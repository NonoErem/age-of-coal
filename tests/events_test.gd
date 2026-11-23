extends SceneTree
## Headless tests for market events.
##   godot --headless --path . -s tests/events_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const MarketEvents = preload("res://sim/market_events.gd")
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


## chance: probability of a new event each day. Trend noise is off so only events move prices.
func data_with(chance: float, max_concurrent: int = 3) -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["balance"]["trend_volatility"] = 0.0
    out["balance"]["trend_reversion"] = 0.0
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = chance
    out["events"]["max_concurrent"] = max_concurrent
    return out


func days(gs, n: int) -> void:
    for _d in n:
        gs.advance_day()


func all_events(gs) -> Array:
    var me: Dictionary = gs.market_events
    return me["upcoming"] + me["active"] + me["past"]


func _init() -> void:
    print("Data")
    var errors: Array = DataLoader.validate(DataLoader.load_game_data())
    for e in errors:
        print("    ", e)
    check(errors.is_empty(), "events.json is consistent")

    print("Timeline")
    var gs = GameState.new(data_with(0.0))
    days(gs, 200)
    check(all_events(gs).is_empty(), "with no chance of events, none happen")

    gs = GameState.new(data_with(0.0))
    var strike: Dictionary = MarketEvents.announce(gs, "miners_strike")
    var lead: int = int(strike["start_day"]) - gs.day
    check(lead >= 3 and lead <= 8, "an event is announced 3-8 days ahead (%d)" % lead)
    var dur: int = int(strike["end_day"]) - int(strike["start_day"]) + 1
    check(dur >= 15 and dur <= 25, "and lasts 15-25 days for a strike (%d)" % dur)
    check(gs.event_news.any(func(n: Dictionary) -> bool: return n["kind"] == "announced"), "the announcement is reported")
    MarketEvents.apply_to_market(gs)
    check(is_equal_approx(float(gs.market.shock_mult["coal"]), 1.0), "on the day of the announcement prices have not moved yet")
    var base_coal: float = gs.market.base_price("coal")
    var halfway: int = int(strike["announced_day"]) + lead / 2
    while gs.day < halfway:
        gs.advance_day()
    var expected: float = 1.0 + 0.40 * 0.5 * (float(gs.day - int(strike["announced_day"])) / float(lead))
    check(is_equal_approx(float(gs.market.shock_mult["coal"]), expected) and expected > 1.0, "before it starts, prices drift partway (x%.3f, anticipation)" % expected)
    while gs.day < int(strike["start_day"]):
        gs.advance_day()
    check(is_equal_approx(float(gs.market.shock_mult["coal"]), 1.40) and gs.market_events["active"].size() == 1, "on the start day the full effect applies")
    check(is_equal_approx(gs.market.reference_price("coal"), base_coal * 1.40), "prices are 40% up")
    check(is_equal_approx(gs.history["coal"][-1], gs.market.spot_price("coal")), "the price chart shows it")
    while gs.day < int(strike["end_day"]):
        gs.advance_day()
    check(gs.market_events["active"].size() == 1, "still running on its last day")
    gs.advance_day()
    check(gs.market_events["active"].is_empty() and gs.market_events["past"].size() == 1 and is_equal_approx(float(gs.market.shock_mult["coal"]), 1.0), "afterwards prices return to normal")

    print("Stacking and limits")
    gs = GameState.new(data_with(0.0))
    var e1: Dictionary = MarketEvents.announce(gs, "miners_strike")
    var e2: Dictionary = MarketEvents.announce(gs, "rearmament")
    e1["start_day"] = gs.day
    e2["start_day"] = gs.day
    gs.advance_day()
    check(is_equal_approx(float(gs.market.shock_mult["coal"]), 1.40 * 1.15), "events on the same resource multiply (coal x%.2f)" % float(gs.market.shock_mult["coal"]))
    check(is_equal_approx(float(gs.market.shock_mult["tools"]), 1.30) and is_equal_approx(float(gs.market.shock_mult["copper_ore"]), 1.0), "other resources only feel the events that touch them")

    gs = GameState.new(data_with(1.0, 2))
    var worst: int = 0
    var duplicate: bool = false
    for _d in 120:
        gs.advance_day()
        var running: Array = gs.market_events["upcoming"] + gs.market_events["active"]
        worst = maxi(worst, running.size())
        var seen: Dictionary = {}
        for e in running:
            if seen.has(e["type"]):
                duplicate = true
            seen[e["type"]] = true
    check(worst == 2, "never more than max_concurrent events at once (%d)" % worst)
    check(not duplicate, "never two of the same kind at once")

    gs = GameState.new(data_with(1.0, 3))
    var early_ok: bool = true
    for _d in 60:
        gs.advance_day()
    for e in all_events(gs):
        var def: Dictionary = gs.data["events"]["events"][e["type"]]
        if int(def["min_day"]) > int(e["announced_day"]):
            early_ok = false
    check(early_ok and all_events(gs).size() > 3, "late-game events (recession, rearmament) never come early")

    gs = GameState.new(data_with(1.0, 1))
    var recurrence_ok: bool = true
    var last_end: Dictionary = {}
    for _d in 400:
        gs.advance_day()
    var by_type: Dictionary = {}
    for e in all_events(gs):
        if by_type.has(e["type"]):
            var gap: int = int(e["start_day"]) - int(by_type[e["type"]]["end_day"])
            if gap < int(gs.data["events"]["events"][e["type"]]["cooldown"]):
                recurrence_ok = false
        by_type[e["type"]] = e
    check(recurrence_ok, "an event kind cannot come back before its cooldown")

    print("Exposure: the bigger you are, the likelier a crash hits you")
    var glut_small: int = 0
    var glut_big: int = 0
    gs = GameState.new(data_with(0.0))
    gs.day = 100
    for _i in 600:
        if MarketEvents.choose_type(gs) == "coal_glut":
            glut_small += 1
    gs.market.presence["coal"] = 300.0
    for _i in 600:
        if MarketEvents.choose_type(gs) == "coal_glut":
            glut_big += 1
    check(glut_big > glut_small * 1.4, "a coal giant sees coal gluts %d times in 600 draws, a newcomer %d" % [glut_big, glut_small])
    var boom_small: int = 0
    var boom_big: int = 0
    gs = GameState.new(data_with(0.0))
    gs.day = 100
    for _i in 600:
        if MarketEvents.choose_type(gs) == "miners_strike":
            boom_small += 1
    gs.market.presence["coal"] = 300.0
    for _i in 600:
        if MarketEvents.choose_type(gs) == "miners_strike":
            boom_big += 1
    check(boom_big < boom_small, "while the coal giant sees fewer strikes (%d vs %d), because exposure only boosts the crashes" % [boom_big, boom_small])

    print("Contracts and events (Sam)")
    gs = GameState.new(data_with(0.0))
    gs.board.append({"id": 900, "client": "gasworks", "resource": "coal", "quantity": 40, "unit_price": 1300, "deadline_days": 30, "offered_day": 1, "expires_day": 60})
    var board_before: int = gs.board.size()
    MarketEvents.announce(gs, "miners_strike")
    var coal_left: bool = false
    for o in gs.board:
        if o["resource"] == "coal":
            coal_left = true
    check(not coal_left and gs.board.size() < board_before, "announcing a coal event pulls the coal offers from the board")
    check(gs.event_news.any(func(n: Dictionary) -> bool: return n["kind"] == "withdrawn"), "and reports it")
    gs.money_cents = 100000000
    var coal_offers: int = 0
    for _i in 400:
        var offer: Dictionary = Contracts.generate_offer(gs)
        if not offer.is_empty() and offer["resource"] == "coal":
            coal_offers += 1
    check(coal_offers == 0, "no coal offers are made while a coal event is announced or running")
    var other_offers: int = 0
    for _i in 100:
        if not Contracts.generate_offer(gs).is_empty():
            other_offers += 1
    check(other_offers > 20, "offers for unaffected goods carry on (%d)" % other_offers)

    print("Saving and determinism")
    gs = GameState.new(data_with(0.3), 5)
    days(gs, 30)
    var gs_b = GameState.new(data_with(0.3), 5)
    days(gs_b, 30)
    check(JSON.stringify(gs.market_events) == JSON.stringify(gs_b.market_events), "same seed gives the same events")
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(data_with(0.3), 1)
    check(gs2.load_dict(parsed), "a game with events saves and loads")
    check(gs2.market_events["upcoming"].size() == gs.market_events["upcoming"].size() and gs2.market_events["active"].size() == gs.market_events["active"].size() and gs2.market_events["past"].size() == gs.market_events["past"].size(), "running, announced and past events come back")
    days(gs, 60)
    days(gs2, 60)
    var same: bool = JSON.stringify(gs.market_events) == JSON.stringify(gs2.market_events)
    for id in gs.data["resources"]:
        if absf(gs.market.spot_price(id) - gs2.market.spot_price(id)) > 0.001:
            same = false
    check(same, "the loaded game goes on to the same events and prices")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
