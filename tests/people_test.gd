extends SceneTree
## People: crews, hired workers, your people in shelters, food in granaries, searchlights in the dark.
##   godot --headless --path . -s tests/people_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Crisis = preload("res://sim/crisis.gd")
const Production = preload("res://sim/production.gd")
const People = preload("res://sim/people.gd")

var checks: int = 0
var failures: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    " + label)
    else:
        failures += 1
        print("  FAIL  " + label)


func near(a: float, b: float, eps: float = 0.0005) -> bool:
    return absf(a - b) < eps


func data() -> Dictionary:
    var d: Dictionary = DataLoader.load_game_data()
    d["events"]["chance_per_day"] = 0.0
    d["crisis"]["aliens"]["spawn_base"] = 0.0
    d["crisis"]["aliens"]["spawn_growth_per_day"] = 0.0
    d["companies"]["take_contracts"] = false
    return d


func game_at(day: int) -> Object:
    var gs = GameState.new(data(), 3)
    gs.day = day
    gs.money_cents = 1000000000
    Crisis.apply_market(gs)
    return gs


func put(gs, id: String, x: int, y: int) -> Dictionary:
    var r: Dictionary = gs.build(id, x, y)
    if not r["ok"]:
        print("    could not place %s at %d,%d: %s" % [id, x, y, str(r)])
        return {}
    return gs.building_by_uid(int(r["uid"]))


## A free tile near (x, y) for a building that does not need a deposit.
func free_near(gs, id: String, x: int, y: int) -> Vector2i:
    for rr in range(0, 6):
        for dy in range(-rr, rr + 1):
            for dx in range(-rr, rr + 1):
                if gs.check_placement(id, x + dx, y + dy) == "":
                    return Vector2i(x + dx, y + dy)
    return Vector2i(-1, -1)


func put_near(gs, id: String, x: int, y: int) -> Dictionary:
    var p: Vector2i = free_near(gs, id, x, y)
    return put(gs, id, p.x, p.y)


func _init() -> void:
    var gd: Dictionary = data()
    var landing: int = int(gd["crisis"]["landing_day"])
    var lb: Dictionary = gd["crisis"]["labour"]
    var pp: Dictionary = gd["balance"]["people"]

    print("Data")
    check(DataLoader.validate(gd).is_empty(), "the data is consistent %s" % str(DataLoader.validate(gd)))
    var bad: Dictionary = data()
    bad["balance"]["people"]["ration"] = 0.0
    check(not DataLoader.validate(bad).is_empty(), "people who eat nothing are refused")
    var bad2: Dictionary = data()
    bad2["buildings"]["granary"]["food_capacity"] = 0
    check(not DataLoader.validate(bad2).is_empty(), "a granary that keeps nothing is refused")
    var bad3: Dictionary = data()
    bad3["crisis"]["labour"]["max_discount"] = 1.0
    check(not DataLoader.validate(bad3).is_empty(), "free work (100% discount) is refused")
    var bad4: Dictionary = data()
    bad4["buildings"]["searchlight"]["crew"] = 0
    check(not DataLoader.validate(bad4).is_empty(), "a searchlight with no crew is refused")
    for id in gd["buildings"]:
        if not gd["buildings"][id].has("crew"):
            check(false, "%s has a crew" % id)

    print("Before the landing: everyone is hired, nothing changes")
    var g0 = game_at(20)
    var oven0: Dictionary = put_near(g0, "coke_oven", 12, 10)
    var mine0: Dictionary = put_near(g0, "warehouse", 14, 10)
    check(int(oven0["crew_hired"]) == 5 and int(oven0["crew_yours"]) == 0 and People.crew_ratio(g0, oven0) == 1.0, "a coke oven has its 5 hired workers")
    check(near(People.upkeep_mult(g0, oven0), 1.0), "so it pays exactly its listed upkeep")
    check(Production.current_upkeep(g0) == int(gd["buildings"]["coke_oven"]["upkeep_per_day"]) + int(gd["buildings"]["warehouse"]["upkeep_per_day"]), "the bill is the listed upkeep")
    check(g0.people == 0, "nobody lives with you")
    var sh0: Dictionary = put_near(g0, "shelter", 10, 12)
    put_near(g0, "mg_nest", 11, 12)
    g0.inventory["munitions"] = 10
    put_near(g0, "granary", 9, 12)
    g0.buy("food", 100)
    for i in 10:
        g0.advance_day()
    check(g0.people == 0 and str(sh0["status"]) == "ready", "even with a shelter, a defense and food: refugees come only after the landing")

    print("Food lives in granaries")
    var gf = game_at(20)
    var r: Dictionary = gf.buy("food", 10)
    check(not r["ok"] and str(r["reason"]) == "granary_full", "no granary, no food (%s)" % str(r.get("reason", "")))
    var gran: Dictionary = put_near(gf, "granary", 12, 10)
    check(gf.food_capacity() == 400 and gf.room_for("food") == 400, "a granary keeps 400 food")
    var yard_before: int = gf.stored_units()
    check(gf.buy("food", 400)["ok"], "buy 400 food")
    check(gf.stored_units() == yard_before and gf.free_space() == gf.capacity() - yard_before, "food does not take room in the yard")
    check(not gf.buy("food", 1)["ok"], "a full granary takes no more")
    check(gf.buy("coal", 10)["ok"], "the yard still takes coal")
    var unit_food: int = gf.market.quote_buy("food", 10)
    var unit_coal: int = gf.market.quote_buy("coal", 10)
    check(unit_food < unit_coal, "food is cheap (%d against %d for 10 coal)" % [unit_food, unit_coal])
    gf.advance_day()
    check(gf.stock("food") == 398, "400 food spoils 0.5%%: 2 a day (%d)" % gf.stock("food"))
    var gs2 = game_at(20)
    put_near(gs2, "granary", 12, 10)
    gs2.buy("food", 10)
    for i in 20:
        gs2.advance_day()
    check(gs2.stock("food") == 9, "a small stock spoils too, slowly: 10 food loses 1 in 20 days (%d)" % gs2.stock("food"))
    check(gf.set_building_stopped(int(gran["uid"]), true)["ok"] == false, "a granary cannot be stopped")
    var rules_ok: Dictionary = gf.add_rule("food", "keep", 300)
    check(rules_ok["ok"], "rules can keep food in stock")

    print("Hiring after the landing")
    var g = game_at(landing)
    var oven: Dictionary = put_near(g, "coke_oven", 12, 10)
    check(near(Crisis.hire_share(g, int(oven["x"]), int(oven["y"])), 0.7), "at the landing, 70% of the places on open ground find a hand")
    check(int(oven["crew_hired"]) == 4 and near(People.crew_ratio(g, oven), 0.8), "so an exposed coke oven has 4 of 5")
    var bat: Dictionary = put_near(g, "field_battery", int(oven["x"]) + 1, int(oven["y"]))
    g.inventory["munitions"] = 50
    People.staff(g)
    check(near(Crisis.hire_share(g, int(oven["x"]), int(oven["y"])), 1.0) and int(oven["crew_hired"]) == 5, "under a supplied battery it has all 5")
    g.inventory["munitions"] = 0
    People.staff(g)
    check(int(oven["crew_hired"]) == 4, "a battery with no munitions makes nobody feel safe")
    g.inventory["munitions"] = 50
    var g1 = game_at(landing + 365)
    var o1: Dictionary = put_near(g1, "coke_oven", 12, 10)
    check(near(Crisis.hire_share(g1, int(o1["x"]), int(o1["y"])), 0.3), "a year on, 30% on open ground")
    var b1: Dictionary = put_near(g1, "field_battery", int(o1["x"]) + 1, int(o1["y"]))
    g1.inventory["munitions"] = 50
    People.staff(g1)
    check(near(Crisis.hire_share(g1, int(o1["x"]), int(o1["y"])), 0.7), "and 70% on protected ground")
    var g5 = game_at(landing + 365 * 5)
    var o5: Dictionary = put_near(g5, "coke_oven", 12, 10)
    check(near(Crisis.hire_share(g5, int(o5["x"]), int(o5["y"])), float(lb["hire_exposed_min"])), "never below the floor")

    print("Wages and upkeep")
    var w: float = float(pp["wage_share"])
    var disc: float = Crisis.labour_discount(g1, int(o1["x"]), int(o1["y"]))
    var hired_share: float = float(int(o1["crew_hired"])) / 5.0
    check(near(People.upkeep_mult(g1, o1), (1.0 - w) + w * hired_share * (1.0 - disc)), "upkeep = maintenance + wages of the hired, lowered on safe ground (%.3f)" % People.upkeep_mult(g1, o1))
    var idle: float = float(gd["balance"]["idle_upkeep_factor"])
    var defo: Dictionary = gd["buildings"]["coke_oven"]
    check(Production.upkeep_of(defo, "paused_missing_input", idle, People.upkeep_mult(g1, o1)) == int(round(float(defo["upkeep_per_day"]) * People.upkeep_mult(g1, o1) * idle)), "idle upkeep is a share of today's lower bill")

    print("Short crews work in proportion")
    var gp = game_at(landing + 365)
    gp.inventory["coal"] = 2000
    var op: Dictionary = put_near(gp, "coke_oven", 30, 18)
    People.staff(gp)
    var ratio: float = People.crew_ratio(gp, op)
    check(ratio > 0.0 and ratio < 1.0, "an exposed oven a year in is short-handed (%.2f)" % ratio)
    var coke0: int = gp.stock("coke")
    for i in 20:
        gp.advance_day()
    var per_batch: int = int(defo["outputs"]["coke"])
    var full_coke: float = float(defo.get("batches_per_day", 1)) * float(per_batch) * 20.0
    var got: int = gp.stock("coke") - coke0
    check(absf(float(got) - full_coke * ratio) <= float(per_batch) * 1.01, "over 20 days it makes %d coke, about %d%% of a full crew's %d" % [got, int(round(ratio * 100.0)), int(full_coke)])

    print("Your people")
    var gh = game_at(landing)
    var shel: Dictionary = put_near(gh, "shelter", 10, 10)
    People.staff(gh)
    check(People.housing(gh) == 0 and str(shel["status"]) == "unsafe", "a shelter on open ground houses nobody")
    var nest: Dictionary = put_near(gh, "mg_nest", int(shel["x"]) + 1, int(shel["y"]))
    gh.inventory["munitions"] = 100
    People.staff(gh)
    check(People.housing(gh) == 20 and str(shel["status"]) == "housing", "with a supplied defense in reach it houses 20")
    gh.advance_day()
    check(gh.people == 0, "no food, no newcomers")
    var granh: Dictionary = put_near(gh, "granary", int(shel["x"]), int(shel["y"]) + 2)
    gh.inventory["food"] = 300
    gh.advance_day()
    check(gh.people == 3 and gh.people_news.any(func(n: Dictionary) -> bool: return n["kind"] == "first"), "the first refugees come: 3 (15%% of the 20 places), and you are told (%d)" % gh.people)
    for i in 30:
        gh.advance_day()
    check(gh.people == 20, "the shelter fills up (%d)" % gh.people)
    check(int(nest["crew_yours"]) == 3 and int(nest["crew_hired"]) == 0, "your people man the nest first")
    var ovh: Dictionary = put_near(gh, "coke_oven", int(shel["x"]) - 1, int(shel["y"]))
    check(int(ovh["crew_yours"]) == 5 and int(ovh["crew_hired"]) == 0, "then the oven: no one hired")
    check(near(People.upkeep_mult(gh, ovh), 1.0 - w), "so the oven pays only its maintenance, no wages")
    var t: Dictionary = People.totals(gh)
    check(int(t["yours"]) == 3 + 5 + 1 and int(t["idle"]) == 20 - 9, "9 of your people at work, 11 free (%s)" % str(t))
    var food0: int = gh.stock("food")
    gh.advance_day()
    var spoiled_today: int = int(floor(float(food0) * float(pp["spoil_per_day"]) + 0.999))
    check(food0 - gh.stock("food") >= 2 and food0 - gh.stock("food") <= 2 + spoiled_today, "20 people eat 2 food a day (and a little spoils)")
    check(People.food_days(gh) == int(floor(float(gh.stock("food")) / 2.0)), "food days are counted at today's ration")

    print("Hunger and homelessness")
    gh.inventory["food"] = 0
    gh.advance_day()
    check(gh.people == 15 and gh.people_news.any(func(n: Dictionary) -> bool: return n["kind"] == "hungry"), "with no food, a quarter leave and you are told (%d left)" % gh.people)
    gh.advance_day()
    check(gh.people < 15 and gh.people > 0 and not gh.people_news.any(func(n: Dictionary) -> bool: return n["kind"] == "hungry"), "more leave the next day, but you are not told twice (%d)" % gh.people)
    gh.inventory["food"] = 200
    var before: int = gh.people
    gh.advance_day()
    check(gh.people >= before, "fed again, they stop leaving and newcomers return")
    gh.demolish(int(nest["uid"]))
    gh.advance_day()
    check(gh.people == 0 and gh.people_news.any(func(n: Dictionary) -> bool: return n["kind"] == "homeless"), "without its defense the shelter empties at once")

    print("A granary lost")
    var gl = game_at(landing)
    var g_a: Dictionary = put_near(gl, "granary", 12, 10)
    put_near(gl, "granary", 15, 10)
    gl.inventory["food"] = 700
    Crisis._destroy(gl, g_a, "crawler")
    check(gl.stock("food") == 400 and gl.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "destroyed" and int(n["lost"].get("food", 0)) == 300), "the food that no longer fits is lost with it")

    print("Night and searchlights")
    var gn = game_at(landing + 200)
    check(Crisis.darkness(gn) > 0.3 and Crisis.darkness(gn) < 1.0, "it is getting dark (%.2f)" % Crisis.darkness(gn))
    var pen: float = float(gd["crisis"]["darkness"]["max_penalty"]) * Crisis.darkness(gn)
    var nn: Dictionary = put_near(gn, "mg_nest", 12, 10)
    gn.inventory["munitions"] = 100
    gn.inventory["coal"] = 10
    check(near(Crisis.aim(gn, int(nn["x"]), int(nn["y"])), 1.0 - pen), "defenses aim worse in the dark (%.2f)" % Crisis.aim(gn, int(nn["x"]), int(nn["y"])))
    put_near(gn, "field_battery", int(nn["x"]), int(nn["y"]) - 1)   # full safety, so every crew is full
    gn.data["buildings"]["field_battery"]["damage"] = 0               # it still fires, for the least damage (1), so the nest's hits can be read
    var sl: Dictionary = put_near(gn, "searchlight", int(nn["x"]) + 1, int(nn["y"]))
    check(str(sl["status"]) == "ready", "a new searchlight waits for the night")
    gn.advance_day()
    check(People.crew_ratio(gn, sl) == 1.0 and People.crew_ratio(gn, nn) == 1.0, "searchlight and nest are fully manned")
    check(str(sl["status"]) == "lit" and gn.stock("coal") == 9, "it lights up and burns 1 coal a night")
    check(near(Crisis.aim(gn, int(nn["x"]), int(nn["y"])), 1.0), "a lit defense aims as by day")
    var far: Vector2i = Vector2i(int(sl["x"]) + 10, int(sl["y"]))
    check(Crisis.aim(gn, far.x, far.y) < 1.0, "beyond its reach it is still dark")
    gn.data["crisis"]["aliens"]["spawn_base"] = 0.0
    gn.aliens = [{"id": 1, "type": "strider", "x": int(nn["x"]) + 1, "y": int(nn["y"]) + 1, "hp": 300, "max_hp": 300, "attack": 0, "speed": 0, "age": 0, "wander_x": 0, "wander_y": 0}]
    gn.advance_day()
    check(int(gn.aliens[0]["hp"]) == 300 - 30 - 1, "the lit nest does its full 30 damage (%d)" % (300 - 1 - int(gn.aliens[0]["hp"])))
    gn.inventory["coal"] = 0
    gn.advance_day()
    check(str(sl["status"]) == "no_supplies" and gn.alien_news.any(func(n: Dictionary) -> bool: return n["kind"] == "no_supplies"), "out of coal it goes dark, and says so")
    var hp_now: int = int(gn.aliens[0]["hp"]) if not gn.aliens.is_empty() else 0
    gn.advance_day()
    if not gn.aliens.is_empty():
        var dealt: int = hp_now - int(gn.aliens[0]["hp"]) - 1
        check(dealt < 30 and dealt == int(round(30.0 * People.crew_ratio(gn, nn) * (1.0 - float(gd["crisis"]["darkness"]["max_penalty"]) * Crisis.darkness(gn)))), "in the dark the nest hits for %d (crew %d%%, aim %d%%)" % [dealt, int(round(People.crew_ratio(gn, nn) * 100.0)), int(round(Crisis.aim(gn, int(nn["x"]), int(nn["y"])) * 100.0))])
    var g0n = game_at(100)
    var sl0: Dictionary = put_near(g0n, "searchlight", 12, 10)
    g0n.inventory["coal"] = 10
    g0n.advance_day()
    check(str(sl0["status"]) == "ready" and g0n.stock("coal") == 10, "before the night begins, it burns nothing")

    print("Unmanned defenses")
    var gu = game_at(landing + 365 * 3)
    var nu: Dictionary = put_near(gu, "mg_nest", 30, 18)
    gu.inventory["munitions"] = 100
    People.staff(gu)
    check(int(nu["crew_hired"]) == 0, "three years in, nobody will be hired to man a lone nest")
    gu.aliens = [{"id": 1, "type": "strider", "x": int(nu["x"]) + 1, "y": int(nu["y"]), "hp": 300, "max_hp": 300, "attack": 0, "speed": 0, "age": 0, "wander_x": 0, "wander_y": 0}]
    gu.advance_day()
    check(str(nu["status"]) == "no_crew" and int(gu.aliens[0]["hp"]) == 300 and gu.stock("munitions") == 100, "an unmanned nest does not fire and uses nothing")

    print("Saving")
    var s: Dictionary = gh.to_dict()
    check(int(s["version"]) == 11 and s.has("people"), "saves are version 11 with people")
    var gx = GameState.new(data(), 1)
    check(gx.load_dict(s), "it loads")
    check(gx.people == gh.people and gx.stock("food") == gh.stock("food") and Production.current_upkeep(gx) == Production.current_upkeep(gh), "same people, food and upkeep after loading")
    var gy = GameState.new(data(), 1)
    var old: Dictionary = s.duplicate(true)
    old["version"] = 10
    check(not gy.load_dict(old), "an older save is refused")

    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
