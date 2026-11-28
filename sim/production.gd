extends RefCounted
## Daily production and upkeep.
## Buildings run in the order they were built, so results are deterministic.
## A factory is never removed when its inputs run out: it is paused with a status
## and restarts by itself as soon as the inputs are back.

const Crisis = preload("res://sim/crisis.gd")
const People = preload("res://sim/people.gd")
const STATUS_BUILT := "built"
const STATUS_RUNNING := "running"
const STATUS_PAUSED := "paused_missing_input"
const STATUS_DEPLETED := "depleted"
const STATUS_BLOCKED := "paused_storage_full"  # nowhere to put what it makes
const STATUS_STOPPED := "stopped"              # paused by the player
const STATUS_DAMAGED := "damaged"              # hit by the creatures: does nothing until repaired
const STATUS_NO_CREW := "no_crew"              # nobody to work it (see people.gd)

## States where a building only keeps a skeleton crew.
const IDLE_STATUSES := [STATUS_PAUSED, STATUS_DEPLETED, STATUS_BLOCKED, STATUS_STOPPED, STATUS_DAMAGED, STATUS_NO_CREW]


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
        elif Crisis.holds_post(kind):
            pass  # defenses and shelters act in the crisis step; they keep a full crew
        elif int(b.get("health", 1 << 30)) < Crisis.max_health(state, b):
            b["status"] = STATUS_DAMAGED
            b["batches"] = 0
        elif (kind == "extractor" or kind == "factory") and People.crew_ratio(state, b) <= 0.0:
            b["status"] = STATUS_NO_CREW
            b["batches"] = 0
        elif kind == "extractor":
            _run_extractor(state, b, def, produced, People.crew_ratio(state, b))
        elif kind == "factory":
            _run_factory(state, b, def, produced, consumed, People.crew_ratio(state, b))
        _note_change(state, b, previous)
        upkeep += upkeep_of(def, str(b["status"]), idle_factor, People.upkeep_mult(state, b))
    return {"produced": produced, "consumed": consumed, "upkeep_cents": upkeep}


## A paused factory or a depleted mine only keeps a skeleton crew.
## `mult` is the invasion's labour discount (see People.upkeep_mult); the idle share applies to the lowered wage.
static func upkeep_of(def: Dictionary, status: String, idle_factor: float, mult: float = 1.0) -> int:
    var cost: float = float(def["upkeep_per_day"]) * mult
    if IDLE_STATUSES.has(status):
        cost *= idle_factor
    return int(round(cost))


## What the buildings cost per day in their current state.
static func current_upkeep(state) -> int:
    var idle_factor: float = float(state.data["balance"]["idle_upkeep_factor"])
    var total: int = 0
    for b in state.buildings:
        total += upkeep_of(state.data["buildings"][b["type"]], str(b["status"]), idle_factor, People.upkeep_mult(state, b))
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


## `crew` (0 to 1) is the share of its crew the building has: it works in proportion.
static func _run_extractor(state, b: Dictionary, def: Dictionary, produced: Dictionary, crew: float = 1.0) -> void:
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
        carry[res] = float(carry.get(res, 0.0)) + float(outputs[res]) * richness * taper * crew
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


static func _run_factory(state, b: Dictionary, def: Dictionary, produced: Dictionary, consumed: Dictionary, crew: float = 1.0) -> void:
    var inputs: Dictionary = def["inputs"]
    # A factory runs up to batches_per_day batches, as many as its stock allows.
    # A short crew runs fewer: fractions carry to the next day, so half a crew really averages half the batches.
    var allowance: float = float(def.get("batches_per_day", 1)) * crew + float(b.get("batch_carry", 0.0))
    var crew_cap: int = int(floor(allowance + 1e-9))
    var batches: int = crew_cap
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
    # Only a crew-limited day carries its fraction over; idle days do not bank batches.
    b["batch_carry"] = (allowance - float(crew_cap)) if (batches == crew_cap and crew < 1.0) else 0.0
    if batches <= 0:
        if crew_cap <= 0 and missing.is_empty() and not space_limited:
            b["status"] = STATUS_RUNNING  # a short crew between batches: still at work
            b["missing"] = []
            b["batches"] = 0
            return
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
