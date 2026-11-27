extends SceneTree
## Sam's probe (informational, exits 0): can you get rich by buying a resource when a price rise is announced
## and selling it while the event runs? Prints the profit for different amounts, with and without
## the "anticipation" effect (prices drifting before the event starts).
##   godot --headless --path . -s tests/sam_event_probe.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const MarketEvents = preload("res://sim/market_events.gd")


func run_case(amount: int, anticipation: float, wait_days: int) -> float:
    var gd: Dictionary = DataLoader.load_game_data()
    gd = gd.duplicate()
    gd["balance"] = gd["balance"].duplicate(true)
    gd["balance"]["trend_volatility"] = 0.0
    gd["balance"]["trend_reversion"] = 0.0
    gd["balance"]["base_storage"] = 1000000  # measure the pure price effect, ignoring room
    gd["events"] = gd["events"].duplicate(true)
    gd["events"]["chance_per_day"] = 0.0
    gd["events"]["anticipation"] = anticipation
    var gs = GameState.new(gd, 3)
    gs.money_cents = 1000000000
    gs.inventory["coal"] = 0  # start from nothing so only the speculation is measured
    var strike: Dictionary = MarketEvents.announce(gs, "miners_strike")
    MarketEvents.apply_to_market(gs)
    for _w in wait_days:
        gs.advance_day()
    var cost: int = int(gs.buy("coal", amount)["cost"])
    while gs.day < int(strike["start_day"]):
        gs.advance_day()
    var days_running: int = int(strike["end_day"]) - int(strike["start_day"]) + 1
    var revenue: int = 0
    var per_day: int = maxi(1, int(ceil(float(amount) / float(days_running))))
    for _d in days_running:
        var n: int = mini(per_day, gs.stock("coal"))
        if n > 0:
            revenue += int(gs.sell("coal", n)["revenue"])
        gs.advance_day()
    return 100.0 * float(revenue - cost) / float(cost)


func _init() -> void:
    print("Buy coal when a strike is announced (+40%), sell evenly while it runs. Profit on the money spent:")
    print("%-8s %16s %18s %18s" % ["Amount", "buy at news", "buy 2 days later", "same, no drift"])
    for amount in [50, 100, 200, 400, 800]:
        print("%-8d %+15.1f%% %+17.1f%% %+17.1f%%" % [amount, run_case(amount, 0.5, 0), run_case(amount, 0.5, 2), run_case(amount, 0.0, 2)])
    quit(0)
