extends SceneTree
## Tuning tool for the crisis burden on rival companies (informational).
## For several settings, plays 3 seeds with no player activity and reports when each rival first goes bankrupt
## after the landing, next to its size at the landing. Goal: small companies fail first, big ones last longer,
## none survives forever.
##   godot --headless --path . -s tests/crisis_rival_tuning.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")


func trial(burden: float, shield: float, seed: int) -> Array:
    var data: Dictionary = DataLoader.load_game_data()
    data["crisis"]["rivals"]["burden_per_year"] = burden
    data["crisis"]["rivals"]["size_shield"] = shield
    var gs = GameState.new(data, seed)
    var landing: int = int(data["crisis"]["landing_day"])
    var size_at: Dictionary = {}
    var fail_at: Dictionary = {}
    for d in 1500:
        gs.advance_day()
        if gs.day == landing:
            for id in gs.rivals:
                size_at[id] = float(gs.rivals[id]["scale"]) if gs.rivals[id]["status"] != "bankrupt" else 0.0
        if gs.day > landing:
            for id in gs.rivals:
                if not fail_at.has(id) and gs.rivals[id]["status"] == "bankrupt":
                    fail_at[id] = gs.day - landing
    var out: Array = []
    for id in gs.rivals:
        out.append([float(size_at.get(id, 0.0)), int(fail_at.get(id, 9999)), id])
    out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    return out


func _init() -> void:
    for setting in [[2.0, 0.7], [3.0, 0.7], [3.0, 0.5]]:
        print("\nburden_per_year %.1f  size_shield %.1f   (size at landing -> days after landing until bankrupt)" % setting)
        for seed in [1, 2, 3]:
            var rows: Array = trial(setting[0], setting[1], seed)
            var parts: Array = []
            var corr_small: Array = []
            for r in rows:
                parts.append("%s x%.1f->%s" % [str(r[2]).substr(0, 4), r[0], "-" if r[1] == 9999 else str(r[1])])
            print("  seed %d: %s" % [seed, "  ".join(parts)])
    quit(0)
