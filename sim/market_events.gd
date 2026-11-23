extends RefCounted
## Market events: strikes, booms, gluts. Each one is announced a few days ahead, then shifts
## prices for a while. Events on the same resource multiply.
##
## - While an event is only announced, prices already move part of the way (anticipation),
##   because markets price in news. Otherwise buying ahead would be free money.
## - Events that crash prices (glut, dumping, recession) are likelier the bigger you are in that market.
## - No contract offers are made for goods an event is distorting, and existing offers for them are
##   withdrawn at the announcement. Otherwise a fixed-price offer could be filled with goods bought cheaply
##   after the event ends.
## - Events use their own random stream.


## Called once a day, after the day number has advanced.
static func daily_update(state) -> void:
    var cfg: Dictionary = state.data["events"]
    var me: Dictionary = state.market_events
    state.event_news = []

    var waiting: Array = []
    for e in me["upcoming"]:
        if int(e["start_day"]) <= state.day:
            me["active"].append(e)
            state.event_news.append({"kind": "started", "type": e["type"], "uid": e["uid"]})
        else:
            waiting.append(e)
    me["upcoming"] = waiting

    var running: Array = []
    for e in me["active"]:
        if int(e["end_day"]) < state.day:
            me["past"].append(e)
            me["last_end"][e["type"]] = int(e["end_day"])
            state.event_news.append({"kind": "ended", "type": e["type"], "uid": e["uid"]})
        else:
            running.append(e)
    me["active"] = running
    while me["past"].size() > 8:
        me["past"].pop_front()

    if me["upcoming"].size() + me["active"].size() < int(cfg["max_concurrent"]) and state.event_rng.randf() < float(cfg["chance_per_day"]):
        announce_new(state)
    apply_to_market(state)


## Picks and announces a new event. Returns it, or {} if nothing is eligible.
static func announce_new(state) -> Dictionary:
    var type: String = choose_type(state)
    if type == "":
        return {}
    return announce(state, type)


static func announce(state, type: String) -> Dictionary:
    var cfg: Dictionary = state.data["events"]
    var me: Dictionary = state.market_events
    var def: Dictionary = cfg["events"][type]
    var lead_range: Array = cfg["announce_days"]
    var lead: int = state.event_rng.randi_range(int(lead_range[0]), int(lead_range[1]))
    var dur: int = state.event_rng.randi_range(int(def["duration"][0]), int(def["duration"][1]))
    var effects: Dictionary = {}
    for res in def["effects"]:
        effects[res] = float(def["effects"][res])
    var e: Dictionary = {
        "uid": int(me["next_uid"]), "type": type, "announced_day": state.day,
        "start_day": state.day + lead, "end_day": state.day + lead + dur - 1, "effects": effects,
    }
    me["next_uid"] = int(me["next_uid"]) + 1
    me["upcoming"].append(e)
    state.event_news.append({"kind": "announced", "type": type, "uid": e["uid"]})
    # Clients wait for prices to settle: pull offers for the affected goods.
    var kept: Array = []
    for o in state.board:
        if effects.has(o["resource"]):
            state.event_news.append({"kind": "withdrawn", "client": o["client"], "resource": o["resource"], "type": type})
        else:
            kept.append(o)
    state.board = kept
    return e


## Which kind of event comes next. Events that crash prices favour the most exposed player.
static func choose_type(state) -> String:
    var cfg: Dictionary = state.data["events"]
    var me: Dictionary = state.market_events
    var weights: Dictionary = {}
    for id in cfg["events"]:
        var def: Dictionary = cfg["events"][id]
        if int(def.get("min_day", 1)) > state.day:
            continue
        if _is_busy(me, id):
            continue
        if int(me["last_end"].get(id, -100000)) + int(def.get("cooldown", 0)) > state.day:
            continue
        var w: float = float(def["weight"])
        if def.get("targets_exposed", false):
            w *= 1.0 + float(cfg["exposure_boost"]) * exposure(state, def)
        weights[id] = w
    if weights.is_empty():
        return ""
    return _pick_weighted(state.event_rng, weights)


## 0 to 1: how big the player is in the most exposed market this event pushes down.
static func exposure(state, def: Dictionary) -> float:
    var full: float = float(state.data["balance"]["market_impact"]["full_share"])
    var worst: float = 0.0
    for res in def["effects"]:
        if float(def["effects"][res]) < 1.0:
            worst = maxf(worst, clampf(state.market.share(res) / full, 0.0, 1.0))
    return worst


static func _is_busy(me: Dictionary, type: String) -> bool:
    for e in me["upcoming"]:
        if e["type"] == type:
            return true
    for e in me["active"]:
        if e["type"] == type:
            return true
    return false


## Sets every resource's price multiplier from the events that are running or announced.
static func apply_to_market(state) -> void:
    var me: Dictionary = state.market_events
    var anticipation: float = float(state.data["events"]["anticipation"])
    for id in state.data["resources"]:
        var mult: float = 1.0
        for e in me["active"]:
            if e["effects"].has(id):
                mult *= float(e["effects"][id])
        for e in me["upcoming"]:
            if e["effects"].has(id):
                var span: float = float(maxi(1, int(e["start_day"]) - int(e["announced_day"])))
                var progress: float = clampf(float(state.day - int(e["announced_day"])) / span, 0.0, 1.0)
                mult *= 1.0 + (float(e["effects"][id]) - 1.0) * anticipation * progress
        state.market.set_shock(id, mult)


## Resources that an announced or running event is distorting right now.
static func affected_resources(state) -> Dictionary:
    var out: Dictionary = {}
    var me: Dictionary = state.market_events
    for list in [me["upcoming"], me["active"]]:
        for e in list:
            for res in e["effects"]:
                out[res] = true
    return out


## Events (announced or running) that move this resource, with their status. For tooltips and markers.
static func touching(state, resource_id: String) -> Array:
    var out: Array = []
    var me: Dictionary = state.market_events
    for e in me["active"]:
        if e["effects"].has(resource_id):
            out.append({"event": e, "status": "active"})
    for e in me["upcoming"]:
        if e["effects"].has(resource_id):
            out.append({"event": e, "status": "upcoming"})
    return out


## "coal +40%, steel +10%"
static func effects_text(effects: Dictionary, resources: Dictionary) -> String:
    var parts: Array = []
    for res in effects:
        var pct: int = int(round((float(effects[res]) - 1.0) * 100.0))
        parts.append("%s %+d%%" % [str(resources[res]["name"]).to_lower(), pct])
    return ", ".join(parts)


static func _pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
    var total: float = 0.0
    for k in weights:
        total += float(weights[k])
    var roll: float = rng.randf() * total
    var last: String = ""
    for k in weights:
        last = str(k)
        roll -= float(weights[k])
        if roll <= 0.0:
            return last
    return last
