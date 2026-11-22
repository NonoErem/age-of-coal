extends SceneTree
## Headless regression tests. Run from the project folder:
##   godot --headless --path . -s tests/market_test.gd
## Exit code is 0 when everything passes.

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


## Same data, but with the random trend switched off so timing tests are clean.
func neutral_data() -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var bal: Dictionary = gd["balance"].duplicate(true)
    bal["trend_volatility"] = 0.0
    bal["trend_reversion"] = 0.0
    var out: Dictionary = gd.duplicate()
    out["balance"] = bal
    return out


func _init() -> void:
    print("Data")
    var errors: Array = DataLoader.validate(DataLoader.load_game_data())
    for e in errors:
        print("    ", e)
    check(errors.is_empty(), "data files are consistent")

    print("Exploit checks (Sam)")
    var gs = GameState.new(neutral_data())
    var cost: int = gs.market.execute_buy("coal", 100)
    var rev: int = gs.market.execute_sell("coal", 100)
    var pnl0: float = float(rev - cost) / float(cost)
    check(pnl0 > -0.20 and pnl0 < -0.16, "same-day round trip loses 16-20%% (got %.1f%%)" % (pnl0 * 100.0))

    gs = GameState.new(neutral_data())
    cost = gs.market.execute_buy("coal", 100)
    for _d in 5:
        gs.market.advance_day(gs.rng)
    rev = gs.market.execute_sell("coal", 100)
    var pnl5: float = float(rev - cost) / float(cost)
    check(pnl5 < -0.15, "waiting 5 days is still a clear loss (%.1f%%)" % (pnl5 * 100.0))

    gs = GameState.new(neutral_data())
    var total: int = 0
    for _d in 300:
        total += gs.market.execute_sell("coal", 40)
        gs.market.advance_day(gs.rng)
    var ratio: float = float(total) / (300.0 * 40.0 * gs.market.base_price("coal"))
    check(ratio > 0.68 and ratio < 0.82, "a small company selling 40 coal/day sees a modest dent (avg %.2f of base)" % ratio)

    gs = GameState.new(neutral_data())
    gs.market.presence["coal"] = 300.0
    total = 0
    for _d in 300:
        total += gs.market.execute_sell("coal", 40)
        gs.market.advance_day(gs.rng, {"coal": 300})
    ratio = float(total) / (300.0 * 40.0 * gs.market.base_price("coal"))
    check(ratio > 0.42 and ratio < 0.55, "a major player selling the same 40/day saturates it (avg %.2f of base)" % ratio)

    print("Importance (the more you matter, the more you move the price)")
    gs = GameState.new(neutral_data())
    var start_pressure: float = float(gs.market.pressure["coal"])
    gs.market.execute_sell("coal", 50)
    var small_move: float = 1.0 - float(gs.market.pressure["coal"]) / start_pressure
    check(small_move < 0.03, "a new company selling 50 coal moves the price under 3%% (%.1f%%)" % (small_move * 100.0))

    gs = GameState.new(neutral_data())
    gs.market.presence["coal"] = 300.0
    gs.market.execute_sell("coal", 50)
    var big_move: float = 1.0 - float(gs.market.pressure["coal"])
    check(big_move > 0.08, "a major player selling 50 coal moves it over 8%% (%.1f%%)" % (big_move * 100.0))

    gs = GameState.new(neutral_data())
    var mk = gs.market
    check(is_equal_approx(mk.impact_factor_for_share(0.0), 0.05) and is_equal_approx(mk.impact_factor_for_share(0.25), 1.0) and is_equal_approx(mk.impact_factor_for_share(0.6), 1.0), "impact runs from 5%% strength to full at a 25%% share, then stops growing")
    check(mk.impact_factor_for_share(0.05) < mk.impact_factor_for_share(0.10), "more share means more impact")

    gs = GameState.new(neutral_data())
    gs.market.execute_sell("coal", 3000)
    check(float(gs.market.pressure["coal"]) < 0.5, "one huge order still crashes the price: it counts toward its own importance")

    gs = GameState.new(neutral_data())
    for _d in 40:
        gs.market.advance_day(gs.rng, {"coal": 300})
    check(gs.market.share("coal") > 0.2, "producing a lot makes you important even if you never trade (share %.2f)" % gs.market.share("coal"))

    gs = GameState.new(neutral_data())
    var q_sell: int = gs.market.quote_sell("coal", 80)
    var predicted_p: float = gs.market.pressure_after("coal", 80, false)
    var real_sell: int = gs.market.execute_sell("coal", 80)
    check(q_sell == real_sell and is_equal_approx(predicted_p, float(gs.market.pressure["coal"])), "the preview matches what really happens")

    print("Market behaviour")
    gs = GameState.new(neutral_data())
    gs.market.apply_shock("coal", 1.4, 3)
    check(gs.market.spot_price("coal") > 1.39 * gs.market.base_price("coal"), "shock raises the price")
    for _d in 3:
        gs.market.advance_day(gs.rng)
    check(is_equal_approx(float(gs.market.shock_mult["coal"]), 1.0), "shock expires after its duration")

    var gd: Dictionary = DataLoader.load_game_data()
    gs = GameState.new(gd, 7)
    var lo: float = 99.0
    var hi: float = 0.0
    for _d in 2000:
        gs.advance_day()
        for id in gd["resources"]:
            lo = minf(lo, float(gs.market.trend[id]))
            hi = maxf(hi, float(gs.market.trend[id]))
    check(lo >= 0.7 - 0.0001 and hi <= 1.4 + 0.0001, "trend stays in 0.7-1.4 over 2000 days (%.2f-%.2f)" % [lo, hi])

    print("Determinism and saving")
    var a = GameState.new(gd, 42)
    var b = GameState.new(gd, 42)
    var c = GameState.new(gd, 43)
    for _d in 100:
        a.advance_day()
        b.advance_day()
        c.advance_day()
    check(is_equal_approx(a.market.spot_price("steel"), b.market.spot_price("steel")), "same seed gives the same prices")
    check(not is_equal_approx(a.market.spot_price("steel"), c.market.spot_price("steel")), "different seed gives different prices")

    var s = GameState.new(gd, 99)
    for _d in 10:
        s.advance_day()
    s.buy("coal", 25)
    s.sell("iron_ore", 5)
    var parsed: Variant = JSON.parse_string(JSON.stringify(s.to_dict()))
    var s2 = GameState.new(gd, 1)
    check(s2.load_dict(parsed), "save loads back")
    check(s2.money_cents == s.money_cents and s2.stock("coal") == s.stock("coal") and s2.day == s.day, "money, stock and day survive save/load")
    for _d in 5:
        s.advance_day()
        s2.advance_day()
    check(absf(s.market.spot_price("coal") - s2.market.spot_price("coal")) < 0.001, "a loaded game continues identically")
    check(absf(float(s.market.presence["coal"]) - float(s2.market.presence["coal"])) < 0.0001, "market presence survives save/load")

    print("Commands")
    var t = GameState.new(gd, 5)
    check(not t.buy("steel", 100000)["ok"], "cannot buy beyond your funds")
    check(not t.sell("coal", 51)["ok"], "cannot sell more than you hold")
    check(t.sell("coal", 50)["ok"] and t.stock("coal") == 0, "selling stock works")
    check(not t.buy("unobtainium", 1)["ok"], "unknown resource is refused")
    check(not t.buy("coal", 0)["ok"], "zero quantity is refused")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
