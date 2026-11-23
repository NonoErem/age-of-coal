extends SceneTree
## Headless tests for the map, buildings, mines and factories.
##   godot --headless --path . -s tests/sim_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Production = preload("res://sim/production.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func fresh_data(neutral_trend: bool = true) -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["map"] = gd["map"].duplicate(true)
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = 0.0
    if neutral_trend:
        out["balance"]["trend_volatility"] = 0.0
        out["balance"]["trend_reversion"] = 0.0
    return out


func find_deposit(gd: Dictionary, resource: String, richness: float) -> String:
    for id in gd["map"]["deposits"]:
        var d: Dictionary = gd["map"]["deposits"][id]
        if d["resource"] == resource and is_equal_approx(float(d["richness"]), richness):
            return id
    return ""


func pos(gd: Dictionary, dep_id: String) -> Vector2i:
    var d: Dictionary = gd["map"]["deposits"][dep_id]
    return Vector2i(int(d["x"]), int(d["y"]))


func find_free_tile(gd: Dictionary, skip: int = 0) -> Vector2i:
    var taken: Dictionary = {}
    for id in gd["map"]["deposits"]:
        taken[pos(gd, id)] = true
    var n: int = 0
    for y in int(gd["map"]["height"]):
        for x in int(gd["map"]["width"]):
            if not taken.has(Vector2i(x, y)):
                if n == skip:
                    return Vector2i(x, y)
                n += 1
    return Vector2i(-1, -1)


func rich_state(gd: Dictionary) -> Object:
    var gs = GameState.new(gd)
    gs.money_cents = 1000000000
    return gs


func _init() -> void:
    print("Data")
    var errors: Array = DataLoader.validate(DataLoader.load_game_data())
    for e in errors:
        print("    ", e)
    check(errors.is_empty(), "data files and map are consistent")

    print("Placement rules")
    var gd: Dictionary = fresh_data()
    var gs = GameState.new(gd)
    var coal_norm: String = find_deposit(gd, "coal", 1.0)
    var coal_poor: String = find_deposit(gd, "coal", 0.6)
    var p: Vector2i = pos(gd, coal_norm)
    var free: Vector2i = find_free_tile(gd)
    check(gs.build("coal_mine", free.x, free.y)["reason"] == "no_deposit", "a mine needs a deposit")
    check(gs.build("iron_mine", p.x, p.y)["reason"] == "wrong_deposit", "a mine needs the right kind of deposit")
    check(gs.build("coke_oven", p.x, p.y)["reason"] == "deposit_tile_reserved", "factories cannot sit on deposits")
    check(gs.build("coal_mine", -1, 0)["reason"] == "out_of_bounds", "out of bounds is refused")
    var money0: int = gs.money_cents
    var land: int = int(gd["map"]["deposits"][coal_norm]["land_cost"])
    var r: Dictionary = gs.build("coal_mine", p.x, p.y)
    check(r["ok"] and money0 - gs.money_cents == 150000 + land, "mine costs building plus land")
    check(gs.build("coal_mine", p.x, p.y)["reason"] == "tile_occupied", "occupied tile is refused")
    var p2: Vector2i = pos(gd, coal_poor)
    var expected: int = 165000 + int(gd["map"]["deposits"][coal_poor]["land_cost"])
    check(gs.build_cost("coal_mine", coal_poor) == expected, "second mine of a type costs 10%% more (%d)" % expected)
    gs.money_cents = 1000
    check(gs.build("coke_oven", free.x, free.y)["reason"] == "insufficient_funds", "cannot build without the money")

    print("Mines")
    gd = fresh_data()
    gs = rich_state(gd)
    var poor: String = find_deposit(gd, "coal", 0.6)
    var norm: String = find_deposit(gd, "coal", 1.0)
    var rich: String = find_deposit(gd, "coal", 1.5)
    for id in [poor, norm, rich]:
        var q: Vector2i = pos(gd, id)
        gs.build("coal_mine", q.x, q.y)
    for _d in 10:
        gs.advance_day()
    check(gs.stock("coal") == 50 + 10 * (6 + 10 + 15), "richness scales output: poor 6, normal 10, rich 15 per day (stock %d)" % gs.stock("coal"))

    gd = fresh_data()
    gs = rich_state(gd)
    var iron_poor: String = find_deposit(gd, "iron_ore", 0.7)
    var ip: Vector2i = pos(gd, iron_poor)
    gs.build("iron_mine", ip.x, ip.y)
    for _d in 5:
        gs.advance_day()
    check(gs.stock("iron_ore") == 20 + 28, "fractions carry over: 8 x 0.7 x 5 days = 28 (stock %d)" % gs.stock("iron_ore"))

    gd = fresh_data()
    gd["map"]["deposits"][find_deposit(gd, "coal", 1.0)]["amount"] = 100
    gs = rich_state(gd)
    var cp: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    gs.build("coal_mine", cp.x, cp.y)
    var depleted_day: int = -1
    for _d in 200:
        gs.advance_day()
        if depleted_day < 0 and gs.buildings[0]["status"] == "depleted":
            depleted_day = _d + 1
    check(gs.stock("coal") == 50 + 100, "a deposit gives exactly its amount (stock %d)" % gs.stock("coal"))
    check(depleted_day >= 12, "output tapers off before depletion (depleted on day %d, not 10)" % depleted_day)
    check(int(gs.deposits[find_deposit(gd, "coal", 1.0)]["remaining"]) == 0 and gs.buildings[0]["status"] == "depleted", "depleted mine stays built, marked depleted")

    print("Factories")
    gd = fresh_data()
    gs = rich_state(gd)
    var f: Vector2i = find_free_tile(gd)
    gs.build("coke_oven", f.x, f.y)
    gs.inventory["coal"] = 0
    gs.advance_day()
    check(gs.buildings[0]["status"] == "paused_missing_input" and gs.buildings.size() == 1, "no input: factory is paused, not removed")
    check(gs.buildings[0]["missing"] == ["coal"], "paused factory says what is missing")
    gs.inventory["coal"] = 3
    gs.advance_day()
    check(gs.buildings[0]["status"] == "running" and gs.stock("coke") == 2 and gs.stock("coal") == 0, "inputs back: factory restarts on its own")
    gs.advance_day()
    check(gs.buildings[0]["status"] == "paused_missing_input" and gs.buildings.size() == 1, "inputs gone again: paused again")

    gd = fresh_data()
    gs = rich_state(gd)
    var cq: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    gs.build("coal_mine", cq.x, cq.y)
    gs.build("coke_oven", find_free_tile(gd).x, find_free_tile(gd).y)
    gs.inventory["coal"] = 0
    gs.advance_day()
    check(gs.stock("coal") == 1 and gs.stock("coke") == 6, "chain works in build order: mine -> oven runs 3 batches (coal %d, coke %d)" % [gs.stock("coal"), gs.stock("coke")])

    print("Capacity")
    gd = fresh_data()
    gs = rich_state(gd)
    gs.build("coke_oven", find_free_tile(gd).x, find_free_tile(gd).y)
    gs.inventory["coal"] = 100
    gs.advance_day()
    check(gs.stock("coke") == 8 and gs.stock("coal") == 88, "with plenty of coal the oven runs its 4 batches (coke %d)" % gs.stock("coke"))
    gd = fresh_data()
    gs = rich_state(gd)
    gs.build("blast_furnace", find_free_tile(gd).x, find_free_tile(gd).y)
    gs.inventory["iron_ore"] = 10
    gs.inventory["coke"] = 100
    gs.inventory["limestone"] = 100
    gs.advance_day()
    check(gs.stock("pig_iron") == 6 and gs.buildings[0]["batches"] == 2, "limited input limits batches: 10 ore gives 2 batches (pig iron %d)" % gs.stock("pig_iron"))

    print("Upkeep")
    gd = fresh_data()
    gs = rich_state(gd)
    var uq: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    gs.build("coal_mine", uq.x, uq.y)
    var before: int = gs.money_cents
    gs.advance_day()
    check(before - gs.money_cents == 2500, "daily upkeep is charged ($25 for a coal mine)")

    gd = fresh_data()
    gs = rich_state(gd)
    gs.build("coke_oven", find_free_tile(gd).x, find_free_tile(gd).y)
    gs.inventory["coal"] = 0
    before = gs.money_cents
    gs.advance_day()
    check(before - gs.money_cents == 375, "a paused factory pays only 25%% upkeep ($3.75 of $15) (paid %d)" % (before - gs.money_cents))

    gd = fresh_data()
    gd["map"]["deposits"][find_deposit(gd, "coal", 1.0)]["amount"] = 50
    gs = rich_state(gd)
    var dq: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    gs.build("coal_mine", dq.x, dq.y)
    for _d in 100:
        gs.advance_day()
    before = gs.money_cents
    gs.advance_day()
    check(gs.buildings[0]["status"] == "depleted" and before - gs.money_cents == 625, "a depleted mine pays only 25%% upkeep ($6.25 of $25) (paid %d)" % (before - gs.money_cents))

    print("Support for the interface")
    gd = fresh_data(false)
    gs = rich_state(gd)
    check(gs.history["coal"].size() == 1, "price history starts with day 1")
    for _d in 150:
        gs.advance_day()
    check(gs.history["coal"].size() == 120, "price history keeps the last 120 days")
    check(is_equal_approx(gs.history["coal"][-1], gs.market.spot_price("coal")), "latest history point is today's price")

    gd = fresh_data()
    gs = GameState.new(gd)
    var predicted: float = gs.market.pressure_after("coal", 50, false)
    gs.market.execute_sell("coal", 50)
    check(is_equal_approx(predicted, float(gs.market.pressure["coal"])), "pressure_after predicts the real price impact")

    gd = fresh_data()
    gs = rich_state(gd)
    var ev_tile: Vector2i = find_free_tile(gd)
    gs.build("coke_oven", ev_tile.x, ev_tile.y)
    gs.inventory["coal"] = 0
    gs.advance_day()
    check(gs.events.size() == 1 and gs.events[0]["kind"] == "paused" and gs.events[0]["missing"] == ["coal"], "a factory running out of input raises a 'paused' event")
    gs.advance_day()
    check(gs.events.is_empty(), "no new event while it stays paused")
    gs.inventory["coal"] = 9
    gs.advance_day()
    check(gs.events.size() == 1 and gs.events[0]["kind"] == "resumed", "and a 'resumed' event when it restarts")

    gd = fresh_data()
    gd["map"]["deposits"][find_deposit(gd, "coal", 1.0)]["amount"] = 30
    gs = rich_state(gd)
    var ed: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    gs.build("coal_mine", ed.x, ed.y)
    var saw_depleted: bool = false
    for _d in 60:
        gs.advance_day()
        for e in gs.events:
            if e["kind"] == "depleted":
                saw_depleted = true
    check(saw_depleted, "a mine running dry raises a 'depleted' event")

    gd = fresh_data()
    gs = rich_state(gd)
    var cpos: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    check(gs.check_placement("coal_mine", cpos.x, cpos.y) == "" and gs.check_placement("iron_mine", cpos.x, cpos.y) == "wrong_deposit", "check_placement tells where a building can go")

    gd = fresh_data()
    gs = rich_state(gd)
    gs.build("coke_oven", find_free_tile(gd).x, find_free_tile(gd).y)
    gs.inventory["coal"] = 0
    gs.advance_day()
    var predicted_upkeep: int = Production.current_upkeep(gs)
    var m_before: int = gs.money_cents
    gs.advance_day()
    check(predicted_upkeep == 375 and m_before - gs.money_cents == predicted_upkeep, "current_upkeep matches what is charged (paused oven: %d)" % predicted_upkeep)

    gd = fresh_data()
    gs = rich_state(gd)
    var pm: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    gs.build("coal_mine", pm.x, pm.y)
    gs.build("coke_oven", find_free_tile(gd).x, find_free_tile(gd).y)
    gs.inventory["coal"] = 0
    for _d in 60:
        gs.advance_day()
    check(float(gs.market.presence["coal"]) < 2.0 and float(gs.market.presence["coke"]) > 4.0, "coal used by your own oven is not market presence, the coke you make is (coal %.1f, coke %.1f)" % [float(gs.market.presence["coal"]), float(gs.market.presence["coke"])])

    print("Saving with buildings")
    gd = fresh_data(false)
    gs = rich_state(gd)
    var sq: Vector2i = pos(gd, find_deposit(gd, "coal", 1.0))
    var fq: Vector2i = find_free_tile(gd)
    gs.build("coal_mine", sq.x, sq.y)
    gs.build("coke_oven", fq.x, fq.y)
    for _d in 5:
        gs.advance_day()
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(gd, 1)
    check(gs2.load_dict(parsed), "save loads back")
    check(gs2.buildings.size() == 2 and gs2.money_cents == gs.money_cents and gs2.stock("coke") == gs.stock("coke"), "buildings, money and stock survive")
    check(not gs2.build("coal_mine", sq.x, sq.y)["ok"], "occupied tiles survive the save")
    for _d in 5:
        gs.advance_day()
        gs2.advance_day()
    var dep_id: String = find_deposit(gd, "coal", 1.0)
    check(gs.stock("coal") == gs2.stock("coal") and gs.money_cents == gs2.money_cents and gs.deposits[dep_id]["remaining"] == gs2.deposits[dep_id]["remaining"], "a loaded game continues identically")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
