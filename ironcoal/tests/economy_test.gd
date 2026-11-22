extends SceneTree
## Sam's economy sanity test: reads the data files and checks that every building can pay for itself.
## It catches balance mistakes (like upkeep bigger than the value a factory adds) the moment a number is edited.
##   godot --headless --path . -s tests/economy_test.gd

const DataLoader = preload("res://sim/data_loader.gd")

const MAX_PAYBACK_MINE := 60.0      # days, deposit richness 1.0
const MAX_PAYBACK_FACTORY := 150.0  # days, running at full capacity, inputs valued at base prices

var failures: int = 0


func value_of(items: Dictionary, resources: Dictionary) -> float:
    var total: float = 0.0
    for id in items:
        total += float(resources[id]["base_price"]) * float(items[id])
    return total


func _init() -> void:
    var gd: Dictionary = DataLoader.load_game_data()
    var resources: Dictionary = gd["resources"]
    var buildings: Dictionary = gd["buildings"]
    print("%-18s %10s %9s %8s %9s" % ["Building", "Net $/day", "Build $", "Payback", "Limit"])
    for id in buildings:
        var b: Dictionary = buildings[id]
        if b["kind"] == "storage":
            continue
        var upkeep: float = float(b["upkeep_per_day"]) / 100.0
        var build: float = float(b["build_cost"]) / 100.0
        var gross: float
        var limit: float
        if b["kind"] == "extractor":
            gross = value_of(b["outputs"], resources) / 100.0
            limit = MAX_PAYBACK_MINE
        else:
            gross = (value_of(b["outputs"], resources) - value_of(b["inputs"], resources)) * float(b.get("batches_per_day", 1)) / 100.0
            limit = MAX_PAYBACK_FACTORY
        var net: float = gross - upkeep
        var payback: float = build / net if net > 0.0 else INF
        var ok: bool = net > 0.0 and payback <= limit
        if not ok:
            failures += 1
        print("%-18s %10.2f %9.0f %7.0fd %8.0fd  %s%s" % [str(b["name"]), net, build, payback, limit, "ok" if ok else "FAIL", "  (placeholder)" if b.get("placeholder", false) else ""])
    print("")
    print("%d buildings out of range" % failures)
    quit(1 if failures > 0 else 0)
