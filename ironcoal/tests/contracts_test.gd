extends SceneTree
## Headless tests for contracts: board, delivery, failure, fairness, saving.
##   godot --headless --path . -s tests/contracts_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
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


func fresh_data(neutral_trend: bool = true) -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["contracts"] = gd["contracts"].duplicate(true)
    if neutral_trend:
        out["balance"]["trend_volatility"] = 0.0
        out["balance"]["trend_reversion"] = 0.0
    return out


func _init() -> void:
    print("Board")
    var gd: Dictionary = fresh_data()
    var gs = GameState.new(gd)
    check(gs.board.size() == 1 and gs.board[0]["resource"] == "coal" and gs.board[0]["quantity"] == 40, "a tutorial contract is waiting on day 1")
    check(gs.board[0]["unit_price"] == 1300, "tutorial pays 130% of the coal price ($13.00 a unit)")
    for _d in 200:
        gs.advance_day()
        if gs.board.size() > int(gd["contracts"]["board_size"]):
            check(false, "board never exceeds its size")
    check(gs.board.size() <= int(gd["contracts"]["board_size"]), "board never exceeds its size")
    var ok_prices: bool = true
    for o in gs.board:
        var ref: float = gs.market.reference_price(o["resource"])
        var ratio: float = float(o["unit_price"]) / ref
        if ratio < 1.04 or ratio > 1.36:
            ok_prices = false
    check(ok_prices, "offers pay 105-135%% of the market price")

    print("Accept and deliver")
    gd = fresh_data()
    gs = GameState.new(gd)
    var offer_id: int = int(gs.board[0]["id"])
    check(gs.accept_contract(offer_id)["ok"] and gs.board.is_empty() and gs.active_contracts.size() == 1, "accepting moves the offer to active")
    check(int(gs.active_contracts[0]["due_day"]) == 31, "tutorial is due on day 31")
    var money0: int = gs.money_cents
    var r: Dictionary = gs.deliver_contract(offer_id, 10)
    check(r["ok"] and not r["completed"] and gs.money_cents - money0 == 13000 and gs.stock("coal") == 40, "partial delivery is paid straight away ($130 for 10 coal)")
    check(gs.deliver_contract(offer_id, 31)["reason"] == "exceeds_contract", "cannot deliver more than the contract asks")
    gs.inventory["coal"] = 5
    check(gs.deliver_contract(offer_id, 10)["reason"] == "insufficient_stock", "cannot deliver what you do not have")
    gs.inventory["coal"] = 100
    r = gs.deliver_contract(offer_id, 30)
    check(r["ok"] and r["completed"] and gs.active_contracts.is_empty() and gs.contract_stats["completed"] == 1, "finishing the contract completes it")
    check(gs.contract_stats["earned_cents"] == 52000, "total earned is 40 x $13.00")

    print("Failure and penalty")
    gd = fresh_data()
    gs = GameState.new(gd)
    offer_id = int(gs.board[0]["id"])
    gs.accept_contract(offer_id)
    gs.deliver_contract(offer_id, 10)
    var money_after_delivery: int = gs.money_cents
    for _d in 30:
        gs.advance_day()
    check(gs.active_contracts.size() == 1, "still open on the due day")
    gs.advance_day()
    check(gs.active_contracts.is_empty() and gs.contract_stats["failed"] == 1, "fails the day after the deadline")
    check(money_after_delivery - gs.money_cents == 15600, "penalty is 40%% of the undelivered part: 30 x $13 x 0.4 = $156 (got %d)" % (money_after_delivery - gs.money_cents))
    check(gs.news.any(func(n: Dictionary) -> bool: return n["kind"] == "failed"), "failure shows up in the news")

    print("Limits")
    gd = fresh_data()
    gd["contracts"]["max_active"] = 1
    gs = GameState.new(gd)
    Contracts.generate_offer(gs)
    Contracts.generate_offer(gs)
    var a: int = int(gs.board[0]["id"])
    var b: int = int(gs.board[1]["id"])
    check(gs.accept_contract(a)["ok"] and gs.accept_contract(b)["reason"] == "too_many_active", "active contracts are capped")
    check(gs.accept_contract(9999)["reason"] == "unknown_offer", "unknown offer is refused")

    gd = fresh_data()
    gs = GameState.new(gd)
    var tutorial_id: int = int(gs.board[0]["id"])
    for _d in 61:
        gs.advance_day()
    var still_there: bool = false
    for o in gs.board:
        if int(o["id"]) == tutorial_id:
            still_there = true
    check(not still_there, "unaccepted offers expire")

    print("Fairness (Sam)")
    gd = fresh_data()
    gd["contracts"]["clients"] = {"shipyard": {"id": "shipyard", "name": "Shipyard", "wants": {"machinery": 1}}}
    gd["contracts"].erase("tutorial")
    gs = GameState.new(gd)
    gs.money_cents = 5000
    check(Contracts.generate_offer(gs).is_empty(), "no machinery contract for a player with $50 and no way to make any")
    gs.money_cents = 1000000000
    var offer: Dictionary = Contracts.generate_offer(gs)
    check(not offer.is_empty() and int(offer["quantity"]) <= Contracts.max_deliverable(gs, "machinery", int(offer["deadline_days"])), "with money, the offer stays within what could be delivered")

    gd = fresh_data()
    gs = GameState.new(gd)
    var ref_before: float = gs.market.reference_price("coal")
    var spot_before: float = gs.market.spot_price("coal")
    gs.money_cents = 1000000000
    gs.market.presence["coal"] = 300.0  # a major player, so its buying really moves the price
    gs.buy("coal", 300)
    check(gs.market.spot_price("coal") > spot_before * 1.5, "buying 300 coal pushes the spot price up a lot")
    check(is_equal_approx(gs.market.reference_price("coal"), ref_before), "but the contract reference price does not move (cannot be pumped)")

    print("Determinism and saving")
    var g1 = GameState.new(fresh_data(false), 42)
    var g2 = GameState.new(fresh_data(false), 42)
    for _d in 80:
        g1.advance_day()
        g2.advance_day()
    check(JSON.stringify(g1.board) == JSON.stringify(g2.board), "same seed gives the same board")
    var prices_equal: bool = true
    var g3 = GameState.new(fresh_data(false), 42)
    g3.contract_rng.seed = 1
    for _d in 80:
        g3.advance_day()
    for id in g1.data["resources"]:
        if not is_equal_approx(g1.market.spot_price(id), g3.market.spot_price(id)):
            prices_equal = false
    check(prices_equal, "contracts use their own random stream: market prices do not depend on them")

    gd = fresh_data(false)
    gs = GameState.new(gd, 9)
    gs.accept_contract(int(gs.board[0]["id"]))
    gs.deliver_contract(int(gs.active_contracts[0]["id"]), 15)
    for _d in 20:
        gs.advance_day()
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(gd, 1)
    check(gs2.load_dict(parsed), "save loads back")
    check(gs2.board.size() == gs.board.size() and gs2.active_contracts.size() == gs.active_contracts.size() and gs2.contract_stats == gs.contract_stats, "board, active contracts and stats survive")
    for _d in 40:
        gs.advance_day()
        gs2.advance_day()
    check(JSON.stringify(gs.board) == JSON.stringify(gs2.board) and gs.money_cents == gs2.money_cents and gs.contract_stats == gs2.contract_stats, "a loaded game continues identically")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
