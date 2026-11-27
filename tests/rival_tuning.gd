extends SceneTree
## Dev tool for tuning: tries parameter sets. Shows how often rivals go bankrupt on their own (no player)
## and whether one forced failure (Tyne Steel) spreads to the others. Edit _init() to try other numbers.
##   godot --headless --path . -s tests/rival_tuning.gd
const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")

func run(label: String, over: Dictionary, cash_scale: float) -> void:
    var base: Dictionary = DataLoader.load_game_data()
    var busts: int = 0
    var weak_days: int = 0
    var seeds: Array = [1, 2, 3, 4, 5, 6]
    for sd in seeds:
        var gd: Dictionary = DataLoader.load_game_data()
        for k in over:
            gd["companies"][k] = over[k]
        for id in gd["companies"]["list"]:
            gd["companies"]["list"][id]["start_cash"] = int(float(gd["companies"]["list"][id]["start_cash"]) * cash_scale)
        var gs = GameState.new(gd, sd)
        for d in 1500:
            gs.advance_day()
            for n in gs.rival_news:
                if n["kind"] == "bankrupt":
                    busts += 1
            for id in gs.rivals:
                if gs.rivals[id]["status"] != "healthy":
                    weak_days += 1
    # cascade: force Tyne bust (calm prices), count others' bankrupt-days over 400 days
    var spread_days: int = 0
    var others_bust: int = 0
    for sd in seeds:
        var gd: Dictionary = DataLoader.load_game_data()
        gd["balance"]["trend_volatility"] = 0.0
        gd["balance"]["trend_reversion"] = 0.0
        gd["events"]["chance_per_day"] = 0.0
        for k in over:
            gd["companies"][k] = over[k]
        for id in gd["companies"]["list"]:
            gd["companies"]["list"][id]["start_cash"] = int(float(gd["companies"]["list"][id]["start_cash"]) * cash_scale)
        var gs = GameState.new(gd, sd)
        gs.rivals["tyne"]["cash"] = -1000000000
        for d in 400:
            gs.advance_day()
            for id in gs.rivals:
                if id != "tyne" and gs.rivals[id]["status"] != "healthy":
                    spread_days += 1
            for n in gs.rival_news:
                if n["kind"] == "bankrupt" and n["company"] != "tyne":
                    others_bust += 1
    print("%-34s natural busts %2d per 9000d, unhealthy-days %4d | forced Tyne: others unhealthy-days %4d (per run), others busted %d" % [label, busts, weak_days, spread_days / seeds.size(), others_bust])

func _init() -> void:
    run("feel 1.0 (idle .5)", {"rival_feel": 1.0}, 1.0)
    run("feel 0.5 idle .5", {"rival_feel": 0.5}, 1.0)
    run("feel 0.3 idle .5", {"rival_feel": 0.3}, 1.0)
    run("feel 0.3 idle .35", {"rival_feel": 0.3, "idle_overhead": 0.35}, 1.0)
    run("feel 0.3 idle .5 cash .7", {"rival_feel": 0.3}, 0.7)
    run("feel 0.5 idle .5 cash .7", {"rival_feel": 0.5}, 0.7)
    run("feel 0.0 idle .5", {"rival_feel": 0.0}, 1.0)
    quit()
