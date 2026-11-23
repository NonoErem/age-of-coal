extends RefCounted
## Loads the JSON data files and checks them for mistakes.
## No class_name on purpose: other scripts preload this file, so no editor import step is needed.

static func load_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        push_error("Missing data file: %s" % path)
        return null
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if parsed == null:
        push_error("Invalid JSON in %s" % path)
    return parsed


static func load_game_data(dir: String = "res://data") -> Dictionary:
    var map: Variant = load_json(dir + "/map.json")
    var map_out: Dictionary = {}
    if typeof(map) == TYPE_DICTIONARY:
        map_out = map
        map_out["deposits"] = _index_by_id(map.get("deposits", []))
    var contracts: Variant = load_json(dir + "/contracts.json")
    var contracts_out: Dictionary = {}
    if typeof(contracts) == TYPE_DICTIONARY:
        contracts_out = contracts
        contracts_out["clients"] = _index_by_id(contracts.get("clients", []))
    var events: Variant = load_json(dir + "/events.json")
    var events_out: Dictionary = {}
    if typeof(events) == TYPE_DICTIONARY:
        events_out = events
        events_out["events"] = _index_by_id(events.get("events", []))
    return {
        "events": events_out,
        "balance": load_json(dir + "/balance.json"),
        "resources": _index_by_id(load_json(dir + "/resources.json")),
        "buildings": _index_by_id(load_json(dir + "/buildings.json")),
        "map": map_out,
        "contracts": contracts_out,
    }


static func _index_by_id(list: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(list) != TYPE_ARRAY:
        return out
    for item in list:
        out[str(item["id"])] = item
    return out


## Returns a list of human-readable problems. Empty list = data is consistent.
static func validate(data: Dictionary) -> Array:
    var errors: Array = []
    if typeof(data.get("balance")) != TYPE_DICTIONARY:
        errors.append("balance.json failed to load")
        return errors
    var resources: Dictionary = data["resources"]
    var buildings: Dictionary = data["buildings"]
    var map: Dictionary = data["map"]
    if resources.is_empty():
        errors.append("resources.json is empty or failed to load")
    if buildings.is_empty():
        errors.append("buildings.json is empty or failed to load")

    for id in resources:
        var r: Dictionary = resources[id]
        if int(r.get("base_price", 0)) <= 0:
            errors.append("resource %s: base_price missing or <= 0" % id)
        if r.has("depth") and float(r["depth"]) <= 0.0:
            errors.append("resource %s: depth must be > 0" % id)

    for id in buildings:
        var b: Dictionary = buildings[id]
        for key in ["inputs", "outputs"]:
            var block: Dictionary = b.get(key, {})
            for res_id in block:
                if not resources.has(res_id):
                    errors.append("building %s: unknown resource '%s' in %s" % [id, res_id, key])
        if int(b.get("batches_per_day", 1)) < 1:
            errors.append("building %s: batches_per_day must be >= 1" % id)
        if int(b.get("cycle_days", 1)) != 1:
            errors.append("building %s: only cycle_days = 1 is supported for now" % id)
        if b.get("kind", "") == "extractor":
            if not resources.has(b.get("deposit", "")):
                errors.append("building %s: deposit '%s' is not a resource" % [id, b.get("deposit", "")])

    if not map.has("width") or not map.has("height"):
        errors.append("map.json failed to load or has no width/height")
    else:
        var w: int = int(map["width"])
        var h: int = int(map["height"])
        var seen: Dictionary = {}
        for id in map["deposits"]:
            var d: Dictionary = map["deposits"][id]
            var x: int = int(d.get("x", -1))
            var y: int = int(d.get("y", -1))
            var key: String = "%d,%d" % [x, y]
            if x < 0 or y < 0 or x >= w or y >= h:
                errors.append("deposit %s: position (%d,%d) is outside the map" % [id, x, y])
            if seen.has(key):
                errors.append("deposit %s: same tile as %s" % [id, seen[key]])
            seen[key] = id
            if not resources.has(d.get("resource", "")):
                errors.append("deposit %s: unknown resource '%s'" % [id, d.get("resource", "")])
            if float(d.get("richness", 0.0)) <= 0.0:
                errors.append("deposit %s: richness must be > 0" % id)
            if int(d.get("amount", 0)) <= 0:
                errors.append("deposit %s: amount must be > 0" % id)
            if int(d.get("land_cost", -1)) < 0:
                errors.append("deposit %s: land_cost missing or negative" % id)

    var cfg: Dictionary = data["contracts"]
    if cfg.is_empty():
        errors.append("contracts.json failed to load")
    else:
        for res_id in cfg["quantities"]:
            var q: Array = cfg["quantities"][res_id]
            if not resources.has(res_id) or q.size() != 2 or int(q[0]) < 1 or int(q[1]) < int(q[0]):
                errors.append("contracts: bad quantity range for '%s'" % res_id)
        for cid in cfg["clients"]:
            var wants: Dictionary = cfg["clients"][cid].get("wants", {})
            if wants.is_empty():
                errors.append("client %s wants nothing" % cid)
            for res_id in wants:
                if not cfg["quantities"].has(res_id):
                    errors.append("client %s: no quantity range for '%s'" % [cid, res_id])
        var tut: Dictionary = cfg.get("tutorial", {})
        if not tut.is_empty():
            if not cfg["clients"].has(tut.get("client", "")) or not cfg["quantities"].has(tut.get("resource", "")):
                errors.append("tutorial contract refers to an unknown client or resource")

    var ev: Dictionary = data["events"]
    if ev.is_empty():
        errors.append("events.json failed to load")
    else:
        var lead: Array = ev["announce_days"]
        if int(ev["max_concurrent"]) < 1 or float(ev["chance_per_day"]) < 0.0 or float(ev["chance_per_day"]) > 1.0:
            errors.append("events: max_concurrent must be >= 1 and chance_per_day between 0 and 1")
        if lead.size() != 2 or int(lead[0]) < 1 or int(lead[1]) < int(lead[0]):
            errors.append("events: announce_days must be [min, max] with min >= 1")
        if float(ev["anticipation"]) < 0.0 or float(ev["anticipation"]) > 1.0:
            errors.append("events: anticipation must be between 0 and 1")
        for eid in ev["events"]:
            var e: Dictionary = ev["events"][eid]
            if e.get("effects", {}).is_empty():
                errors.append("event %s has no effects" % eid)
            for res_id in e.get("effects", {}):
                if not resources.has(res_id):
                    errors.append("event %s: unknown resource '%s'" % [eid, res_id])
                elif float(e["effects"][res_id]) <= 0.0 or is_equal_approx(float(e["effects"][res_id]), 1.0):
                    errors.append("event %s: the effect on %s must be above 0 and not 1" % [eid, res_id])
            var dur: Array = e.get("duration", [])
            if dur.size() != 2 or int(dur[0]) < 1 or int(dur[1]) < int(dur[0]):
                errors.append("event %s: duration must be [min, max] with min >= 1" % eid)
            if float(e.get("weight", 0.0)) <= 0.0:
                errors.append("event %s: weight must be > 0" % eid)

    var start: Dictionary = data["balance"].get("start_inventory", {})
    for res_id in start:
        if not resources.has(res_id):
            errors.append("balance start_inventory: unknown resource '%s'" % res_id)
    return errors
