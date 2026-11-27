extends SceneTree
## Sam's probe (informational): how does the board behave with premium-dependent lifetimes?
## Runs 600 days with no events and prints how many offers appear, how long they last, and how full the board is.
##   godot --headless --path . -s tests/sam_offer_probe.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")


func _init() -> void:
    var gd: Dictionary = DataLoader.load_game_data()
    gd = gd.duplicate()
    gd["events"] = gd["events"].duplicate(true)
    gd["events"]["chance_per_day"] = 0.0
    gd["balance"] = gd["balance"].duplicate(true)
    gd["balance"]["base_storage"] = 1000000
    var gs = GameState.new(gd, 8)
    gs.money_cents = 1000000000
    var seen: Dictionary = {}
    var occupancy: float = 0.0
    var empty_days: int = 0
    var days: int = 600
    for _d in days:
        gs.advance_day()
        for o in gs.board:
            if not seen.has(o["id"]):
                seen[o["id"]] = o.duplicate()
        occupancy += float(gs.board.size())
        if gs.board.is_empty():
            empty_days += 1
    var short: int = 0
    var long_: int = 0
    var hot_total: int = 0
    var life_hot: float = 0.0
    var life_dull: float = 0.0
    var dull_total: int = 0
    for id in seen:
        var o: Dictionary = seen[id]
        var life: int = int(o["expires_day"]) - int(o["offered_day"]) + 1
        if life <= 3:
            short += 1
        if life >= 10:
            long_ += 1
        if float(o["premium"]) >= 1.25:
            hot_total += 1
            life_hot += life
        elif float(o["premium"]) <= 1.12:
            dull_total += 1
            life_dull += life
    print("offers seen: %d in %d days (one every %.1f days)" % [seen.size(), days, float(days) / float(seen.size())])
    print("lasting 3 days or less: %d, lasting 10 days or more: %d" % [short, long_])
    print("offers paying 25%%+ over market: %d, average life %.1f days" % [hot_total, life_hot / maxf(1.0, hot_total)])
    print("offers paying 12%% or less over market: %d, average life %.1f days" % [dull_total, life_dull / maxf(1.0, dull_total)])
    print("average offers on the board: %.1f of %d, days with an empty board: %d%%" % [occupancy / days, int(gd["contracts"]["board_size"]), int(100.0 * empty_days / days)])
    quit(0)
