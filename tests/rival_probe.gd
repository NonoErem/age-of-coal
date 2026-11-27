extends SceneTree
## Sam's long-run probe: no player at all, many seeds. How often do rivals weaken, go bankrupt, come back?
## Run: godot --headless --path . -s tests/rival_probe.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")


func _init() -> void:
    var gd: Dictionary = DataLoader.load_game_data()
    var days: int = 1500
    var seeds: Array = [1, 2, 3, 4, 5, 6]
    var ids: Array = gd["companies"]["list"].keys()
    var time_weak: Dictionary = {}
    var time_bust: Dictionary = {}
    var busts: Dictionary = {}
    for id in ids:
        time_weak[id] = 0
        time_bust[id] = 0
        busts[id] = 0
    var mult_lo: float = 9.0
    var mult_hi: float = 0.0
    var mult_where: String = ""
    var pr: Dictionary = {}
    for sd in seeds:
        var gs = GameState.new(gd, sd)
        for d in days:
            gs.advance_day()
            for n in gs.rival_news:
                if n["kind"] == "bankrupt":
                    busts[n["company"]] += 1
            for id in ids:
                var st: String = str(gs.rivals[id]["status"])
                if st == "weakened":
                    time_weak[id] += 1
                elif st == "bankrupt":
                    time_bust[id] += 1
            for res in gd["resources"]:
                var m: float = float(gs.market.rival_mult[res])
                if m < mult_lo:
                    mult_lo = m
                    mult_where = "%s low seed %d day %d" % [res, sd, d]
                mult_hi = maxf(mult_hi, m)
    var total: float = float(days * seeds.size())
    print("%d seeds x %d days, no player" % [seeds.size(), days])
    print("%-10s %9s %9s %7s" % ["company", "weakened%", "bankrupt%", "busts"])
    for id in ids:
        print("%-10s %8.1f%% %8.1f%% %7d" % [id, 100.0 * time_weak[id] / total, 100.0 * time_bust[id] / total, busts[id]])
    print("rival price multiplier range %.2f .. %.2f (lowest: %s)" % [mult_lo, mult_hi, mult_where])
    quit()
