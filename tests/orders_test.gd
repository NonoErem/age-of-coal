extends SceneTree
## Headless tests for standing orders (automatic daily buying and selling).
##   godot --headless --path . -s tests/orders_test.gd

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


func data_with(base_storage: int = 100000) -> Dictionary:
    var gd: Dictionary = DataLoader.load_game_data()
    var out: Dictionary = gd.duplicate()
    out["balance"] = gd["balance"].duplicate(true)
    out["balance"]["trend_volatility"] = 0.0
    out["balance"]["trend_reversion"] = 0.0
    out["balance"]["base_storage"] = base_storage
    out["events"] = gd["events"].duplicate(true)
    out["events"]["chance_per_day"] = 0.0
    out["contracts"] = gd["contracts"].duplicate(true)
    return out


func new_state(base_storage: int = 100000) -> Object:
    var gs = GameState.new(data_with(base_storage))
    gs.money_cents = 100000000
    gs.board = []
    return gs


func news_of(gs, kind: String) -> Array:
    return gs.order_news.filter(func(n: Dictionary) -> bool: return n["kind"] == kind)


func _init() -> void:
    print("Starting an order")
    var gs = new_state()
    check(DataLoader.validate(DataLoader.load_game_data()).is_empty(), "the data is valid")
    check(gs.start_standing_order("coal", "sell", 20, 30)["ok"] and gs.standing_orders.size() == 1, "an order can be started on day 1, no offer needed")
    check(gs.start_standing_order("unobtainium", "sell", 1, 1)["reason"] == "unknown_resource", "unknown resource refused")
    check(gs.start_standing_order("coal", "swap", 1, 1)["reason"] == "invalid_side", "unknown side refused")
    check(gs.start_standing_order("coal", "sell", 0, 5)["reason"] == "invalid_quantity" and gs.start_standing_order("coal", "sell", 501, 5)["reason"] == "invalid_quantity", "quantity must be 1 to 500 a day")
    check(gs.start_standing_order("coal", "sell", 5, 0)["reason"] == "invalid_days" and gs.start_standing_order("coal", "sell", 5, 121)["reason"] == "invalid_days", "duration must be 1 to 120 days")
    check(gs.start_standing_order("coal", "sell", 5, 5, -1)["reason"] == "invalid_limit", "a negative price limit is refused")
    for i in 5:
        gs.start_standing_order("iron_ore", "buy", 1, 10)
    check(gs.standing_orders.size() == 6 and gs.start_standing_order("coal", "buy", 1, 1)["reason"] == "too_many_orders", "at most 6 orders at once")
    var first_id: int = int(gs.standing_orders[0]["id"])
    check(gs.cancel_standing_order(first_id)["ok"] and gs.standing_orders.size() == 5 and gs.cancel_standing_order(first_id)["reason"] == "unknown_order", "an order can be cancelled, once")

    print("Selling")
    gs = new_state()
    gs.inventory = {"coal": 100}
    gs.start_standing_order("coal", "sell", 20, 3)
    var money0: int = gs.money_cents
    gs.advance_day()
    check(gs.stock("coal") == 80 and gs.money_cents > money0 and gs.standing_orders[0]["units_done"] == 20 and gs.standing_orders[0]["days_left"] == 2, "each day it sells the same amount (20 coal)")
    gs.advance_day()
    gs.advance_day()
    check(gs.stock("coal") == 40 and gs.standing_orders.is_empty(), "after its last day it is gone")
    var fin: Array = news_of(gs, "finished")
    check(fin.size() == 1 and fin[0]["units"] == 60 and fin[0]["days"] == 3, "and reports what it did (60 units)")
    check(gs.money_cents > money0, "the money arrived")
    check(float(gs.market.presence["coal"]) > 0.0, "automatic sales count towards your presence in the market")

    print("Buying")
    gs = new_state()
    gs.inventory = {}
    gs.start_standing_order("coal", "buy", 10, 3)
    money0 = gs.money_cents
    for _d in 3:
        gs.advance_day()
    check(gs.stock("coal") == 30 and gs.money_cents < money0 and gs.standing_orders.is_empty(), "it buys the same amount each day (3 x 10)")

    print("A day with nothing to trade is lost")
    gs = new_state()
    gs.inventory = {"coal": 30}
    gs.start_standing_order("coal", "sell", 20, 4)
    gs.advance_day()
    check(gs.order_news.is_empty(), "a normal day says nothing")
    gs.advance_day()
    var partial: Array = news_of(gs, "problem")
    check(gs.stock("coal") == 0 and partial.size() == 1 and partial[0]["result"] == "partial_stock", "when stock runs short it sells what it can and says so (10 of 20)")
    gs.advance_day()
    check(news_of(gs, "problem").size() == 1 and news_of(gs, "problem")[0]["result"] == "no_stock", "then it reports the dry spell once")
    gs.advance_day()
    check(news_of(gs, "problem").is_empty() and news_of(gs, "finished").size() == 1 and gs.standing_orders.is_empty(), "and stays quiet until it ends (no spam)")
    check(news_of(gs, "finished")[0]["units"] == 30, "still the days count: it ended after 4 days having sold 30")

    gs = new_state()
    gs.inventory = {}
    gs.start_standing_order("coal", "sell", 20, 3)
    gs.advance_day()
    gs.inventory = {"coal": 50}
    gs.advance_day()
    check(news_of(gs, "recovered").size() == 1 and gs.stock("coal") == 30, "when it works again it says so")

    print("Buying has limits too")
    gs = new_state(60)
    gs.inventory = {"steel": 50}
    gs.start_standing_order("coal", "buy", 30, 2)
    gs.advance_day()
    check(gs.stock("coal") == 10 and news_of(gs, "problem")[0]["result"] == "partial_room", "it only buys what fits in storage (10 of 30)")
    gs.advance_day()
    check(gs.stock("coal") == 10, "and nothing more once full")

    gs = new_state()
    gs.inventory = {}
    gs.money_cents = 5000
    gs.start_standing_order("coal", "buy", 100, 2)
    gs.advance_day()
    check(gs.stock("coal") > 0 and gs.stock("coal") < 100 and gs.money_cents >= 0 and news_of(gs, "problem")[0]["result"] == "partial_money", "it only buys what you can pay for, and never goes into debt (%d units)" % gs.stock("coal"))
    gs.money_cents = 0
    gs.advance_day()
    check(gs.money_cents == 0, "with no money it buys nothing")

    print("Price limits")
    gs = new_state()
    gs.inventory = {"coal": 100}
    var base: float = gs.market.base_price("coal")
    gs.start_standing_order("coal", "sell", 10, 3, int(base))   # asks for at least the base price on average: the market pays less after the spread
    gs.advance_day()
    check(gs.stock("coal") == 100 and gs.standing_orders[0]["skipped"] == 1 and news_of(gs, "problem")[0]["result"] == "price", "a sell below your limit does not happen, and the day still counts")
    gs = new_state()
    gs.inventory = {"coal": 100}
    gs.start_standing_order("coal", "sell", 10, 3, 100)
    gs.advance_day()
    check(gs.stock("coal") == 90, "a sell above the limit goes ahead")
    gs = new_state()
    gs.inventory = {}
    gs.start_standing_order("coal", "buy", 10, 3, 500)   # will not pay more than $5 a unit: it costs about $10.9
    gs.advance_day()
    check(gs.stock("coal") == 0 and news_of(gs, "problem")[0]["result"] == "price", "a buy above your limit does not happen")

    print("Saving")
    gs = new_state()
    gs.inventory = {"coal": 200}
    gs.start_standing_order("coal", "sell", 15, 10, 100)
    gs.start_standing_order("iron_ore", "buy", 5, 8)
    for _d in 3:
        gs.advance_day()
    var parsed: Variant = JSON.parse_string(JSON.stringify(gs.to_dict()))
    var gs2 = GameState.new(data_with(), 1)
    check(gs2.load_dict(parsed), "a game with standing orders loads")
    check(gs2.standing_orders.size() == 2 and gs2.standing_orders[0]["days_left"] == 7 and gs2.standing_orders[0]["units_done"] == 45 and gs2.standing_orders[0]["limit_cents"] == 100, "progress, limits and totals come back")
    for _d in 12:
        gs.advance_day()
        gs2.advance_day()
    check(gs.stock("coal") == gs2.stock("coal") and gs.stock("iron_ore") == gs2.stock("iron_ore") and gs.money_cents == gs2.money_cents and gs2.standing_orders.is_empty(), "the loaded game carries the orders out identically")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
