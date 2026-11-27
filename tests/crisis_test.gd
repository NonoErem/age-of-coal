extends SceneTree
## The invasion: calendar, economy, shipping limits, creatures, defenses, damage, repairs, rivals, saving.
## Includes Sam's checks: no one-day wipe early on, no save-scumming, no free lunch from repairs.
##   godot --headless --path . -s tests/crisis_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Crisis = preload("res://sim/crisis.gd")
const Companies = preload("res://sim/companies.gd")
const SaveManager = preload("res://game/save_manager.gd")

var checks: int = 0
var failures: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    " + label)
    else:
        failures += 1
        print("  FAIL  " + label)


func data() -> Dictionary:
    var d: Dictionary = DataLoader.load_game_data()
    d["events"]["chance_per_day"] = 0.0
    return d


## A game jumped to the day before `day`, then advanced into it.
func at_day(day: int, seed: int = 7, d: Dictionary = {}) -> Object:
    var gs = GameState.new(data() if d.is_empty() else d, seed)
    gs.day = day - 1
    Crisis.apply_market(gs)
    gs.advance_day()
    return gs


func _init() -> void:
    var gd: Dictionary = data()
    var cfg: Dictionary = gd["crisis"]
    var announce: int = int(cfg["announce_day"])
    var landing: int = int(cfg["landing_day"])

    print("Data")
    check(DataLoader.validate(gd).is_empty(), "the data files are consistent %s" % str(DataLoader.validate(gd)))
    check(announce == 330 and landing == 390, "announced on day 330, landings on day 390")
    var bad: Dictionary = data()
    bad["crisis"]["landing_day"] = 100
    check(not DataLoader.validate(bad).is_empty(), "landings before the announcement are refused")
    var bad2: Dictionary = data()
    bad2["crisis"]["aliens"]["types"] = [{"id": "blob", "hp": 10, "attack": 1, "speed": 1, "weight": 1.0, "weight_per_year": 0.0}]
    check(not DataLoader.validate(bad2).is_empty(), "a crawler type is required (the first landing is a crawler)")

    print("Calendar")
    var gs = GameState.new(data(), 1)
    check(Crisis.date_text(gs, 1) == "1 Jan 1925", "day 1 is 1 Jan 1925")
    check(Crisis.date_text(gs, 60) == "1 Mar 1925" and Crisis.date_text(gs, 366) == "1 Jan 1926", "months and years roll over")
    check(Crisis.date_text(gs, 1155) == "29 Feb 1928", "1928 is a leap year")
    check(Crisis.phase(gs, 1)["id"] == "peace" and Crisis.phase(gs, announce)["id"] == "warning" and Crisis.phase(gs, landing)["id"] == "invasion", "phases follow the calendar")
    check(Crisis.next_phase(gs, 1)["id"] == "warning" and Crisis.next_phase(gs, 5000).is_empty(), "the next phase is known, and the last one never ends")

    print("Peace")
    check(not Crisis.announced(gs) and gs.market.trade_cap == -1 and is_equal_approx(gs.market.spread(), float(gd["balance"]["spread"])), "in peace there is no limit and no extra spread")
    for id in gd["resources"]:
        if not is_equal_approx(float(gs.market.crisis_mult[id]), 1.0):
            check(false, "no crisis effect on %s in peace" % id)
    check(gs.aliens.is_empty(), "no creatures in peace")

    print("The announcement")
    var g2 = at_day(announce)
    check(g2.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "announced" and int(n["landing_day"]) == landing), "the announcement comes on its day, with the landing date")
    check(g2.market.spread() > float(gd["balance"]["spread"]) and g2.market.volatility_mult > 1.0, "markets panic: wider spread, prices swing more")
    check(g2.market.trade_cap == -1 and g2.aliens.is_empty(), "but trade is still open and nothing has landed")
    var g2b = at_day(announce - 1)
    check(not g2b.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "announced"), "nothing is said the day before")

    print("The landing")
    var g3 = at_day(landing)
    check(g3.aliens.size() == 1 and g3.aliens[0]["type"] == "crawler", "the first creature lands on the landing day: one crawler")
    var a0: Dictionary = g3.aliens[0]
    var w: int = int(gd["map"]["width"])
    var h: int = int(gd["map"]["height"])
    check(int(a0["x"]) == 0 or int(a0["y"]) == 0 or int(a0["x"]) == w - 1 or int(a0["y"]) == h - 1, "it lands on the edge of the map")
    check(g3.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "sighting" and bool(n["first"])), "the first sighting is reported as such")
    check(g3.market.trade_cap == int(cfg["access"]["trade_cap_start"]), "shipping is limited from the landing: %d a day" % g3.market.trade_cap)
    var g4 = at_day(landing + 180)
    check(abs(g4.market.trade_cap - int(cfg["access"]["trade_cap_start"]) / 2) <= 1, "the limit halves every %d days" % int(cfg["access"]["trade_cap_halving_days"]))
    var g5 = at_day(landing + 3000)
    check(g5.market.trade_cap == int(cfg["access"]["trade_cap_min"]), "but never falls below %d" % int(cfg["access"]["trade_cap_min"]))

    print("The economy crashes")
    var y1 = at_day(landing + 365)
    check(float(y1.market.crisis_mult["rails"]) < float(y1.market.crisis_mult["steel"]) and float(y1.market.crisis_mult["steel"]) < 1.0, "a year in, rails have fallen more than steel, and steel has fallen")
    check(float(y1.market.crisis_mult["munitions"]) > 1.2, "munitions are dearer")
    check(y1.market.depth("coal") < GameState.new(data(), 7).market.depth("coal"), "markets are thinner")
    check(Crisis.contract_mult(y1) < 1.0 and Crisis.contract_mult(at_day(landing + 5000)) >= float(cfg["access"]["min_contract_mult"]), "contract offers become rarer, never quite stop")
    var y9 = at_day(landing + 4000)
    for id in gd["resources"]:
        var m: float = float(y9.market.crisis_mult[id])
        if m < float(cfg["economy"]["min_mult"]) - 0.0001 or m > float(cfg["economy"]["max_mult"]) + 0.0001:
            check(false, "the crisis multiplier of %s stays within its limits" % id)
    check(y9.market.spread() <= float(gd["balance"]["spread"]) + float(cfg["access"]["warning_spread"]) + float(cfg["access"]["max_extra_spread"]) + 0.0001, "the spread is capped")

    print("Shipping limits")
    var sl = at_day(landing + 400)
    sl.money_cents = 100000000
    sl.inventory = {"coal": 0}
    var cap: int = sl.market.trade_cap
    var r1: Dictionary = sl.buy("coal", cap + 1)
    check(not r1["ok"] and r1["reason"] == "market_limit" and int(r1["room"]) == cap, "buying past the limit is refused, with what is left")
    check(sl.buy("coal", cap)["ok"] and sl.market.trade_room("coal") == 0, "up to the limit is fine, then the day is used up")
    check(not sl.sell("coal", 1)["ok"], "selling counts against the same limit")
    check(sl.market.trade_room("iron_ore") == cap, "each good has its own limit")
    sl.advance_day()
    check(sl.market.trade_room("coal") == sl.market.trade_cap, "the limit resets the next day")
    sl.inventory["coal"] = 0
    sl.add_rule("coal", "keep", 5000)
    sl.advance_day()
    check(sl.stock("coal") <= sl.market.trade_cap + 1 and str(sl.rules[0]["last_result"]) == "partial_limit", "a rule buys only what shipping allows and says so")
    sl.start_standing_order("coal", "sell", 400, 3)
    var before_coal: int = sl.stock("coal")
    sl.advance_day()
    check(before_coal - sl.stock("coal") <= sl.market.trade_cap + 50, "a standing order is clipped too")

    print("Creatures attack")
    var gb = GameState.new(data(), 3)
    gb.money_cents = 50000000
    gb.build("coke_oven", 20, 12)
    var oven: Dictionary = gb.buildings[0]
    gb.inventory["coal"] = 100
    gb.day = landing + 10
    Crisis.apply_market(gb)
    gb.aliens = [{"id": 99, "type": "crawler", "x": 24, "y": 12, "hp": 40, "max_hp": 40, "attack": 6, "speed": 2, "age": 0, "wander_x": 20, "wander_y": 12}]
    gb.data["crisis"]["aliens"]["spawn_base"] = 0.0
    gb.data["crisis"]["aliens"]["spawn_growth_per_day"] = 0.0
    gb.advance_day()
    check(int(gb.aliens[0]["x"]) == 22 and int(oven["health"]) == 120, "a crawler walks 2 tiles a day towards your nearest building")
    gb.advance_day()
    check(int(gb.aliens[0]["x"]) == 21 and int(oven["health"]) == 114, "and attacks it once next to it")
    check(oven["status"] == "damaged" and gb.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "attacked"), "the building is damaged and you are told")
    var coke_before: int = gb.stock("coke")
    gb.advance_day()
    check(gb.stock("coke") == coke_before and oven["status"] == "damaged", "a damaged building makes nothing")
    check(gb.last_report["upkeep_cents"] < int(gd["buildings"]["coke_oven"]["upkeep_per_day"]), "and pays only idle upkeep")
    check(not gb.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "attacked"), "the attack is announced once, not every day")
    var cost: int = gb.repair_cost(int(oven["uid"]))
    var expect: int = int(ceil(float(gd["buildings"]["coke_oven"]["build_cost"]) * 0.5 * float(120 - int(oven["health"])) / 120.0))
    check(cost == expect, "repairs cost half the build price for full damage, in proportion (%s)" % cost)
    var cash: int = gb.money_cents
    check(gb.repair(int(oven["uid"]))["ok"] and int(oven["health"]) == 120 and gb.money_cents == cash - cost and oven["status"] == "built", "repairing restores it and charges")
    check(not gb.repair(int(oven["uid"]))["ok"], "an intact building cannot be repaired")
    check(gb.check_placement("warehouse", int(gb.aliens[0]["x"]), int(gb.aliens[0]["y"])) == "alien_here", "nothing can be built under a creature")
    oven["health"] = 4
    gb.advance_day()
    check(gb.buildings.is_empty() and not gb.tile_owner.has(gb.tile_key(20, 12)), "at zero health the building is destroyed and the tile freed")
    check(gb.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "destroyed") and int(gb.crisis_stats["destroyed"]) == 1, "and you are told")
    for d in 20:
        gb.advance_day()
    check(gb.aliens.is_empty(), "with nothing left to attack, creatures wander off")

    print("A mine on a deposit")
    var gm = GameState.new(data(), 3)
    gm.money_cents = 50000000
    var dep: String = gm.revealed_deposit_ids()[0]
    var dd: Dictionary = gd["map"]["deposits"][dep]
    var mine_kind: String = {"coal": "coal_mine", "iron_ore": "iron_mine", "limestone": "limestone_quarry", "copper_ore": "copper_mine"}[dd["resource"]]
    gm.build(mine_kind, int(dd["x"]), int(dd["y"]))
    gm.buildings[0]["health"] = 1
    gm.day = landing + 5
    Crisis.apply_market(gm)
    gm.aliens = [{"id": 1, "type": "strider", "x": int(dd["x"]) + 1, "y": int(dd["y"]), "hp": 100, "max_hp": 100, "attack": 14, "speed": 1, "age": 0, "wander_x": 5, "wander_y": 5}]
    gm.advance_day()
    check(gm.buildings.is_empty() and gm.deposit_id_at(int(dd["x"]), int(dd["y"])) == dep and gm.check_placement(mine_kind, int(dd["x"]), int(dd["y"])) in ["", "alien_here"], "a destroyed mine leaves its deposit: you can build again")

    print("Defenses")
    var gdf = GameState.new(data(), 4)
    gdf.money_cents = 50000000
    gdf.build("coke_oven", 20, 12)
    gdf.build("mg_nest", 21, 12)
    var nest: Dictionary = gdf.buildings[1]
    check(nest["status"] == "ready" and int(nest["health"]) == 160, "a new nest is ready, with its own health")
    gdf.day = landing + 10
    Crisis.apply_market(gdf)
    gdf.data["crisis"]["aliens"]["spawn_base"] = 0.0
    gdf.data["crisis"]["aliens"]["spawn_growth_per_day"] = 0.0
    gdf.inventory["munitions"] = 0
    gdf.aliens = [{"id": 1, "type": "crawler", "x": 23, "y": 12, "hp": 40, "max_hp": 40, "attack": 6, "speed": 1, "age": 0, "wander_x": 5, "wander_y": 5}]
    gdf.advance_day()
    check(nest["status"] == "no_ammo" and int(gdf.aliens[0]["hp"]) == 40, "without munitions it does not fire")
    check(gdf.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "no_ammo"), "and says so")
    gdf.advance_day()
    check(not gdf.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "no_ammo"), "once, not every day")
    gdf.inventory["munitions"] = 5
    gdf.advance_day()
    check(nest["status"] == "firing" and gdf.stock("munitions") == 4 and int(gdf.aliens[0]["hp"]) == 10, "with munitions it fires: 30 damage for one munition")
    gdf.advance_day()
    check(gdf.aliens.is_empty() and int(gdf.crisis_stats["kills"]) == 1 and gdf.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "killed"), "and kills the crawler")
    gdf.advance_day()
    check(nest["status"] == "ready" and gdf.stock("munitions") == 3, "nothing in reach: no munitions used")
    gdf.aliens = [{"id": 2, "type": "crawler", "x": 22, "y": 12, "hp": 300, "max_hp": 300, "attack": 6, "speed": 1, "age": 0, "wander_x": 5, "wander_y": 5}]
    gdf.advance_day()
    check(int(nest["health"]) < 160 and gdf.buildings[0]["status"] != "damaged", "the nest stands in front and takes the hits")
    check(nest["status"] == "firing", "a damaged defense keeps firing")
    gdf.set_building_stopped(int(nest["uid"]), true)
    var hp_before: int = int(gdf.aliens[0]["hp"])
    gdf.advance_day()
    check(int(gdf.aliens[0]["hp"]) == hp_before, "a stopped defense does not fire")
    check(Crisis.covered_by(gdf, 20, 12).size() == 1 and Crisis.covered_by(gdf, 20, 20).is_empty(), "cover: who protects a tile")

    print("Sam: the first months of the invasion")
    var worst: int = 0
    var destroyed_from_full: bool = false
    for seed in [11, 12, 13]:
        var gs2 = GameState.new(data(), seed)
        gs2.money_cents = 50000000
        for spot in [[9, 7], [11, 7], [13, 8], [10, 9], [12, 10]]:
            gs2.build("warehouse", spot[0], spot[1])
        gs2.day = landing - 1
        Crisis.apply_market(gs2)
        for d in 120:
            var hp: Dictionary = {}
            for b in gs2.buildings:
                hp[int(b["uid"])] = int(b["health"])
            gs2.advance_day()
            var alive: Dictionary = {}
            for b in gs2.buildings:
                alive[int(b["uid"])] = true
                worst = maxi(worst, int(hp.get(int(b["uid"]), int(b["health"]))) - int(b["health"]))
            for uid in hp:
                if not alive.has(uid) and int(hp[uid]) >= 90:
                    destroyed_from_full = true
    check(worst <= 45, "in the first 120 days no building loses more than half a warehouse's health (45) in a day (worst %d)" % worst)
    check(not destroyed_from_full, "and none goes from full health to nothing in one day")

    print("Sam: reloading does not change what comes")
    var ga = GameState.new(data(), 21)
    ga.money_cents = 50000000
    ga.build("coke_oven", 20, 12)
    ga.day = landing - 1
    Crisis.apply_market(ga)
    for d in 40:
        ga.advance_day()
    var saved: Dictionary = JSON.parse_string(JSON.stringify(ga.to_dict()))
    for d in 30:
        ga.advance_day()
    var gl = GameState.new(data(), 999)
    check(gl.load_dict(saved), "a game in the middle of the invasion loads")
    for d in 30:
        gl.advance_day()
    check(JSON.stringify(gl.aliens) == JSON.stringify(ga.aliens) and int(gl.crisis_stats["spawned"]) == int(ga.crisis_stats["spawned"]), "the same creatures come, in the same places")
    check(gl.buildings.size() == ga.buildings.size() and (gl.buildings.is_empty() or int(gl.buildings[0]["health"]) == int(ga.buildings[0]["health"])), "and do the same damage")
    check(gl.market.trade_cap == ga.market.trade_cap and is_equal_approx(gl.market.spread(), ga.market.spread()), "the crisis market comes back with the calendar")
    var old: Dictionary = saved.duplicate(true)
    old["version"] = 9
    check(not GameState.new(data(), 1).load_dict(old), "saves from before the invasion (version 9) are refused")
    var broken: Dictionary = saved.duplicate(true)
    broken["crisis"].erase("rng_state")
    check(not GameState.new(data(), 1).load_dict(broken), "a damaged crisis section is refused, not crashed on")

    print("Rivals")
    var gr = at_day(landing + 200, 5)
    var grew: bool = false
    var sizes: Dictionary = {}
    for id in gr.rivals:
        sizes[id] = float(gr.rivals[id]["scale"])
    for d in 60:
        gr.advance_day()
    for id in gr.rivals:
        if float(gr.rivals[id]["scale"]) > float(sizes[id]) + 0.0001:
            grew = true
    check(not grew, "nobody expands during the invasion")
    var gx = at_day(landing + 10, 5)
    var some: String = gx.rivals.keys()[0]
    Companies._go_bankrupt(gx, some)
    for d in int(gd["companies"]["revival_days"]) + 10:
        gx.advance_day()
    check(gx.rivals[some]["status"] == "bankrupt", "a rival that fails after the landing is not restarted by investors")
    gx.money_cents = 1000000000
    check(gx.buy_company(some)["ok"] and gx.rivals[some]["status"] == "weakened", "but you can still buy it and restart it")
    var small: int = Crisis.rival_burden(gr, 10000, 1.0)
    var big: int = Crisis.rival_burden(gr, 10000, 3.0)
    check(small > 0 and float(big) / 3.0 < float(small), "the crisis burden weighs less, size for size, on big companies")
    check(Crisis.rival_burden(at_day(landing - 5), 10000, 1.0) == 0, "and none before the landing")

    print("Night falls")
    var gn = GameState.new(data(), 1)
    var nc: Dictionary = cfg["night"]
    check(Crisis.night(gn, announce - 1) == 0.0 and Crisis.night_tint(gn, 1) == Color.WHITE, "broad daylight until the announcement")
    check(Crisis.night(gn, announce + 30) > 0.0 and Crisis.night(gn, announce + 30) < float(nc["dusk_at_landing"]), "it starts to darken during the warning")
    check(is_equal_approx(Crisis.night(gn, landing), float(nc["dusk_at_landing"])), "dusk by the landing")
    var prev: float = -1.0
    var rising: bool = true
    for dd2 in range(landing, landing + 900, 30):
        if Crisis.night(gn, dd2) < prev:
            rising = false
        prev = Crisis.night(gn, dd2)
    check(rising, "darker every month")
    check(is_equal_approx(Crisis.night(gn, landing + 5000), float(nc["max"])) and float(nc["max"]) <= 0.8, "and capped, so the screen stays readable")
    var bad3: Dictionary = data()
    bad3["crisis"]["night"]["max"] = 0.95
    check(not DataLoader.validate(bad3).is_empty(), "a night too dark to read is refused")

    print("Switched off")
    var off: Dictionary = data()
    off["crisis"] = {"enabled": false}
    var go = GameState.new(off, 2)
    go.day = 1000
    Crisis.apply_market(go)
    go.advance_day()
    check(go.aliens.is_empty() and go.market.trade_cap == -1 and is_equal_approx(float(go.market.crisis_mult["rails"]), 1.0), "\"enabled\": false gives the old game")

    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
