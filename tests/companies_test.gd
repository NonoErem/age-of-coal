extends SceneTree
## Headless tests for rival companies: market effects, weakening, bankruptcy, buying, contracts, saving, exploits.
##   godot --headless --path . -s tests/companies_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Companies = preload("res://sim/companies.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


## Calm world: no random price wandering, no market events, so only the rivals move things.
func fresh_data(rivals: bool = true) -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["balance"]["trend_volatility"] = 0.0
    out["balance"]["trend_reversion"] = 0.0
    out["balance"]["base_storage"] = 1000000
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = 0.0
    out["companies"] = gd["companies"].duplicate(true)
    out["companies"]["enabled"] = rivals
    return out


func _init() -> void:
    test_data()
    test_depth_and_prices()
    test_weakness_moves_prices()
    test_bankruptcy_and_revival()
    test_dumping_ruins_a_seller()
    test_expensive_inputs_idle_a_buyer()
    test_buying_and_selling()
    test_dividends_and_wipeout()
    test_flip_exploits()
    test_contract_taking()
    test_save_and_load()
    test_growth()
    test_determinism()
    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)


func test_data() -> void:
    print("Data")
    var gd: Dictionary = fresh_data()
    check(DataLoader.validate(gd).is_empty(), "the data is valid")
    check(gd["companies"]["list"].size() == 8, "there are eight rivals")
    var bad: Dictionary = fresh_data()
    bad["companies"]["list"]["tyne"] = bad["companies"]["list"]["tyne"].duplicate(true)
    bad["companies"]["list"]["tyne"]["inputs"]["gold"] = 5
    check(not DataLoader.validate(bad).is_empty(), "an unknown resource in a company is caught")
    var bad2: Dictionary = fresh_data()
    bad2["companies"]["sell_back"] = 1.2
    check(not DataLoader.validate(bad2).is_empty(), "selling back at more than the price is refused")
    # Every raw and made good has at least one specialist, so rivals can take any offer.
    var made: Dictionary = {}
    for id in gd["companies"]["list"]:
        for res in gd["companies"]["list"][id]["outputs"]:
            made[res] = true
    check(made.size() == gd["resources"].size(), "every good has a specialist producer")


func test_depth_and_prices() -> void:
    print("Depth and starting prices")
    var gs = GameState.new(fresh_data(), 1)
    check(is_equal_approx(gs.market.depth("steel"), 250.0 * 1.35), "a healthy steel specialist makes steel 35% deeper")
    check(is_equal_approx(gs.market.depth("coal"), 400.0 * 1.30), "coal is 30% deeper")
    check(is_equal_approx(gs.market.depth("machinery"), 60.0 * 1.50), "machinery is 50% deeper")
    var healthy_ok: bool = true
    for res in gs.data["resources"]:
        if not is_equal_approx(float(gs.market.rival_mult[res]), 1.0):
            healthy_ok = false
    check(healthy_ok, "healthy rivals leave every price at normal")
    var off = GameState.new(fresh_data(false), 1)
    check(is_equal_approx(off.market.depth("steel"), 250.0) and off.rivals.is_empty(), "with rivals switched off nothing changes")
    for _d in 20:
        off.advance_day()
    check(off.rival_news.is_empty(), "and they report nothing")
    # A bigger order moves a deeper market less.
    var q_on: int = gs.market.quote_sell("steel", 100)
    var q_off: int = off.market.quote_sell("steel", 100)
    check(q_on > q_off, "dumping 100 steel fetches more in the deeper market")


func test_weakness_moves_prices() -> void:
    print("A weak rival moves the market")
    var gs = GameState.new(fresh_data(), 1)
    gs.rivals["tyne"]["strength"] = 0.5
    gs.rivals["tyne"]["status"] = "weakened"
    for _d in 25:
        Companies.update_market(gs, "smooth")
    check(float(gs.market.rival_mult["steel"]) > 1.08, "less steel supplied: steel gets dearer (%.2f)" % float(gs.market.rival_mult["steel"]))
    check(float(gs.market.rival_mult["pig_iron"]) < 0.96, "less pig iron bought: pig iron gets cheaper (%.2f)" % float(gs.market.rival_mult["pig_iron"]))
    check(float(gs.market.rival_mult["coal"]) < 1.0, "even coal feels it (%.3f)" % float(gs.market.rival_mult["coal"]))
    check(float(gs.market.rival_mult["rails"]) == 1.0, "unrelated goods do not move")
    check(gs.market.spot_price("steel") > 9000.0 * 1.08, "the spot price shows it")
    check(gs.market.reference_price("steel") > 9000.0 * 1.08, "and so does the price contracts are based on")
    check(gs.market.depth("steel") < 250.0 * 1.35 and gs.market.depth("steel") > 250.0, "the steel market is thinner than before")
    check(is_equal_approx(gs.market.depth("steel"), 250.0 * (1.0 + 0.35 * 0.5)), "depth follows strength")
    var lo: bool = float(gs.market.rival_mult["steel"]) <= float(gs.data["companies"]["mult_max"])
    check(lo, "the shift is capped")


func test_bankruptcy_and_revival() -> void:
    print("Bankruptcy and revival")
    var gs = GameState.new(fresh_data(), 1)
    gs.rivals["tyne"]["cash"] = -1000000000
    gs.advance_day()
    var r: Dictionary = gs.rivals["tyne"]
    check(r["status"] == "bankrupt" and float(r["strength"]) == 0.0, "a company too deep in debt goes bankrupt")
    var told: bool = false
    for n in gs.rival_news:
        if n["kind"] == "bankrupt" and n["company"] == "tyne" and not n["was_owned"]:
            told = true
    check(told, "the news says so")
    check(float(gs.market.depth("steel")) == 250.0, "its depth bonus is gone")
    for _d in 30:
        gs.advance_day()
    check(float(gs.market.rival_mult["steel"]) > 1.15, "steel is clearly dearer while it is down (%.2f)" % float(gs.market.rival_mult["steel"]))
    check(float(gs.market.rival_mult["pig_iron"]) < 0.9, "pig iron is clearly cheaper (%.2f)" % float(gs.market.rival_mult["pig_iron"]))
    check(int(gs.rivals["tyne"]["profit"]) == 0, "a bankrupt company earns nothing")
    var revived_on: int = -1
    var strength_then: float = -1.0
    var status_then: String = ""
    for d in 80:
        gs.advance_day()
        for n in gs.rival_news:
            if n["kind"] == "revived" and revived_on < 0:
                revived_on = gs.day
                strength_then = float(gs.rivals["tyne"]["strength"])
                status_then = str(gs.rivals["tyne"]["status"])
    check(revived_on > 0, "investors restart it after %d days" % revived_on)
    check(status_then == "weakened" and is_equal_approx(strength_then, float(gs.data["companies"]["revival_strength"])), "it comes back weakened, at the revival strength")
    for _d in 120:
        gs.advance_day()
    check(gs.rivals["tyne"]["status"] == "healthy" and float(gs.rivals["tyne"]["strength"]) > 0.99, "and recovers fully in calm markets")
    check(absf(float(gs.market.rival_mult["steel"]) - 1.0) < 0.02, "prices settle back to normal (%.3f)" % float(gs.market.rival_mult["steel"]))


func test_dumping_ruins_a_seller() -> void:
    print("Selling too cheaply ruins a producer")
    var gs = GameState.new(fresh_data(), 1)
    var gone_on: int = -1
    var weak_first: bool = false
    for d in 120:
        gs.market.pressure["steel"] = 0.3  # somebody keeps steel at a third of its price
        gs.advance_day()
        if gs.rivals["tyne"]["status"] == "weakened":
            weak_first = true
        if gone_on < 0 and gs.rivals["tyne"]["status"] == "bankrupt":
            gone_on = d
    check(gone_on > 0, "Tyne Steel goes under after %d days of cheap steel" % gone_on)
    check(gone_on >= 15, "but not overnight")
    check(weak_first, "and it was reported weakened first")


func test_expensive_inputs_idle_a_buyer() -> void:
    print("Inputs it cannot afford")
    var gs = GameState.new(fresh_data(), 1)
    check(Companies.variable_margin(gs, "tyne") > 0, "at normal prices Tyne Steel makes a margin")
    gs.market.pressure["pig_iron"] = 2.2
    check(Companies.variable_margin(gs, "tyne") == 0, "with pig iron far too dear it idles instead of buying")
    gs.market.pressure["pig_iron"] = 1.0
    gs.market.pressure["steel"] = 0.5
    check(Companies.variable_margin(gs, "tyne") == 0, "and it idles rather than sell steel at a loss")


func test_buying_and_selling() -> void:
    print("Buying and selling a rival")
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 100000000
    var price: int = Companies.value(gs, "tyne")
    check(price == int(gs.data["companies"]["list"]["tyne"]["base_value"]), "a healthy company costs its full value")
    var r1: Dictionary = gs.buy_company("tyne")
    check(r1["ok"] and gs.money_cents == 100000000 - price and gs.rivals["tyne"]["owned"], "buying takes the money and gives you the company")
    check(not gs.buy_company("tyne")["ok"] and gs.buy_company("tyne")["reason"] == "already_owned", "it cannot be bought twice")
    check(gs.buy_company("harlow")["ok"] and gs.buy_company("albion")["ok"], "you can own three")
    check(gs.buy_company("midland")["reason"] == "too_many_owned", "but not four")
    var poor = GameState.new(fresh_data(), 1)
    poor.money_cents = 1000
    check(poor.buy_company("tyne")["reason"] == "insufficient_funds" and poor.money_cents == 1000, "no money, no company")
    check(gs.buy_company("nowhere")["reason"] == "unknown_company", "unknown companies are refused")
    check(gs.sell_company("tyne")["reason"] == "hold_period", "you cannot sell straight away")
    check(gs.sell_company("midland")["reason"] == "not_owned", "or sell what you do not own")
    var min_hold: int = int(gs.data["companies"]["min_hold_days"])
    for _d in min_hold:
        gs.advance_day()
    var before: int = gs.money_cents
    var rs: Dictionary = gs.sell_company("tyne")
    check(rs["ok"] and gs.money_cents == before + int(rs["revenue"]) and not gs.rivals["tyne"]["owned"], "after the waiting period you can sell")
    check(int(rs["revenue"]) < Companies.value(gs, "tyne"), "for less than it would cost to buy it back")
    # Every state: selling is worth less than buying.
    var always_less: bool = true
    for s in [0.0, 0.2, 0.5, 0.8, 1.0]:
        gs.rivals["albion"]["strength"] = s
        if Companies.sell_price(gs, "albion") >= Companies.value(gs, "albion"):
            always_less = false
    check(always_less, "at any strength the sale price is below the purchase price")
    # A bankrupt company is cheap, and buying it restarts it.
    var gb = GameState.new(fresh_data(), 1)
    gb.money_cents = 100000000
    gb.rivals["midland"]["cash"] = -1000000000
    gb.advance_day()
    var cheap: int = Companies.value(gb, "midland")
    var base: int = int(gb.data["companies"]["list"]["midland"]["base_value"])
    check(cheap == int(round(float(base) * float(gb.rivals["midland"]["scale"]) * float(gb.data["companies"]["buy_floor"]))), "a bankrupt company costs only the floor price")
    var rb: Dictionary = gb.buy_company("midland")
    check(rb["ok"] and rb["restarted"] and gb.rivals["midland"]["status"] == "weakened" and float(gb.rivals["midland"]["strength"]) > 0.5, "buying it restarts it, weakened")
    check(gb.rivals["midland"]["owned"], "and it is yours")


func test_dividends_and_wipeout() -> void:
    print("Dividends and losing your stake")
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 100000000
    gs.buy_company("tyne")
    var before: int = gs.money_cents
    gs.advance_day()
    var profit: int = int(gs.rivals["tyne"]["profit"])
    var gain: int = gs.money_cents - before
    check(profit > 0 and gain == int(floor(float(profit) * 0.5)) - int(gs.last_report["upkeep_cents"]) * 0 and gain > 0, "an owned company pays half its profit as a dividend")
    check(int(gs.rival_stats["dividends_cents"]) == gain, "the total is tracked")
    check(int(gs.rivals["tyne"]["dividends"]) == gain, "and shown per company")
    # Owned and doomed.
    gs.rivals["tyne"]["cash"] = -1000000000
    gs.advance_day()
    check(gs.rivals["tyne"]["status"] == "bankrupt" and not gs.rivals["tyne"]["owned"], "if it goes bankrupt your stake is wiped out")
    check(int(gs.rival_stats["wiped_out"]) == 1, "and the stats remember")
    var told: bool = false
    for n in gs.rival_news:
        if n["kind"] == "bankrupt" and n["was_owned"]:
            told = true
    check(told, "the news says it was yours")
    check(gs.sell_company("tyne")["reason"] == "not_owned", "there is nothing left to sell")


func test_flip_exploits() -> void:
    print("Sam: buy cheap, flip")
    # 1. Buy a bankrupt company at the floor, nurse it, sell it as soon as allowed.
    var gs = GameState.new(fresh_data(), 1)
    gs.money_cents = 1000000000
    gs.rivals["tyne"]["cash"] = -1000000000
    gs.advance_day()
    var start_money: int = gs.money_cents
    var base: int = int(gs.data["companies"]["list"]["tyne"]["base_value"])
    var paid: int = Companies.value(gs, "tyne")
    check(gs.buy_company("tyne")["ok"], "bought the bankrupt Tyne Steel")
    var sold: Dictionary = {}
    for _d in 200:
        gs.advance_day()
        sold = gs.sell_company("tyne")
        if sold["ok"]:
            break
    var net: int = gs.money_cents - start_money
    print("      paid %d, net result after selling %d (%.0f%% of its full value)" % [paid / 100, net / 100, 100.0 * float(net) / float(base)])
    check(sold.get("ok", false), "sold after the waiting period")
    check(net > 0 and net < int(0.5 * float(base)), "the bargain flip pays something, but less than half the company's full value")
    # 2. Same-day round trip is impossible.
    var g2 = GameState.new(fresh_data(), 1)
    g2.money_cents = 1000000000
    g2.rivals["albion"]["cash"] = -1000000000
    g2.advance_day()
    var m2: int = g2.money_cents
    g2.buy_company("albion")
    check(g2.sell_company("albion")["reason"] == "hold_period" and g2.money_cents < m2, "no same-day flip of a bankrupt company")
    # 3. Healthy company, hold, sell: always a loss.
    var g3 = GameState.new(fresh_data(), 1)
    g3.money_cents = 1000000000
    var m3: int = g3.money_cents
    g3.buy_company("harlow")
    for _d in 60:
        g3.advance_day()
    g3.sell_company("harlow")
    check(g3.money_cents < m3 + int(0.5 * float(int(g3.data["companies"]["list"]["harlow"]["base_value"]))), "holding a healthy company for 60 days and selling is a poor trade")
    # 4. Ruining a rival's market by dumping costs the dumper far more than it costs the rival.
    var g4 = GameState.new(fresh_data(), 1)
    g4.money_cents = 1000000000
    g4.inventory["steel"] = 400
    var margin_before: int = Companies.variable_margin(g4, "tyne")
    var spot_value: int = int(round(g4.market.spot_price("steel") * 400.0))
    var got: int = int(g4.sell("steel", 400)["revenue"])
    check(Companies.variable_margin(g4, "tyne") < margin_before, "a big dump of steel does squeeze Tyne's margin")
    check(got < int(0.8 * float(spot_value)), "but the dumper takes the loss (got %d%% of spot value)" % int(100.0 * float(got) / float(spot_value)))


func test_contract_taking() -> void:
    print("Rivals take offers")
    var gs = GameState.new(fresh_data(), 1)
    gs.board = []
    gs.day = 20
    var low: Dictionary = {"id": 1, "client": "railway", "resource": "steel", "quantity": 20, "unit_price": 1, "deadline_days": 10, "offered_day": 5, "expires_day": 30, "premium": 1.05}
    var high: Dictionary = low.duplicate()
    high["premium"] = 1.35
    var p_low: float = Companies.take_chance(gs, "tyne", low)
    var p_high: float = Companies.take_chance(gs, "tyne", high)
    check(p_high > p_low and p_low > 0.0, "the better an offer pays, the likelier a rival takes it (%.3f vs %.3f)" % [p_low, p_high])
    check(Companies.take_chance(gs, "harlow", high) == 0.0, "a rival only takes goods it makes")
    gs.rivals["tyne"]["strength"] = 0.5
    check(Companies.take_chance(gs, "tyne", high) < p_high, "a weakened rival is slower")
    gs.rivals["tyne"]["strength"] = 1.0
    gs.rivals["tyne"]["owned"] = true
    check(Companies.take_chance(gs, "tyne", high) == 0.0, "your own company leaves your offers alone")
    gs.rivals["tyne"]["owned"] = false
    gs.rivals["tyne"]["status"] = "bankrupt"
    check(Companies.take_chance(gs, "tyne", high) == 0.0, "a bankrupt one takes nothing")
    gs.rivals["tyne"]["status"] = "healthy"
    # Over many days a rich offer does get taken, a fresh one never on its first day.
    var taken: int = 0
    var trials: int = 400
    for t in trials:
        var g = GameState.new(fresh_data(), 100 + t)
        g.day = 20
        var o: Dictionary = high.duplicate()
        o["offered_day"] = 20
        g.board = [o]
        Companies.take_offers(g)
        if g.board.is_empty():
            taken += 1
    check(taken == 0, "an offer that arrived today is safe until tomorrow")
    for t in trials:
        var g = GameState.new(fresh_data(), 100 + t)
        g.day = 20
        g.board = [high.duplicate()]
        Companies.take_offers(g)
        if g.board.is_empty():
            taken += 1
            check_news_once(g)
    var rate: float = float(taken) / float(trials)
    check(rate > 0.05 and rate < 0.25, "a +35%% steel offer is taken by Tyne on about %.0f%% of days" % (rate * 100.0))
    var off: Dictionary = fresh_data()
    off["companies"]["take_contracts"] = false
    var gn = GameState.new(off, 1)
    gn.day = 20
    gn.board = [high.duplicate()]
    for _i in 200:
        Companies.take_offers(gn)
    check(gn.board.size() == 1, "with the option off, rivals leave the board alone")
    # The market stream is not touched by rivals.
    var a = GameState.new(fresh_data(), 7)
    var data_b: Dictionary = fresh_data()
    data_b["companies"]["take_contracts"] = false
    var b = GameState.new(data_b, 7)
    var same: bool = true
    for _d in 60:
        a.advance_day()
        b.advance_day()
        if a.rng.state != b.rng.state:
            same = false
    check(same, "rivals taking offers never disturb the market's random stream")


var _news_checked: bool = false


func check_news_once(g) -> void:
    if _news_checked:
        return
    _news_checked = true
    var n: Dictionary = g.rival_news[0]
    check(n["kind"] == "took_offer" and n["company"] == "tyne" and n["resource"] == "steel", "a taken offer is reported with who took it")


func test_save_and_load() -> void:
    print("Saving and loading")
    var gd: Dictionary = fresh_data()
    var gs = GameState.new(gd, 5)
    gs.money_cents = 500000000
    gs.buy_company("harlow")
    gs.rivals["northern"]["cash"] = -1000000000
    for _d in 25:
        gs.advance_day()
    check(gs.rivals["northern"]["status"] == "bankrupt", "a bankrupt rival, an owned one and a moving market")
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(gd, 5)
    check(gs2.load_dict(parsed), "the save loads")
    check(_snapshot(gs) == _snapshot(gs2), "rivals survive the save")
    check(gs.rival_stats == gs2.rival_stats, "and so do their stats")
    check(is_equal_approx(gs.market.depth("rails"), gs2.market.depth("rails")), "depth is restored")
    check(is_equal_approx(gs.market.spot_price("rails"), gs2.market.spot_price("rails")), "and so are prices")
    for _d in 120:
        gs.advance_day()
        gs2.advance_day()
    check(_snapshot(gs) == _snapshot(gs2) and gs.money_cents == gs2.money_cents and JSON.stringify(gs.board) == JSON.stringify(gs2.board), "a loaded game continues identically")
    # A save that names a company the data does not have is refused.
    var broken: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    broken["rivals"]["list"]["ghost"] = broken["rivals"]["list"]["tyne"]
    var gs3 = GameState.new(gd, 5)
    check(not gs3.load_dict(broken), "a save with an unknown company is refused")
    # An older save is refused.
    var old: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    old["version"] = 7
    check(not GameState.new(gd, 5).load_dict(old), "a version 7 save is refused")


## The rivals' state with floats rounded, because a JSON save keeps floats to about 15 digits.
func _snapshot(gs) -> String:
    var out: Array = []
    for id in gs.rivals:
        var r: Dictionary = gs.rivals[id]
        out.append([id, r["status"], r["owned"], r["cash"], r["profit"], r["bankrupt_days"], r["paid"], r["dividends"], r["bought_day"], snappedf(float(r["strength"]), 1e-9), snappedf(float(r["scale"]), 1e-9)])
    return str(out)


func test_growth() -> void:
    print("Growth")
    var cfg: Dictionary = DataLoader.load_game_data()["companies"]
    var gs = GameState.new(fresh_data(), 1)
    var depth0: float = gs.market.depth("steel")
    var price0: int = Companies.value(gs, "tyne")
    for _d in 150:
        gs.advance_day()
    var sc: float = float(gs.rivals["tyne"]["scale"])
    check(sc > 1.2 and sc < float(cfg["growth_max_scale"]), "a healthy rival grows (x%.2f after 150 calm days)" % sc)
    check(Companies.value(gs, "tyne") > int(1.2 * float(price0)), "and so does its price (%d to %d dollars)" % [price0 / 100, Companies.value(gs, "tyne") / 100])
    check(gs.market.depth("steel") > depth0 * 1.03, "its market gets deeper as it grows (%.0f to %.0f)" % [depth0, gs.market.depth("steel")])
    check(int(gs.rivals["tyne"]["profit"]) > 0 and gs.rivals["tyne"]["status"] == "healthy", "it stays healthy and profitable while growing")
    check(absf(float(gs.market.rival_mult["steel"]) - 1.0) < 0.02, "growing does not move prices on its own")
    var big = GameState.new(fresh_data(), 1)
    for _d in 1500:
        big.advance_day()
    var capped: bool = true
    for id in big.rivals:
        if float(big.rivals[id]["scale"]) > float(cfg["growth_max_scale"]) + 1e-9 or float(big.rivals[id]["scale"]) < float(cfg["min_scale"]) - 1e-9:
            capped = false
    check(capped, "no rival ever goes beyond its limits in 1500 days")
    # Not all rivals grow equally: it follows how well they do (prices wander in the real game).
    var live = GameState.new(DataLoader.load_game_data(), 2)
    for _d in 300:
        live.advance_day()
    var lo: float = 99.0
    var hi: float = 0.0
    for id in live.rivals:
        lo = minf(lo, float(live.rivals[id]["scale"]))
        hi = maxf(hi, float(live.rivals[id]["scale"]))
    check(hi - lo > 0.2, "after 300 days they differ with how well they did (x%.2f to x%.2f)" % [lo, hi])
    # A company you own grows slower, because you take half of its profit.
    var a = GameState.new(fresh_data(), 4)
    var b = GameState.new(fresh_data(), 4)
    b.money_cents = 100000000
    b.buy_company("tyne")
    for _d in 200:
        a.advance_day()
        b.advance_day()
    check(float(b.rivals["tyne"]["scale"]) < float(a.rivals["tyne"]["scale"]), "an owned company grows more slowly (x%.2f against x%.2f)" % [float(b.rivals["tyne"]["scale"]), float(a.rivals["tyne"]["scale"])])
    check(float(b.rivals["tyne"]["scale"]) > 1.0, "but it still grows")
    # Failure: a company in debt shrinks, and a failed one restarts small.
    var f = GameState.new(fresh_data(), 1)
    for _d in 120:
        f.advance_day()
    var grown: float = float(f.rivals["tyne"]["scale"])
    f.rivals["tyne"]["cash"] = -int(0.3 * float(cfg["list"]["tyne"]["start_cash"]) * grown)
    f.advance_day()
    check(float(f.rivals["tyne"]["scale"]) < grown, "a company in debt shrinks")
    f.rivals["tyne"]["cash"] = -1000000000
    f.advance_day()
    check(f.rivals["tyne"]["status"] == "bankrupt" and float(f.rivals["tyne"]["scale"]) <= float(cfg["restart_scale"]) + 1e-9, "when it fails it restarts no bigger than the restart size")
    check(Companies.value(f, "tyne") < int(float(cfg["list"]["tyne"]["base_value"]) * 0.2), "so a failed giant is a cheap bargain, not a costly one")
    # A bigger company leaves a bigger hole.
    var s1 = GameState.new(fresh_data(), 1)
    var s2 = GameState.new(fresh_data(), 1)
    s2.rivals["tyne"]["scale"] = 2.0
    for st in [s1, s2]:
        st.rivals["tyne"]["strength"] = 0.0
        st.rivals["tyne"]["status"] = "bankrupt"
        st.rivals["tyne"]["bankrupt_days"] = 90
        for _d in 25:
            Companies.update_market(st, "smooth")
    check(float(s2.market.rival_mult["steel"]) > float(s1.market.rival_mult["steel"]) + 0.1, "a bigger company failing moves steel more (%.2f against %.2f)" % [float(s2.market.rival_mult["steel"]), float(s1.market.rival_mult["steel"])])
    # Bigger companies take offers more often.
    var offer: Dictionary = {"id": 1, "client": "railway", "resource": "steel", "quantity": 20, "premium": 1.2, "offered_day": 1}
    var t1: float = Companies.take_chance(s1, "tyne", offer) if false else 0.0
    s1.rivals["tyne"]["status"] = "healthy"
    s1.rivals["tyne"]["strength"] = 1.0
    s2.rivals["tyne"]["status"] = "healthy"
    s2.rivals["tyne"]["strength"] = 1.0
    check(Companies.take_chance(s2, "tyne", offer) > Companies.take_chance(s1, "tyne", offer) + t1, "a bigger company takes offers more often")
    # Saving keeps the size.
    var g = GameState.new(fresh_data(), 3)
    for _d in 60:
        g.advance_day()
    var g2 = GameState.new(fresh_data(), 3)
    check(g2.load_dict(JSON.parse_string(JSON.stringify(g.to_dict()))) and absf(float(g2.rivals["harlow"]["scale"]) - float(g.rivals["harlow"]["scale"])) < 1e-9 and float(g2.rivals["harlow"]["scale"]) > 1.0, "sizes survive the save")
    var bad: Variant = JSON.parse_string(JSON.stringify(g.to_dict()))
    bad["rivals"]["list"]["harlow"].erase("scale")
    check(not GameState.new(fresh_data(), 3).load_dict(bad), "a save without a rival's size is refused, not guessed")
    # Sam: nursing growth to resell, and how long a company takes to pay for itself.
    var h = GameState.new(fresh_data(), 6)
    h.money_cents = 1000000000
    var start: int = h.money_cents
    var paid: int = Companies.value(h, "blackwater")
    h.buy_company("blackwater")
    for _d in 100:
        h.advance_day()
    var div100: int = int(h.rival_stats["dividends_cents"])
    for _d in 200:
        h.advance_day()
    var sold: Dictionary = h.sell_company("blackwater")
    var net: int = h.money_cents - start
    print("      Sam: bought the best grower at %d, dividends %d after 100 days, sold after 300 days for %d (dividends %d), net %d dollars (%.0f%% of the price)" % [paid / 100, div100 / 100, int(sold["revenue"]) / 100, int(h.rival_stats["dividends_cents"]) / 100, net / 100, 100.0 * float(net) / float(paid)])
    check(div100 < paid / 2, "after 100 days the dividends are still less than half the price")
    check(int(sold["revenue"]) < paid, "a growing company still sells for less than it cost: growth alone is no profit")
    check(net > 0, "but held long enough, a good company does repay itself (net %d dollars)" % (net / 100))


func test_determinism() -> void:
    print("Determinism")
    var a = GameState.new(fresh_data(), 11)
    var b = GameState.new(fresh_data(), 11)
    for _d in 200:
        a.advance_day()
        b.advance_day()
    check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "same seed, same 200 days")
