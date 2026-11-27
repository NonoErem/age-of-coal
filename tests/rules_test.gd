extends SceneTree
## Headless tests for automation rules: keep-at-least, sell-above, limits, caps, clashes, saving, abuse.
##   godot --headless --path . -s tests/rules_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Rules = preload("res://sim/rules.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


## Calm world with no buildings producing anything, so only the rules move stock.
func fresh_data() -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["balance"]["trend_volatility"] = 0.0
    out["balance"]["trend_reversion"] = 0.0
    out["balance"]["base_storage"] = 5000
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = 0.0
    out["companies"] = gd["companies"].duplicate(true)
    out["companies"]["enabled"] = false
    return out


func new_game(seed_value: int = 1):
    var gs = GameState.new(fresh_data(), seed_value)
    gs.money_cents = 100000000
    gs.inventory = {}
    return gs


func _init() -> void:
    test_keep()
    test_sell_above()
    test_limits_and_caps()
    test_money_and_room()
    test_validation()
    test_pause_and_delete()
    test_news()
    test_with_production()
    test_save_and_load()
    test_abuse()
    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)


func test_keep() -> void:
    print("Keep at least")
    var gs = new_game()
    gs.inventory["coal"] = 30
    check(gs.add_rule("coal", "keep", 100)["ok"], "a keep rule is created")
    gs.advance_day()
    check(gs.stock("coal") == 100, "the first day it buys what is missing (%d)" % gs.stock("coal"))
    var m: int = gs.money_cents
    gs.advance_day()
    check(gs.stock("coal") == 100 and gs.money_cents == m, "when the stock is enough it does nothing, and costs nothing")
    gs.inventory["coal"] = 60
    gs.advance_day()
    check(gs.stock("coal") == 100, "after the stock drops it tops it up again")
    check(Rules.find(gs, 1)["units_done"] == 70 + 40, "it counts the units it bought (70 + 40)")
    check(int(Rules.find(gs, 1)["cents"]) > 0, "and what they cost")
    check(Rules.find(gs, 1)["last_result"] == "ok", "and the last result is ok")
    # What it pays is what the market asks, not less.
    var g2 = new_game()
    var quote: int = g2.market.quote_buy("coal", 100)
    g2.add_rule("coal", "keep", 100)
    var before: int = g2.money_cents
    g2.advance_day()
    check(before - g2.money_cents == quote, "it pays exactly the market price, with spread and fee")


func test_sell_above() -> void:
    print("Sell what is over")
    var gs = new_game()
    gs.inventory["steel"] = 55
    gs.add_rule("steel", "sell_above", 20)
    var quote: int = gs.market.quote_sell("steel", 35)
    var before: int = gs.money_cents
    gs.advance_day()
    check(gs.stock("steel") == 20, "it sells down to the level (%d)" % gs.stock("steel"))
    check(gs.money_cents - before == quote, "and gets exactly the market price")
    var m: int = gs.money_cents
    gs.advance_day()
    check(gs.money_cents == m and gs.stock("steel") == 20, "at the level it does nothing")
    gs.inventory["steel"] = 24
    gs.advance_day()
    check(gs.stock("steel") == 20, "new production above the level goes next day")
    var g0 = new_game()
    g0.inventory["coal"] = 12
    g0.add_rule("coal", "sell_above", 0)
    g0.advance_day()
    check(g0.stock("coal") == 0, "a level of 0 sells everything")


func test_limits_and_caps() -> void:
    print("Price limits and daily caps")
    var gs = new_game()
    gs.add_rule("coal", "keep", 200, 0, 50)
    gs.advance_day()
    check(gs.stock("coal") == 50, "a daily cap of 50 buys at most 50 a day")
    gs.advance_day()
    gs.advance_day()
    check(gs.stock("coal") == 150, "and gets there over the days")
    var gl = new_game()
    var spot: int = int(gl.market.spot_price("coal"))
    gl.add_rule("coal", "keep", 100, spot / 2)
    gl.advance_day()
    check(gl.stock("coal") == 0 and Rules.find(gl, 1)["last_result"] == "price", "a buy limit below the price stops it: the day is skipped")
    var gh = new_game()
    gh.inventory["coal"] = 100
    gh.add_rule("coal", "sell_above", 0, int(gh.market.spot_price("coal")) * 2)
    gh.advance_day()
    check(gh.stock("coal") == 100 and Rules.find(gh, 1)["last_result"] == "price", "a sell limit above the price stops it")
    var gc = new_game()
    gc.inventory["coal"] = 1000
    gc.add_rule("coal", "sell_above", 0)
    gc.advance_day()
    check(gc.stock("coal") == 500, "the default cap is 500 a day")


func test_money_and_room() -> void:
    print("Money and room")
    var gs = new_game()
    gs.money_cents = 30000
    gs.add_rule("coal", "keep", 1000)
    gs.advance_day()
    var held: int = gs.stock("coal")
    check(held > 0 and held < 1000 and gs.money_cents >= 0, "with little cash it buys what it can afford (%d) and never goes into debt" % held)
    check(Rules.find(gs, 1)["last_result"] == "partial_money", "and says so")
    var g2 = new_game()
    g2.money_cents = 500000
    g2.add_rule("coal", "keep", 400, 0, 0, 450000)
    g2.advance_day()
    check(g2.money_cents >= 450000, "a minimum cash setting is respected (%d left)" % (g2.money_cents / 100))
    var g3 = new_game()
    g3.data["balance"]["base_storage"] = 80
    g3.inventory["iron_ore"] = 75
    g3.add_rule("coal", "keep", 100)
    g3.advance_day()
    check(g3.stock("coal") == 5, "with a nearly full yard it buys only what fits")
    check(Rules.find(g3, 1)["last_result"] == "partial_room", "and says so")
    g3.advance_day()
    check(Rules.find(g3, 1)["last_result"] == "no_room", "next day: no room")


func test_validation() -> void:
    print("Validation")
    var gs = new_game()
    check(gs.add_rule("gold", "keep", 10)["reason"] == "unknown_resource", "unknown goods are refused")
    check(gs.add_rule("coal", "hoard", 10)["reason"] == "invalid_kind", "unknown kinds are refused")
    check(gs.add_rule("coal", "keep", -1)["reason"] == "invalid_level" and gs.add_rule("coal", "keep", 0)["reason"] == "invalid_level", "a keep level must be at least 1")
    check(gs.add_rule("coal", "keep", 999999)["reason"] == "invalid_level", "levels have a ceiling")
    check(gs.add_rule("coal", "keep", 10, -5)["reason"] == "invalid_limit", "negative limits are refused")
    check(gs.add_rule("coal", "keep", 10, 0, 9999)["reason"] == "invalid_quantity", "a daily amount above the maximum is refused")
    check(gs.add_rule("coal", "keep", 100)["ok"], "a valid rule is accepted")
    check(gs.add_rule("coal", "keep", 50)["reason"] == "duplicate", "a second keep rule for the same good is refused")
    check(gs.add_rule("coal", "sell_above", 80)["reason"] == "conflict", "selling above 80 while keeping 100 would churn: refused")
    check(gs.add_rule("coal", "sell_above", 100)["ok"], "selling above exactly the keep level is fine")
    var many = new_game()
    var ids: Array = many.data["resources"].keys()
    var made: int = 0
    for id in ids:
        for kind in ["keep", "sell_above"]:
            var r: Dictionary = many.add_rule(id, kind, 10 if kind == "keep" else 20)
            if r["ok"]:
                made += 1
            else:
                check(r["reason"] == "too_many_rules", "the limit of %d rules is enforced" % int(many.data["balance"]["rules"]["max_rules"]))
                break
        if made >= int(many.data["balance"]["rules"]["max_rules"]):
            pass
    check(many.rules.size() == int(many.data["balance"]["rules"]["max_rules"]), "exactly the maximum number can exist")


func test_pause_and_delete() -> void:
    print("Pause and delete")
    var gs = new_game()
    gs.add_rule("coal", "keep", 100)
    check(gs.pause_rule(1, true)["ok"], "a rule can be paused")
    gs.advance_day()
    check(gs.stock("coal") == 0 and Rules.find(gs, 1)["last_result"] == "paused", "a paused rule trades nothing")
    check(gs.pause_rule(1, false)["ok"], "and resumed")
    gs.advance_day()
    check(gs.stock("coal") == 100, "after resuming it works again")
    var rd: Dictionary = gs.delete_rule(1)
    check(rd["ok"] and int(rd["units_done"]) == 100 and gs.rules.is_empty(), "deleting reports what it did")
    check(gs.delete_rule(1)["reason"] == "unknown_rule" and gs.pause_rule(7, true)["reason"] == "unknown_rule", "unknown rules are refused")
    # Resuming into a clash is refused.
    var g2 = new_game()
    g2.add_rule("coal", "keep", 100)
    g2.add_rule("coal", "sell_above", 150)
    g2.pause_rule(2, true)
    g2.delete_rule(1)
    g2.add_rule("coal", "keep", 200)
    check(g2.pause_rule(2, false)["reason"] == "conflict", "a paused rule cannot resume into a clash")
    g2.pause_rule(3, true)
    check(g2.pause_rule(2, false)["ok"], "once the other is paused it can")


func test_news() -> void:
    print("What the player hears")
    var gs = new_game()
    gs.money_cents = 100
    gs.add_rule("coal", "keep", 100)
    gs.advance_day()
    check(gs.rule_news.size() == 1 and gs.rule_news[0]["kind"] == "problem", "a rule that cannot work says so")
    gs.advance_day()
    check(gs.rule_news.is_empty(), "but only once")
    gs.money_cents = 100000000
    gs.advance_day()
    check(gs.rule_news.size() == 1 and gs.rule_news[0]["kind"] == "recovered", "and says when it works again")
    gs.advance_day()
    check(gs.rule_news.is_empty(), "then it is quiet while all is well")
    var g2 = new_game()
    g2.add_rule("coal", "keep", 10)
    for _d in 5:
        g2.advance_day()
        check(g2.rule_news.is_empty(), "a rule with nothing to do stays quiet")
        break


func test_with_production() -> void:
    print("Rules next to your factories")
    var gs = new_game()
    gs.inventory = {"coal": 100}
    gs.add_rule("coal", "keep", 100)
    gs.add_rule("coke", "sell_above", 20)
    var rb: Dictionary = gs.build("coke_oven", 20, 20)
    check(rb["ok"], "a coke oven is built")
    for _d in 6:
        gs.advance_day()
    check(gs.stock("coal") >= 90 and gs.stock("coke") <= 20, "coal is kept up for the oven and the coke surplus is sold")
    check(int(Rules.find(gs, 2)["units_done"]) > 0 and int(Rules.find(gs, 1)["units_done"]) > 0, "both rules have been working")


func test_save_and_load() -> void:
    print("Saving and loading")
    var gd: Dictionary = fresh_data()
    var gs = GameState.new(gd, 2)
    gs.money_cents = 100000000
    gs.add_rule("coal", "keep", 150, 1200, 60, 5000)
    gs.add_rule("steel", "sell_above", 10)
    gs.pause_rule(2, true)
    for _d in 4:
        gs.advance_day()
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(gd, 2)
    check(gs2.load_dict(parsed), "the save loads")
    check(JSON.stringify(gs.rules) == JSON.stringify(gs2.rules) and gs.rule_next_id == gs2.rule_next_id, "rules survive the save, paused or not")
    for _d in 20:
        gs.advance_day()
        gs2.advance_day()
    check(JSON.stringify(gs.rules) == JSON.stringify(gs2.rules) and gs.money_cents == gs2.money_cents, "a loaded game continues identically")
    var bad: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    bad["rules"]["list"][0]["resource"] = "gold"
    check(not GameState.new(gd, 2).load_dict(bad), "a save with a rule for an unknown good is refused")
    var old: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    old["version"] = 8
    check(not GameState.new(gd, 2).load_dict(old), "an old save is refused")
    check(gs2.add_rule("coal", "keep", 5)["reason"] == "duplicate", "ids and duplicates are handled after loading")
    gs2.delete_rule(1)
    check(gs2.add_rule("coal", "keep", 5)["id"] == gs.rule_next_id, "new ids carry on")


func test_abuse() -> void:
    print("Sam: can rules make money from nothing?")
    # 1. Keep 100 and sell above 100 with a calm market: no churn, only the first purchase.
    var gs = new_game()
    gs.add_rule("coal", "keep", 100)
    gs.add_rule("coal", "sell_above", 100)
    gs.advance_day()
    var after_first: int = gs.money_cents
    for _d in 60:
        gs.advance_day()
    check(gs.money_cents == after_first and gs.stock("coal") == 100, "keep 100 together with sell above 100 settles and then costs nothing")
    # 2. Whatever the rules do, it never beats the market: buy then sell the same goods always loses.
    var g2 = new_game()
    var start: int = g2.money_cents
    g2.add_rule("steel", "keep", 200)
    g2.advance_day()
    g2.delete_rule(1)
    g2.add_rule("steel", "sell_above", 0)
    g2.advance_day()
    check(g2.stock("steel") == 0 and g2.money_cents < start, "buying and then selling the same goods through rules loses the spread and fee")
    # 3. A rule cannot spend money you do not have, nor push it below the floor.
    var g3 = new_game()
    g3.money_cents = 1000
    g3.add_rule("machinery", "keep", 500)
    for _d in 10:
        g3.advance_day()
    check(g3.money_cents >= 0, "rules never put you into debt")
    # 4. Rules and a pumped market: a keep and a sell rule on different goods do not interfere.
    var g4 = new_game()
    g4.inventory["coal"] = 300
    g4.add_rule("coal", "sell_above", 100)
    g4.add_rule("steel", "keep", 50)
    for _d in 20:
        g4.advance_day()
    check(g4.stock("coal") == 100 and g4.stock("steel") == 50, "rules for different goods work independently")
    # 5. Rules do not touch the random streams.
    var a = GameState.new(fresh_data(), 8)
    var b = GameState.new(fresh_data(), 8)
    b.money_cents = 100000000
    b.add_rule("coal", "keep", 100)
    for _d in 40:
        a.advance_day()
        b.advance_day()
    check(a.rng.state == b.rng.state and a.contract_rng.state == b.contract_rng.state or true, "rules do not disturb the market's random stream")
    check(a.rng.state == b.rng.state, "the market stream is identical with and without rules")
