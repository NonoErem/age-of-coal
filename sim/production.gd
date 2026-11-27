extends RefCounted
## Daily production and upkeep.
## Buildings run in the order they were built, so results are deterministic.
## A factory is never removed when its inputs run out: it is paused with a status
## and restarts by itself as soon as the inputs are back.

const STATUS_BUILT := "built"
const STATUS_RUNNING := "running"
const STATUS_PAUSED := "paused_missing_input"
const STATUS_DEPLETED := "depleted"
const STATUS_BLOCKED := "paused_storage_full"  # nowhere to put what it makes
const STATUS_STOPPED := "stopped"              # paused by the player

## States where a building only keeps a skeleton crew.
const IDLE_STATUSES := [STATUS_PAUSED, STATUS_DEPLETED, STATUS_BLOCKED, STATUS_STOPPED]


## Runs one day for every building and returns a report.
static func run_day(state) -> Dictionary:
    var produced: Dictionary = {}
    var consumed: Dictionary = {}
    var upkeep: int = 0
    var defs: Dictionary = state.data["buildings"]
    var idle_factor: float = float(state.data["balance"]["idle_upkeep_factor"])
    for b in state.buildings:
        var def: Dictionary = defs[b["type"]]
        var kind: String = str(def["kind"])
        var previous: String = str(b["status"])
        if b.get("stopped", false):
            b["status"] = STATUS_STOPPED
        elif kind == "extractor":
            _run_extractor(state, b, def, produced)
        elif kind == "factory":
            _run_factory(state, b, def, produced, consumed)
        _note_change(state, b, previous)
        upkeep += upkeep_of(def, str(b["status"]), idle_factor)
    return {"produced": produced, "consumed": consumed, "upkeep_cents": upkeep}


## A paused factory or a depleted mine only keeps a skeleton crew.
static func upkeep_of(def: Dictionary, status: String, idle_factor: float) -> int:
    var cost: int = int(def["upkeep_per_day"])
    if IDLE_STATUSES.has(status):
        cost = int(round(float(cost) * idle_factor))
    return cost


## What the buildings cost per day in their current state.
static func current_upkeep(state) -> int:
    var idle_factor: float = float(state.data["balance"]["idle_upkeep_factor"])
    var total: int = 0
    for b in state.buildings:
        total += upkeep_of(state.data["buildings"][b["type"]], str(b["status"]), idle_factor)
    return total


static func _note_change(state, b: Dictionary, previous: String) -> void:
    var now: String = str(b["status"])
    if now == previous:
        return
    var kind: String = ""
    if now == STATUS_PAUSED:
        kind = "paused"
    elif now == STATUS_BLOCKED:
        kind = "blocked"
    elif now == STATUS_DEPLETED:
        kind = "depleted"
    elif now == STATUS_RUNNING and (previous == STATUS_PAUSED or previous == STATUS_BLOCKED):
        kind = "resumed"
    if kind != "":
        state.events.append({"kind": kind, "uid": b["uid"], "type": b["type"], "x": b["x"], "y": b["y"], "missing": b["missing"].duplicate()})


static func _add(inv: Dictionary, id: String, qty: int) -> void:
    inv[id] = int(inv.get(id, 0)) + qty


static func _run_extractor(state, b: Dictionary, def: Dictionary, produced: Dictionary) -> void:
    var balance: Dictionary = state.data["balance"]
    var dep: Dictionary = state.deposits[b["deposit_id"]]
    var info: Dictionary = state.data["map"]["deposits"][b["deposit_id"]]
    if int(dep["remaining"]) <= 0:
        b["status"] = STATUS_DEPLETED
        return
    # Output tapers off over the last part of the deposit.
    var initial: float = float(info["amount"])
    var threshold: float = float(balance["taper_threshold"])
    var taper: float = 1.0
    if float(dep["remaining"]) < initial * threshold:
        taper = maxf(float(balance["taper_floor"]), float(dep["remaining"]) / (initial * threshold))
    var richness: float = float(info["richness"])
    var outputs: Dictionary = def["outputs"]
    var carry: Dictionary = b["carry"]
    var stuck: bool = false
    for res in outputs:
        if state.free_space() <= 0:
            stuck = true  # no room: nothing is dug and nothing piles up
            continue
        # Fractions carry over to the next day, so 5.6 units/day really averages 5.6.
        carry[res] = float(carry.get(res, 0.0)) + float(outputs[res]) * richness * taper
        var possible: int = mini(int(floor(float(carry[res]) + 1e-9)), int(dep["remaining"]))
        var whole: int = mini(possible, state.free_space())
        if whole < possible:
            # What does not fit is lost; only the fraction stays.
            carry[res] = maxf(0.0, float(carry[res]) - float(possible - whole))
            stuck = stuck or whole == 0
        if whole > 0:
            carry[res] = maxf(0.0, float(carry[res]) - float(whole))
            dep["remaining"] = int(dep["remaining"]) - whole
            _add(state.inventory, res, whole)
            _add(produced, res, whole)
    if int(dep["remaining"]) <= 0:
        b["status"] = STATUS_DEPLETED
    elif stuck:
        b["status"] = STATUS_BLOCKED
    else:
        b["status"] = STATUS_RUNNING


static func _run_factory(state, b: Dictionary, def: Dictionary, produced: Dictionary, consumed: Dictionary) -> void:
    var inputs: Dictionary = def["inputs"]
    # A factory runs up to batches_per_day batches, as many as its stock allows.
    var batches: int = int(def.get("batches_per_day", 1))
    var missing: Array = []
    for res in inputs:
        var need: int = int(inputs[res])
        batches = mini(batches, floori(float(state.stock(res)) / float(need)))
        if state.stock(res) < need:
            missing.append(res)
    # A recipe that makes more units than it uses needs room for the difference.
    var net_units: int = 0
    for res in def["outputs"]:
        net_units += int(def["outputs"][res])
    for res in inputs:
        net_units -= int(inputs[res])
    var space_limited: bool = false
    if net_units > 0:
        var fit: int = floori(float(state.free_space()) / float(net_units))
        if fit < batches:
            batches = fit
            space_limited = true
    if batches <= 0:
        b["status"] = STATUS_BLOCKED if (space_limited and missing.is_empty()) else STATUS_PAUSED
        b["missing"] = missing
        b["batches"] = 0
        return
    for res in inputs:
        _add(state.inventory, res, -int(inputs[res]) * batches)
        _add(consumed, res, int(inputs[res]) * batches)
    var outputs: Dictionary = def["outputs"]
    for res in outputs:
        _add(state.inventory, res, int(outputs[res]) * batches)
        _add(produced, res, int(outputs[res]) * batches)
    b["status"] = STATUS_RUNNING
    b["missing"] = []
    b["batches"] = batches
