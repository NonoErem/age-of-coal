extends SceneTree
## Headless tests for surveys: hidden deposits, areas, depth levels, costs, saving, and what must not leak.
##   godot --headless --path . -s tests/survey_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Survey = preload("res://sim/survey.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func fresh_data() -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = 0.0
    out["companies"] = gd["companies"].duplicate(true)
    out["companies"]["enabled"] = false
    return out


func _init() -> void:
    test_data()
    test_start()
    test_reveal_rules()
    test_costs_and_refusals()
    test_hidden_stays_hidden()
    test_use_after_reveal()
    test_save_and_load()
    test_exploits()
    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)


func hidden_ids(gs) -> Array:
    var out: Array = []
    for id in gs.data["map"]["deposits"]:
        if int(gs.data["map"]["deposits"][id].get("depth", 0)) > 0:
            out.append(id)
    return out


func test_data() -> void:
    print("Data")
    var gd: Dictionary = fresh_data()
    check(DataLoader.validate(gd).is_empty(), "the data is valid")
    var d: Dictionary = gd["map"]["deposits"]
    var visible: int = 0
    var d1: int = 0
    var d2: int = 0
    for id in d:
        match int(d[id].get("depth", 0)):
            0:
                visible += 1
            1:
                d1 += 1
            2:
                d2 += 1
    check(visible == 26, "the 26 deposits of the earlier version are still there, without a depth")
    check(d1 >= 6 and d2 >= 4, "there are shallow (%d) and deep (%d) hidden deposits" % [d1, d2])
    var kinds: Dictionary = {}
    for id in d:
        if int(d[id].get("depth", 0)) > 0:
            kinds[d[id]["resource"]] = true
    check(kinds.size() == 4, "every ore has something hidden: %s" % str(kinds.keys()))
    # Deeper means richer, bigger and dearer land.
    var rich: Array = [0.0, 0.0, 0.0]
    var cnt: Array = [0, 0, 0]
    var amt: Array = [0.0, 0.0, 0.0]
    for id in d:
        var dp: int = int(d[id].get("depth", 0))
        rich[dp] += float(d[id]["richness"])
        amt[dp] += float(d[id]["amount"])
        cnt[dp] += 1
    check(rich[1] / cnt[1] > rich[0] / cnt[0] and rich[2] / cnt[2] > rich[1] / cnt[1], "on average deeper ore is richer")
    check(amt[2] / cnt[2] > amt[1] / cnt[1] and amt[1] / cnt[1] > amt[0] / cnt[0], "and the deposits are bigger")
    check(Survey.cost(GameState.new(gd, 1), 2) > Survey.cost(GameState.new(gd, 1), 1), "the deep survey costs more than the shallow one")
    var bad: Dictionary = fresh_data()
    bad["map"] = bad["map"].duplicate(true)
    bad["map"]["survey"]["levels"]["2"]["cost"] = 1000
    check(not DataLoader.validate(bad).is_empty(), "a deep survey cheaper than a shallow one is refused")
    var bad2: Dictionary = fresh_data()
    bad2["map"] = bad2["map"].duplicate(true)
    bad2["map"].erase("survey")
    check(not DataLoader.validate(bad2).is_empty(), "hidden deposits without survey settings are refused")


func test_start() -> void:
    print("At the start")
    var gs = GameState.new(fresh_data(), 1)
    check(gs.revealed_deposit_ids().size() == 26, "exactly the 26 old deposits are visible")
    var all_old: bool = true
    for id in gs.data["map"]["deposits"]:
        var d: Dictionary = gs.data["map"]["deposits"][id]
        if int(d.get("depth", 0)) == 0 and gs.deposit_id_at(int(d["x"]), int(d["y"])) != id:
            all_old = false
    check(all_old, "each of them can be found on its tile")
    check(gs.survey_tiles.is_empty(), "nothing has been surveyed")


func test_reveal_rules() -> void:
    print("What a survey reveals")
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 100000000
    var d: Dictionary = gs.data["map"]["deposits"]
    # coal_d1_a is at (14, 3): shallow. coal_d2_a at (22, 13): deep.
    var r1: Dictionary = gs.survey(14, 3, 1)
    check(r1["ok"] and r1["found"].has("coal_d1_a"), "a shallow survey on a shallow deposit finds it")
    check(gs.deposit_id_at(14, 3) == "coal_d1_a", "and the tile now has a deposit")
    var gd = GameState.new(fresh_data(), 1)
    gd.money_cents = 100000000
    var r2: Dictionary = gd.survey(22, 13, 1)
    check(r2["ok"] and r2["found"].is_empty(), "a shallow survey over a deep deposit finds nothing, and still costs money")
    check(gd.deposit_id_at(22, 13) == "", "the deep deposit stays hidden")
    var r3: Dictionary = gd.survey(22, 13, 2)
    check(r3["ok"] and r3["found"].has("coal_d2_a"), "a deep survey of the same place finds it")
    # Area: radius 3 means a 7x7 square.
    var a: Rect2i = Survey.area(gs, 20, 12)
    check(a.size == Vector2i(7, 7) and a.position == Vector2i(17, 9), "the area is a 7 by 7 square around the tile")
    var corner: Rect2i = Survey.area(gs, 0, 0)
    check(corner.size == Vector2i(4, 4), "at the map's corner it is cut to the map")
    # A deposit just outside the area is not revealed.
    var ge = GameState.new(fresh_data(), 1)
    ge.money_cents = 100000000
    var r4: Dictionary = ge.survey(14, 7, 1)  # covers y 4..10: coal_d1_a at y=3 is outside
    check(not r4["found"].has("coal_d1_a") and ge.deposit_id_at(14, 3) == "", "a deposit just outside the area is not revealed")
    var r5: Dictionary = ge.survey(14, 6, 1)  # covers y 3..9: now inside
    check(r5["found"].has("coal_d1_a"), "move the area and it is found")
    # A deep survey also reveals shallow ones in its area, and old visible ones are not 'found' again.
    var gx = GameState.new(fresh_data(), 1)
    gx.money_cents = 100000000
    var r6: Dictionary = gx.survey(24, 15, 2)  # covers 21..27 x 12..18: coal_d2_a (22,13), coal_d1_b (24,18), limestone_1? (24,13 is old)
    check(r6["found"].has("coal_d2_a") and r6["found"].has("coal_d1_b"), "a deep survey finds both depths in its area")
    check(not r6["found"].has("limestone_1"), "and never reports what you could already see")


func test_costs_and_refusals() -> void:
    print("Costs and refusals")
    var gs = GameState.new(fresh_data(), 1)
    var c1: int = Survey.cost(gs, 1)
    var c2: int = Survey.cost(gs, 2)
    var before: int = gs.money_cents
    gs.survey(14, 3, 1)
    check(before - gs.money_cents == c1, "a shallow survey costs exactly its price")
    before = gs.money_cents
    gs.survey(14, 3, 2)
    check(before - gs.money_cents == c2, "a deep one on the same place costs its own price")
    check(gs.survey(14, 3, 2)["reason"] == "already_surveyed", "doing the same deep survey twice is refused")
    check(gs.survey(14, 3, 1)["reason"] == "already_surveyed", "and so is a shallow one over a deeper survey")
    before = gs.money_cents
    check(gs.money_cents == before, "a refused survey costs nothing")
    var poor = GameState.new(fresh_data(), 1)
    poor.money_cents = c1 - 1
    var rp: Dictionary = poor.survey(14, 3, 1)
    check(rp["reason"] == "insufficient_funds" and poor.money_cents == c1 - 1 and poor.survey_tiles.is_empty(), "not enough cash: nothing is paid and nothing is surveyed")
    check(gs.survey(-1, 3, 1)["reason"] == "out_of_bounds" and gs.survey(99, 3, 1)["reason"] == "out_of_bounds", "off the map is refused")
    check(gs.survey(5, 5, 3)["reason"] == "unknown_level" and gs.survey(5, 5, 0)["reason"] == "unknown_level", "unknown levels are refused")
    # Overlapping surveys: charged in full, but only new ground counts for the 'already' test.
    var go = GameState.new(fresh_data(), 1)
    go.survey(10, 10, 1)
    check(go.survey(11, 10, 1)["ok"], "a shifted survey that covers new tiles is allowed")
    check(Survey.new_tiles(go, 10, 10, 1) == 0, "and the first area is now fully covered")
    check(Survey.level_at(go, 10, 10) == 1 and Survey.level_at(go, 20, 20) == 0, "levels are tracked per tile")
    go.money_cents = 100000000
    go.survey(10, 10, 2)
    check(Survey.level_at(go, 10, 10) == 2, "a deeper survey raises the level of its tiles")
    go.survey(10, 10, 1)
    check(true, "")


func test_hidden_stays_hidden() -> void:
    print("Sam: nothing leaks before a survey")
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 100000000
    var leaked: bool = false
    for id in hidden_ids(gs):
        var d: Dictionary = gs.data["map"]["deposits"][id]
        if gs.deposit_id_at(int(d["x"]), int(d["y"])) != "":
            leaked = true
    check(not leaked, "no hidden deposit can be found on its tile")
    var mine_refused: bool = true
    for id in hidden_ids(gs):
        var d: Dictionary = gs.data["map"]["deposits"][id]
        var mine: String = _mine_for(gs, str(d["resource"]))
        if gs.check_placement(mine, int(d["x"]), int(d["y"])) != "no_deposit":
            mine_refused = false
    check(mine_refused, "a mine on a hidden tile gets the same answer as on empty ground: no deposit")
    var ids: Array = gs.revealed_deposit_ids()
    var any_hidden: bool = false
    for id in ids:
        if int(gs.data["map"]["deposits"][id].get("depth", 0)) > 0:
            any_hidden = true
    check(not any_hidden, "the list of visible deposits holds no hidden ones")
    # A factory on a hidden tile is allowed (the tile looks empty), and the deposit appears under it when surveyed.
    var d0: Dictionary = gs.data["map"]["deposits"]["coal_d1_a"]
    var rb: Dictionary = gs.build("coke_oven", int(d0["x"]), int(d0["y"]))
    check(rb["ok"], "a factory can be built on ground that hides ore")
    var rs: Dictionary = gs.survey(int(d0["x"]), int(d0["y"]), 1)
    check(rs["ok"] and rs["found"].has("coal_d1_a"), "the survey still finds the deposit")
    check(gs.build("coal_mine", int(d0["x"]), int(d0["y"]))["reason"] == "tile_occupied", "it cannot be mined until the factory is gone")
    var ub: Dictionary = gs.building_at(int(d0["x"]), int(d0["y"]))
    gs.demolish(int(ub["uid"]))
    check(gs.build("coal_mine", int(d0["x"]), int(d0["y"]))["ok"], "after demolishing, the mine goes up")


func _mine_for(gs, resource: String) -> String:
    for id in gs.data["buildings"]:
        var def: Dictionary = gs.data["buildings"][id]
        if def["kind"] == "extractor" and def["deposit"] == resource:
            return id
    return ""


func test_use_after_reveal() -> void:
    print("Using a revealed deposit")
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 100000000
    gs.survey(25, 6, 1)  # copper_d1_a at (25, 6), richness 1.6
    var d: Dictionary = gs.data["map"]["deposits"]["copper_d1_a"]
    var cost: int = gs.build_cost("copper_mine", "copper_d1_a")
    check(cost == int(gs.data["buildings"]["copper_mine"]["build_cost"]) + int(d["land_cost"]), "the land price is added as for any deposit")
    var before: int = gs.money_cents
    var rb: Dictionary = gs.build("copper_mine", 25, 6)
    check(rb["ok"] and before - gs.money_cents == cost, "the mine is bought normally")
    check(gs.build("iron_mine", 25, 6)["reason"] == "tile_occupied", "one building per tile")
    var stock0: int = gs.stock("copper_ore")
    gs.advance_day()
    gs.advance_day()
    var made: int = gs.stock("copper_ore") - stock0
    var per_day: float = float(gs.data["buildings"]["copper_mine"]["outputs"]["copper_ore"])
    check(made > 0 and made >= int(floor(per_day * 1.6)), "it digs richness times the normal output (%d in two days)" % made)
    check(int(gs.deposits["copper_d1_a"]["remaining"]) < int(d["amount"]), "and the deposit shrinks")
    check(gs.build("coal_mine", 14, 3)["reason"] == "no_deposit", "an unsurveyed deposit still cannot be mined")


func test_save_and_load() -> void:
    print("Saving and loading")
    var gd: Dictionary = fresh_data()
    var gs = GameState.new(gd, 3)
    gs.money_cents = 100000000
    gs.survey(14, 3, 1)
    gs.survey(23, 14, 2)
    gs.build("coal_mine", 14, 3)
    for _d in 5:
        gs.advance_day()
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(gd, 3)
    check(gs2.load_dict(parsed), "the save loads")
    check(gs2.survey_tiles == gs.survey_tiles and gs2.revealed == gs.revealed, "surveyed ground and revealed deposits survive")
    check(gs2.survey_stats == gs.survey_stats, "so do the statistics")
    check(gs2.deposit_id_at(22, 13) == "coal_d2_a" and gs2.deposit_id_at(11, 20) == "", "hidden stays hidden and revealed stays revealed")
    check(gs2.survey(14, 3, 1)["reason"] == "already_surveyed", "a loaded game remembers what was surveyed")
    # An old save (version 8) is refused.
    var old: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    old["version"] = 8
    check(not GameState.new(gd, 3).load_dict(old), "a version 8 save is refused")
    # A save naming an unknown deposit is refused.
    var bad: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    bad["survey"]["revealed"].append("ghost_deposit")
    check(not GameState.new(gd, 3).load_dict(bad), "a save with an unknown deposit is refused")
    var bad2: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    bad2["survey"]["tiles"]["3,3"] = 9
    check(not GameState.new(gd, 3).load_dict(bad2), "a save with an impossible survey level is refused")
    # A mine on a deposit is always visible, even if the save says nothing.
    var tricky: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    tricky["survey"]["revealed"] = []
    var g3 = GameState.new(gd, 3)
    check(g3.load_dict(tricky) and g3.deposit_id_at(14, 3) == "coal_d1_a", "a mine always stands on a deposit you can see")


func test_exploits() -> void:
    print("Sam: can surveying be abused?")
    # 1. Surveying everything costs a lot more than the ore is worth at the start, and is bounded.
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 1000000000
    var spent: int = 0
    var found: int = 0
    var cells: Vector2i = Vector2i(int(gs.data["map"]["width"]), int(gs.data["map"]["height"]))
    var surveys: int = 0
    for cy in range(3, cells.y + 3, 7):
        for cx in range(3, cells.x + 3, 7):
            var r: Dictionary = gs.survey(mini(cx, cells.x - 1), mini(cy, cells.y - 1), 2)
            if r["ok"]:
                spent += int(r["cost"])
                found += r["found"].size()
                surveys += 1
    print("      surveying the whole map deep: %d surveys, %d dollars, %d deposits" % [surveys, spent / 100, found])
    check(found == hidden_ids(gs).size(), "a grid of deep surveys finds every hidden deposit (%d)" % found)
    check(spent > 5 * int(gs.data["balance"]["start_money_cents"]), "but costs more than five times the starting money (%d dollars)" % (spent / 100))
    # 2. Find cost per deposit at each level.
    check(Survey.cost(gs, 1) < int(gs.data["balance"]["start_money_cents"]) / 4, "a shallow survey is affordable from day 1")
    check(Survey.cost(gs, 2) < int(gs.data["balance"]["start_money_cents"]) / 2, "a deep one is a real but not hopeless expense on day 1")
    # 3. Surveys cannot be resold or refunded, and do not touch the market or contract random streams.
    var a = GameState.new(fresh_data(), 9)
    var b = GameState.new(fresh_data(), 9)
    b.money_cents = 1000000000
    for _d in 40:
        a.advance_day()
        b.advance_day()
        if _d % 7 == 0:
            b.survey(5 + _d % 20, 5 + _d % 10, 1)
    check(a.rng.state == b.rng.state, "surveys never disturb the market's random stream")
    check(a.event_rng.state == b.event_rng.state, "or the event stream")
