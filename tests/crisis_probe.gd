extends SceneTree
## Sam's crisis probe (informational, not a pass/fail test).
## Plays a fixed small base through the whole timeline, once undefended and once ringed with defenses
## that are kept supplied, and prints what happens: creatures, damage, rivals, prices, shipping limits.
##   godot --headless --path . -s tests/crisis_probe.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Crisis = preload("res://sim/crisis.gd")


func base(gs, defended: bool) -> void:
    gs.money_cents = 50000000
    # A cluster around the middle-left of the map: mines on known deposits plus factories.
    var spots: Array = [["coke_oven", 9, 7], ["blast_furnace", 11, 7], ["steelworks", 13, 8], ["warehouse", 10, 9], ["munitions_works", 12, 10]]
    for s in spots:
        gs.build(s[0], s[1], s[2])
    for id in gs.revealed_deposit_ids():
        var d: Dictionary = gs.data["map"]["deposits"][id]
        if abs(int(d["x"]) - 11) <= 6 and abs(int(d["y"]) - 8) <= 5:
            var kind: String = {"coal": "coal_mine", "iron_ore": "iron_mine", "limestone": "limestone_quarry", "copper_ore": "copper_mine"}[d["resource"]]
            gs.build(kind, int(d["x"]), int(d["y"]))
    if defended:
        for p in [[7, 5], [15, 5], [7, 11], [15, 11], [11, 4], [11, 12]]:
            gs.build("mg_nest", p[0], p[1])
        gs.build("field_battery", 11, 8)
    gs.money_cents = 5000000


func run(defended: bool, seed: int) -> void:
    var gs = GameState.new(DataLoader.load_game_data(), seed)
    base(gs, defended)
    var start_buildings: int = gs.buildings.size()
    var damaged_days: int = 0
    var first_destroy: int = -1
    var max_one_day: int = 0
    print("\n== %s, seed %d: %d buildings ==" % ["DEFENDED" if defended else "UNDEFENDED", seed, start_buildings])
    print("%5s %-9s %5s %6s %6s %6s %5s %6s %7s %7s %s" % ["day", "phase", "alive", "spawn", "kills", "dest", "dmgd", "cap", "coal$", "rail$", "rivals h/w/b (sizes)"])
    for d in 1200:
        if defended:
            # Keep munitions and repair everything every day: what a careful player could do.
            if gs.stock("munitions") < 30:
                gs.inventory["munitions"] = gs.stock("munitions") + 30
            for b in gs.buildings:
                if Crisis.is_damaged(gs, b):
                    gs.money_cents += Crisis.repair_cost(gs, b)
                    gs.repair(int(b["uid"]))
        var before: Dictionary = {}
        for b in gs.buildings:
            before[int(b["uid"])] = int(b["health"])
        gs.advance_day()
        for b in gs.buildings:
            var lost: int = int(before.get(int(b["uid"]), int(b["health"]))) - int(b["health"])
            max_one_day = maxi(max_one_day, lost)
            if Crisis.is_damaged(gs, b):
                damaged_days += 1
        for n in gs.alien_news:
            if n["kind"] == "destroyed" and first_destroy < 0:
                first_destroy = gs.day
        if gs.day % 60 == 0 and gs.day >= 300:
            var h := 0
            var w := 0
            var bk := 0
            var sizes: Array = []
            for id in gs.rivals:
                match str(gs.rivals[id]["status"]):
                    "healthy": h += 1
                    "weakened": w += 1
                    _: bk += 1
                sizes.append("%s%.1f" % [str(id).substr(0, 2), float(gs.rivals[id]["scale"])] if gs.rivals[id]["status"] != "bankrupt" else "%s--" % str(id).substr(0, 2))
            var dmg := 0
            for b in gs.buildings:
                if Crisis.is_damaged(gs, b):
                    dmg += 1
            print("%5d %-9s %5d %6d %6d %6d %5d %6d %7.2f %7.2f %d/%d/%d %s" % [gs.day, str(Crisis.phase(gs).get("name", "")), gs.aliens.size(), int(gs.crisis_stats["spawned"]),
                int(gs.crisis_stats["kills"]), int(gs.crisis_stats["destroyed"]), dmg, gs.market.trade_cap,
                gs.market.spot_price("coal") / 100.0, gs.market.spot_price("rails") / 100.0, h, w, bk, " ".join(sizes)])
    print("buildings left %d of %d, first destroyed on day %s, worst single-day loss on one building %d hp, ammo used %d, repairs $%d" % [
        gs.buildings.size(), start_buildings, str(first_destroy), max_one_day, int(gs.crisis_stats["ammo_used"]), int(gs.crisis_stats["repairs_cents"]) / 100])


func _init() -> void:
    for seed in [1, 2]:
        run(false, seed)
        run(true, seed)
    quit(0)
