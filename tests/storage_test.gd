extends SceneTree
## Headless tests for storage, stopping buildings and demolishing them.
##   godot --headless --path . -s tests/storage_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Production = preload("res://sim/production.gd")
const Contracts = preload("res://sim/contracts.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func data_with(base_storage: int = 250) -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["balance"]["trend_volatility"] = 0.0
    out["balance"]["trend_reversion"] = 0.0
    out["balance"]["base_storage"] = base_storage
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = 0.0
    out["map"] = gd["map"].duplicate(true)
    out["buildings"] = gd["buildings"].duplicate(true)
    return out


func rich(gd: Dictionary) -> Object:
    var gs = GameState.new(gd)
    gs.money_cents = 1000000000
    return gs


func coal_tile(gd: Dictionary) -> Vector2i:
    var d: Dictionary = gd["map"]["deposits"]["coal_2"]
    return Vector2i(int(d["x"]), int(d["y"]))


func free_tile(gd: Dictionary, skip: int = 0) -> Vector2i:
    var n: int = 0
    for y in int(gd["map"]["height"]):
        for x in int(gd["map"]["width"]):
            var on_deposit: bool = false
            for id in gd["map"]["deposits"]:
                if int(gd["map"]["deposits"][id]["x"]) == x and int(gd["map"]["deposits"][id]["y"]) == y:
                    on_deposit = true
            if not on_deposit:
                if n == skip:
                    return Vector2i(x, y)
                n += 1
    return Vector2i(-1, -1)


func has_event(gs, kind: String) -> bool:
    for e in gs.events:
        if e["kind"] == kind:
            return true
    return false


func _init() -> void:
    print("Capacity")
    var gd: Dictionary = data_with()
    var gs = rich(gd)
    check(DataLoader.validate(DataLoader.load_game_data()).is_empty(), "the data (with warehouses) is valid")
    check(gs.capacity() == 250 and gs.stored_units() == 70 and gs.free_space() == 180, "the open yard holds 250 units, 70 are in it (%d free)" % gs.free_space())
    var w1: Dictionary = gs.build("warehouse", free_tile(gd).x, free_tile(gd).y)
    check(w1["ok"] and gs.capacity() == 750, "a warehouse adds 500 units")
    var w2_cost: int = gs.build_cost("warehouse")
    check(w2_cost == 88000, "the next one costs 10%% more ($880, got %d)" % w2_cost)
    var coal: Vector2i = coal_tile(gd)
    check(gs.build("warehouse", coal.x, coal.y)["reason"] == "deposit_tile_reserved", "warehouses go on free ground, not on deposits")
    gs.build("warehouse", free_tile(gd, 1).x, free_tile(gd, 1).y)
    check(gs.capacity() == 1250, "two warehouses make 1,250")

    print("Buying needs room")
    gd = data_with()
    gs = rich(gd)
    var r: Dictionary = gs.buy("coal", 200)
    check(not r["ok"] and r["reason"] == "storage_full" and r["free"] == 180, "you cannot buy more than the free room (180)")
    check(gs.buy("coal", 180)["ok"] and gs.free_space() == 0, "buying exactly what fits works")
    check(gs.buy("coal", 1)["reason"] == "storage_full", "and then nothing more fits")
    gs.sell("coal", 10)
    check(gs.free_space() == 10 and gs.buy("steel", 10)["ok"], "selling makes room")

    print("Mines stop when storage is full")
    gd = data_with(25)
    gs = rich(gd)
    gs.inventory = {}
    var pm: Vector2i = coal_tile(gd)
    gs.build("coal_mine", pm.x, pm.y)
    gs.advance_day()
    gs.advance_day()
    check(gs.stock("coal") == 20 and gs.buildings[0]["status"] == "running", "while there is room it digs (20 coal)")
    gs.advance_day()
    check(gs.stock("coal") == 25 and gs.buildings[0]["status"] == "running", "it fills the last 5 units and stops there (partial day)")
    var remaining: int = int(gs.deposits["coal_2"]["remaining"])
    gs.advance_day()
    check(gs.buildings[0]["status"] == "paused_storage_full" and has_event(gs, "blocked"), "next day it is blocked and says so")
    check(int(gs.deposits["coal_2"]["remaining"]) == remaining and gs.stock("coal") == 25, "a blocked mine digs nothing: the deposit is not used up")
    check(gs.buildings[0]["carry"].get("coal", 0.0) < 1.0, "and no output piles up in secret")
    var before: int = gs.money_cents
    gs.advance_day()
    check(before - gs.money_cents == 625, "a blocked mine only pays idle upkeep ($6.25)")
    gs.sell("coal", 10)
    gs.advance_day()
    check(gs.buildings[0]["status"] == "running" and gs.stock("coal") == 25 and has_event(gs, "resumed"), "with room again it restarts by itself")

    print("A recipe that makes more than it uses")
    gd = data_with(100)
    gd["buildings"]["duplicator"] = {"id": "duplicator", "name": "Duplicator", "symbol": "Dp", "kind": "factory", "batches_per_day": 4,
        "build_cost": 1000, "upkeep_per_day": 100, "inputs": {"coal": 1}, "outputs": {"coke": 3}, "cycle_days": 1}
    gs = rich(gd)
    gs.inventory = {"coal": 50}
    gs.build("duplicator", free_tile(gd).x, free_tile(gd).y)
    # 50 stored, 100 capacity: room for 50 more; each batch adds 2 net units.
    gs.advance_day()
    check(gs.stock("coke") == 12 and gs.stock("coal") == 46 and gs.buildings[0]["batches"] == 4, "with plenty of room all 4 batches run")
    gs.inventory = {"coal": 50, "coke": 47}
    gs.advance_day()
    check(gs.buildings[0]["batches"] == 1 and gs.stock("coke") == 50, "with room for 3 more units only 1 batch fits (net +2)")
    gs.inventory = {"coal": 50, "coke": 50}
    gs.advance_day()
    check(gs.buildings[0]["status"] == "paused_storage_full" and gs.buildings[0]["missing"].is_empty(), "with no room it is blocked, not 'missing input'")

    print("Stopping a building")
    gd = data_with(100000)
    gs = rich(gd)
    var sm: Vector2i = coal_tile(gd)
    gs.build("coal_mine", sm.x, sm.y)
    gs.build("coke_oven", free_tile(gd).x, free_tile(gd).y)
    var uid_mine: int = int(gs.buildings[0]["uid"])
    var uid_oven: int = int(gs.buildings[1]["uid"])
    gs.advance_day()
    check(gs.buildings[0]["status"] == "running" and Contracts.production_rate(gs, "coal") == 10.0, "a running mine counts as production")
    check(gs.set_building_stopped(uid_mine, true)["ok"] and gs.buildings[0]["status"] == "stopped", "a building can be stopped")
    var coal_before: int = gs.stock("coal")
    var remaining2: int = int(gs.deposits["coal_2"]["remaining"])
    before = gs.money_cents
    gs.advance_day()
    check(gs.stock("coal") <= coal_before and int(gs.deposits["coal_2"]["remaining"]) == remaining2, "a stopped mine digs nothing")
    check(Contracts.production_rate(gs, "coal") == 0.0, "and does not count towards contract offers")
    check(not gs.events.any(func(e: Dictionary) -> bool: return e["uid"] == uid_mine), "stopping it yourself is not reported as an event")
    gs.set_building_stopped(uid_oven, true)
    gs.inventory["coal"] = 100
    gs.advance_day()
    check(gs.stock("coal") == 100, "a stopped oven keeps its coal")
    before = gs.money_cents
    gs.advance_day()
    check(before - gs.money_cents == 625 + 375, "both pay a quarter of their upkeep ($6.25 + $3.75)")
    gs.set_building_stopped(uid_mine, false)
    check(gs.buildings[0]["status"] == "built", "resuming marks it to start on the next day")
    gs.advance_day()
    check(gs.buildings[0]["status"] == "running" and gs.stock("coal") == 110, "and it digs again")
    gs.build("warehouse", free_tile(gd, 3).x, free_tile(gd, 3).y)
    check(gs.set_building_stopped(int(gs.buildings[2]["uid"]), true)["reason"] == "cannot_stop" and gs.set_building_stopped(9999, true)["reason"] == "unknown_building", "storage cannot be stopped, unknown buildings are refused")

    print("Demolishing")
    gd = data_with(100000)
    gs = rich(gd)
    var dm: Vector2i = coal_tile(gd)
    var start_money: int = gs.money_cents
    var r1: Dictionary = gs.build("coal_mine", dm.x, dm.y)
    var uid: int = int(r1["uid"])
    check(gs.demolish_refund(uid) == 60000, "the refund is 30%% of what was paid, land included ($600 of $2,000)")
    var d1: Dictionary = gs.demolish(uid)
    check(d1["ok"] and d1["refund"] == 60000 and gs.buildings.is_empty() and start_money - gs.money_cents == 140000, "demolishing removes it and refunds 30%% (net cost $1,400)")
    check(gs.check_placement("coal_mine", dm.x, dm.y) == "" and gs.build_cost("coal_mine", "coal_2") == 200000, "the tile is free again and the price is back to normal")
    for _i in 3:
        var rr: Dictionary = gs.build("coal_mine", dm.x, dm.y)
        gs.demolish(int(rr["uid"]))
    check(start_money - gs.money_cents == 4 * 140000, "building and demolishing in a loop only loses money (Sam)")
    check(gs.demolish(9999)["reason"] == "unknown_building", "an unknown building is refused")

    gd = data_with(100000)
    gd["map"]["deposits"]["coal_2"]["amount"] = 20
    gs = rich(gd)
    gs.build("coal_mine", dm.x, dm.y)
    for _d in 40:
        gs.advance_day()
    check(gs.buildings[0]["status"] == "depleted", "a mine runs dry")
    check(gs.demolish(int(gs.buildings[0]["uid"]))["ok"] and Production.current_upkeep(gs) == 0, "and can be demolished, so it stops costing upkeep")

    gd = data_with()
    gs = rich(gd)
    gs.build("warehouse", free_tile(gd).x, free_tile(gd).y)
    gs.buy("coal", 600)
    check(gs.stored_units() == 670 and gs.demolish(int(gs.buildings[0]["uid"]))["reason"] == "storage_in_use", "a warehouse cannot go while the stock would not fit without it")
    gs.sell("coal", 600)
    check(gs.demolish(int(gs.buildings[0]["uid"]))["ok"] and gs.capacity() == 250, "once there is room to spare it can")

    print("Contracts respect storage (Sam)")
    gd = data_with(100)
    gs = rich(gd)
    gs.inventory = {}
    check(Contracts.max_deliverable(gs, "steel", 10) <= 100, "no offer for more than you could ever store and buy (%d)" % Contracts.max_deliverable(gs, "steel", 10))

    print("Saving")
    gd = data_with(60)
    gs = rich(gd)
    gs.build("coal_mine", dm.x, dm.y)
    gs.build("coke_oven", free_tile(gd).x, free_tile(gd).y)
    gs.set_building_stopped(int(gs.buildings[1]["uid"]), true)
    for _d in 6:
        gs.advance_day()
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(gd, 1)
    check(gs2.load_dict(parsed), "a game with stopped and blocked buildings loads")
    check(gs2.buildings[1]["stopped"] == true and int(gs2.buildings[0]["paid"]) == int(gs.buildings[0]["paid"]) and gs2.buildings[0]["status"] == gs.buildings[0]["status"], "stopped, paid and status come back")
    check(gs2.demolish_refund(int(gs2.buildings[0]["uid"])) == gs.demolish_refund(int(gs.buildings[0]["uid"])), "the refund is the same after loading")
    for _d in 10:
        gs.advance_day()
        gs2.advance_day()
    check(gs.stock("coal") == gs2.stock("coal") and gs.money_cents == gs2.money_cents, "the loaded game goes on identically")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
