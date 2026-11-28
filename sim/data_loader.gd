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


## A missing file is fine here (the game then runs without rival companies).
static func load_json_optional(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        return null
    return load_json(path)


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
    var companies: Variant = load_json_optional(dir + "/companies.json")
    var companies_out: Dictionary = {"enabled": false, "list": {}}
    if typeof(companies) == TYPE_DICTIONARY:
        companies_out = companies
        companies_out["list"] = _index_by_id(companies.get("companies", []))
    var crisis: Variant = load_json_optional(dir + "/crisis.json")
    return {
        "crisis": crisis if typeof(crisis) == TYPE_DICTIONARY else {"enabled": false},
        "companies": companies_out,
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
        var sv: Array = map.get("start_view", [0, 0])
        if sv.size() != 2 or int(sv[0]) < 0 or int(sv[1]) < 0 or int(sv[0]) >= w or int(sv[1]) >= h:
            errors.append("map: start_view must be a tile inside the map")
        if w < 1 or h < 1:
            errors.append("map: width and height must be at least 1")
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
            if int(d.get("depth", 0)) < 0 or int(d.get("depth", 0)) > 2:
                errors.append("deposit %s: depth must be 0 (visible), 1 or 2" % id)
        errors.append_array(_validate_survey(map))

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
        var life: Dictionary = cfg.get("offer_lifetime", {})
        if int(life.get("min_days", 0)) < 1 or int(life.get("max_days", 0)) < int(life.get("min_days", 0)) or float(life.get("curve", 0.0)) <= 0.0:
            errors.append("contracts: offer_lifetime needs min_days >= 1, max_days >= min_days and a curve above 0")
        var standing: Dictionary = cfg.get("standing", {})
        if int(standing.get("max_orders", 0)) < 1 or int(standing.get("max_days", 0)) < 1 or int(standing.get("max_qty_per_day", 0)) < 1:
            errors.append("contracts: standing needs max_orders, max_days and max_qty_per_day of at least 1")
        var tut: Dictionary = cfg.get("tutorial", {})
        if not tut.is_empty():
            if not cfg["clients"].has(tut.get("client", "")) or not cfg["quantities"].has(tut.get("resource", "")):
                errors.append("tutorial contract refers to an unknown client or resource")

    var bal: Dictionary = data["balance"]
    if int(bal.get("base_storage", 0)) < 1:
        errors.append("balance: base_storage must be at least 1")
    if float(bal.get("demolish_refund", -1.0)) < 0.0 or float(bal.get("demolish_refund", 2.0)) > 1.0:
        errors.append("balance: demolish_refund must be between 0 and 1")
    for id in buildings:
        if buildings[id].get("kind", "") == "storage" and int(buildings[id].get("capacity", 0)) < 1:
            errors.append("building %s: a storage building needs a capacity" % id)
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

    errors.append_array(_validate_companies(data))
    errors.append_array(_validate_crisis(data))
    for id in buildings:
        var bd: Dictionary = buildings[id]
        if bd.get("kind", "") == "defense":
            if int(bd.get("range", 0)) < 1 or int(bd.get("damage", 0)) < 1:
                errors.append("building %s: a defense needs a range and damage of at least 1" % id)
            for res_id in bd.get("ammo", {}):
                if not resources.has(res_id):
                    errors.append("building %s: unknown ammunition '%s'" % [id, res_id])
        if int(bd.get("crew", -1)) < 0:
            errors.append("building %s: crew must be 0 or more" % id)
        if bd.get("kind", "") == "shelter" and int(bd.get("housing", 0)) < 1:
            errors.append("building %s: a shelter needs housing of at least 1" % id)
        if bd.get("kind", "") == "granary" and int(bd.get("food_capacity", 0)) < 1:
            errors.append("building %s: a granary needs a food_capacity of at least 1" % id)
        if bd.get("kind", "") == "light":
            if int(bd.get("range", 0)) < 1 or int(bd.get("crew", 0)) < 1:
                errors.append("building %s: a searchlight needs a range and a crew of at least 1" % id)
            for res_id in bd.get("supplies", {}):
                if not resources.has(res_id):
                    errors.append("building %s: unknown supply '%s'" % [id, res_id])
    var pp: Dictionary = data["balance"].get("people", {})
    for key in ["wage_share", "ration", "spoil_per_day", "hunger_leave", "arrivals_share", "arrivals_min", "base_food_storage"]:
        if not pp.has(key):
            errors.append("balance people: '%s' is missing" % key)
    if pp.has("wage_share") and (float(pp["wage_share"]) < 0.0 or float(pp["wage_share"]) > 1.0):
        errors.append("balance people: wage_share must be between 0 and 1")
    if pp.has("ration") and float(pp["ration"]) <= 0.0:
        errors.append("balance people: ration must be above 0 (people eat)")
    if pp.has("spoil_per_day") and (float(pp["spoil_per_day"]) < 0.0 or float(pp["spoil_per_day"]) > 0.2):
        errors.append("balance people: spoil_per_day must be between 0 and 0.2")
    if pp.has("hunger_leave") and (float(pp["hunger_leave"]) <= 0.0 or float(pp["hunger_leave"]) > 1.0):
        errors.append("balance people: hunger_leave must be above 0 and at most 1")
    if not resources.has("food"):
        errors.append("resources: food is missing (your people eat it)")
    var start: Dictionary = data["balance"].get("start_inventory", {})
    for res_id in start:
        if not resources.has(res_id):
            errors.append("balance start_inventory: unknown resource '%s'" % res_id)
    return errors


static func _validate_companies(data: Dictionary) -> Array:
    var errors: Array = []
    var c: Dictionary = data.get("companies", {})
    if not bool(c.get("enabled", false)):
        return errors
    var resources: Dictionary = data["resources"]
    for key in ["friction", "price_sensitivity", "mult_min", "mult_max", "mult_smoothing", "weak_below", "healthy_above",
            "shrink", "grow", "comfort_cash", "debt_limit", "revival_days", "revival_strength", "dividend_rate",
            "buy_floor", "sell_back", "min_hold_days", "max_owned", "take_base", "take_peak", "max_input_mult", "idle_overhead", "rival_feel", "growth_reinvest", "growth_max_scale", "min_scale", "scale_decay", "restart_scale", "take_scale_cap"]:
        if not c.has(key):
            errors.append("companies: '%s' is missing" % key)
    if not errors.is_empty():
        return errors
    if float(c["mult_min"]) <= 0.0 or float(c["mult_min"]) > 1.0 or float(c["mult_max"]) < 1.0:
        errors.append("companies: mult_min must be in (0, 1] and mult_max at least 1")
    if float(c["weak_below"]) >= float(c["healthy_above"]):
        errors.append("companies: weak_below must be lower than healthy_above")
    if float(c["buy_floor"]) <= 0.0 or float(c["buy_floor"]) >= 1.0:
        errors.append("companies: buy_floor must be between 0 and 1")
    if float(c["sell_back"]) <= 0.0 or float(c["sell_back"]) >= 1.0:
        errors.append("companies: sell_back must be above 0 and below 1, or buying and selling would be free money")
    if float(c["revival_strength"]) <= 0.0 or float(c["revival_strength"]) > 1.0 or int(c["revival_days"]) < 1:
        errors.append("companies: revival_strength must be in (0, 1] and revival_days at least 1")
    if float(c["dividend_rate"]) < 0.0 or float(c["dividend_rate"]) > 1.0:
        errors.append("companies: dividend_rate must be between 0 and 1")
    if float(c["take_base"]) < 0.0 or float(c["take_peak"]) < float(c["take_base"]) or float(c["take_peak"]) > 1.0:
        errors.append("companies: take_base and take_peak must satisfy 0 <= base <= peak <= 1")
    if float(c["growth_max_scale"]) < 1.0 or float(c["min_scale"]) <= 0.0 or float(c["min_scale"]) > 1.0:
        errors.append("companies: growth_max_scale must be at least 1 and min_scale in (0, 1]")
    if float(c["restart_scale"]) < float(c["min_scale"]) or float(c["restart_scale"]) > float(c["growth_max_scale"]):
        errors.append("companies: restart_scale must lie between min_scale and growth_max_scale")
    if float(c["growth_reinvest"]) < 0.0 or float(c["growth_reinvest"]) > 1.0 or float(c["scale_decay"]) < 0.0 or float(c["scale_decay"]) >= 1.0:
        errors.append("companies: growth_reinvest must be 0..1 and scale_decay 0..1")
    if float(c["rival_feel"]) < 0.0 or float(c["rival_feel"]) > 1.0:
        errors.append("companies: rival_feel must be between 0 and 1")
    if float(c["idle_overhead"]) < 0.0 or float(c["idle_overhead"]) > 1.0:
        errors.append("companies: idle_overhead must be between 0 and 1")
    if float(c["friction"]) < 0.0 or float(c["friction"]) > 1.0:
        errors.append("companies: friction must be between 0 and 1")
    if c["list"].is_empty():
        errors.append("companies: the list is empty")
    for id in c["list"]:
        var def: Dictionary = c["list"][id]
        if def.get("outputs", {}).is_empty():
            errors.append("company %s makes nothing" % id)
        for key in ["outputs", "inputs"]:
            for res_id in def.get(key, {}):
                if not resources.has(res_id):
                    errors.append("company %s: unknown resource '%s' in %s" % [id, res_id, key])
                elif float(def[key][res_id]) <= 0.0:
                    errors.append("company %s: %s of %s must be above 0" % [id, key, res_id])
        for res_id in def.get("depth_bonus", {}):
            if not def.get("outputs", {}).has(res_id) or float(def["depth_bonus"][res_id]) < 0.0:
                errors.append("company %s: depth_bonus for '%s' must be for one of its outputs and not negative" % [id, res_id])
        for key in ["overhead", "start_cash", "base_value"]:
            if int(def.get(key, 0)) <= 0:
                errors.append("company %s: %s must be above 0" % [id, key])
    return errors


static func _validate_crisis(data: Dictionary) -> Array:
    var errors: Array = []
    var c: Dictionary = data.get("crisis", {})
    if not bool(c.get("enabled", false)):
        return errors
    for key in ["start_date", "announce_day", "landing_day", "year_days", "phases", "economy", "access", "rivals", "damage", "aliens"]:
        if not c.has(key):
            errors.append("crisis: '%s' is missing" % key)
    if not errors.is_empty():
        return errors
    if int(c["announce_day"]) < 2 or int(c["landing_day"]) <= int(c["announce_day"]):
        errors.append("crisis: announce_day must be at least 2 and landing_day after it")
    var last: int = 0
    for p in c["phases"]:
        if int(p.get("start", 0)) <= last:
            errors.append("crisis: phases must start on increasing days, the first on day 1")
        last = int(p.get("start", 0))
    if c["phases"].is_empty() or int(c["phases"][0]["start"]) != 1:
        errors.append("crisis: the first phase must start on day 1")
    var starts: Array = c["phases"].map(func(p: Dictionary) -> int: return int(p["start"]))
    if not starts.has(int(c["announce_day"])) or not starts.has(int(c["landing_day"])):
        errors.append("crisis: there must be a phase starting on announce_day and one on landing_day")
    for res_id in c["economy"].get("crash_weight", {}):
        if not data["resources"].has(res_id):
            errors.append("crisis: crash_weight for unknown resource '%s'" % res_id)
    if float(c["economy"]["min_mult"]) <= 0.0 or float(c["economy"]["max_mult"]) < 1.0:
        errors.append("crisis: economy min_mult must be above 0 and max_mult at least 1")
    if int(c["access"]["trade_cap_min"]) < 1 or float(c["access"]["trade_cap_halving_days"]) <= 0.0:
        errors.append("crisis: trade_cap_min must be at least 1 and trade_cap_halving_days above 0")
    if c.has("labour"):
        var lb: Dictionary = c["labour"]
        for key in ["drop_at_landing", "drop_per_year", "max_wage_drop", "exposed_share", "max_discount", "repair_labour_share", "build_labour_share", "hire_protected_at_landing", "hire_protected_per_year", "hire_protected_min", "hire_exposed_at_landing", "hire_exposed_per_year", "hire_exposed_min"]:
            if not lb.has(key):
                errors.append("crisis labour: '%s' is missing" % key)
        if errors.is_empty():
            for key in ["exposed_share", "repair_labour_share", "build_labour_share", "hire_protected_at_landing", "hire_protected_min", "hire_exposed_at_landing", "hire_exposed_min"]:
                if float(lb[key]) < 0.0 or float(lb[key]) > 1.0:
                    errors.append("crisis labour: %s must be between 0 and 1" % key)
            if float(lb["max_discount"]) > 0.95 or float(lb["max_wage_drop"]) > 0.95 or float(lb["max_discount"]) < 0.0:
                errors.append("crisis labour: discounts must stay at or below 0.95 (work is never free)")
    if c.has("night"):
        var nt: Dictionary = c["night"]
        if float(nt.get("max", 0.0)) < 0.0 or float(nt.get("max", 0.0)) > 0.8 or float(nt.get("dusk_at_landing", 0.0)) > float(nt.get("max", 0.0)) or float(nt.get("years_to_full", 0.0)) <= 0.0:
            errors.append("crisis: night needs 0 <= dusk_at_landing <= max <= 0.8 (beyond that the screen is unreadable) and years_to_full above 0")
    var types: Array = c["aliens"].get("types", [])
    if types.is_empty():
        errors.append("crisis: no alien types")
    var ids: Array = []
    for t in types:
        ids.append(str(t.get("id", "")))
        if int(t.get("hp", 0)) < 1 or int(t.get("attack", 0)) < 1 or int(t.get("speed", 0)) < 1:
            errors.append("crisis: alien %s needs hp, attack and speed of at least 1" % t.get("id", "?"))
    if not ids.has("crawler"):
        errors.append("crisis: the first creature is a crawler, so a 'crawler' type is needed")
    return errors


static func _validate_survey(map: Dictionary) -> Array:
    var errors: Array = []
    var sv: Variant = map.get("survey")
    var needs: bool = false
    for id in map["deposits"]:
        if int(map["deposits"][id].get("depth", 0)) > 0:
            needs = true
    if typeof(sv) != TYPE_DICTIONARY:
        if needs:
            errors.append("map: there are hidden deposits but no 'survey' section")
        return errors
    if int(sv.get("radius", 0)) < 1:
        errors.append("survey: radius must be at least 1")
    var levels: Dictionary = sv.get("levels", {})
    var prev_cost: int = 0
    for lv in [1, 2]:
        if not levels.has(str(lv)):
            errors.append("survey: level %d is missing" % lv)
            continue
        var c: int = int(levels[str(lv)].get("cost", 0))
        if c <= 0:
            errors.append("survey: level %d needs a cost above 0" % lv)
        if c <= prev_cost:
            errors.append("survey: level %d must cost more than level %d" % [lv, lv - 1])
        prev_cost = c
        if str(levels[str(lv)].get("name", "")) == "":
            errors.append("survey: level %d needs a name" % lv)
    return errors
