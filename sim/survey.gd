extends RefCounted
## Surveys: pay to find the ore that lies below the surface.
##
## The deposits you could always see on the map are at depth 0. Deeper ones (depth 1 and 2, in map.json)
## are hidden until a survey covers their tile. A survey of level L is done on a square area around a
## chosen tile (`radius` tiles each way) and reveals every hidden deposit of depth L or less inside it.
## So a level 2 survey also finds the shallower ones; a level 1 survey cannot see the deepest ore.
## The price is paid whatever is found. Once revealed, a deposit is used like any other (land price and all).
## Deeper ore is richer and bigger, and costs more to buy the land on.
## Surveys involve no luck: the map is fixed, so what lies where is the same every game.
## A survey that could not show you anything new (the whole area is already surveyed this deep) is refused.


static func settings(state) -> Dictionary:
    return state.data["map"]["survey"]


static func max_level(state) -> int:
    var m: int = 0
    for k in settings(state)["levels"]:
        m = maxi(m, int(k))
    return m


static func cost(state, level: int) -> int:
    return int(settings(state)["levels"][str(level)]["cost"])


static func level_name(state, level: int) -> String:
    return str(settings(state)["levels"][str(level)]["name"])


## The square that a survey centred here covers, cut to the map.
static func area(state, x: int, y: int) -> Rect2i:
    var r: int = int(settings(state)["radius"])
    var w: int = int(state.data["map"]["width"])
    var h: int = int(state.data["map"]["height"])
    var x0: int = maxi(0, x - r)
    var y0: int = maxi(0, y - r)
    var x1: int = mini(w - 1, x + r)
    var y1: int = mini(h - 1, y + r)
    return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## How deep this tile has been surveyed (0 = never).
static func level_at(state, x: int, y: int) -> int:
    return int(state.survey_tiles.get(state.tile_key(x, y), 0))


## Tiles in the area that this survey would cover for the first time.
static func new_tiles(state, x: int, y: int, level: int) -> int:
    var a: Rect2i = area(state, x, y)
    var n: int = 0
    for yy in range(a.position.y, a.end.y):
        for xx in range(a.position.x, a.end.x):
            if level_at(state, xx, yy) < level:
                n += 1
    return n


## Why a survey cannot be done here, or "". Money is not checked.
static func check(state, x: int, y: int, level: int) -> String:
    if level < 1 or not settings(state)["levels"].has(str(level)):
        return "unknown_level"
    if x < 0 or y < 0 or x >= int(state.data["map"]["width"]) or y >= int(state.data["map"]["height"]):
        return "out_of_bounds"
    if new_tiles(state, x, y, level) == 0:
        return "already_surveyed"
    return ""


static func run(state, x: int, y: int, level: int) -> Dictionary:
    var why: String = check(state, x, y, level)
    if why != "":
        return {"ok": false, "reason": why}
    var price: int = cost(state, level)
    if price > state.money_cents:
        return {"ok": false, "reason": "insufficient_funds", "cost": price}
    state.money_cents -= price
    var a: Rect2i = area(state, x, y)
    for yy in range(a.position.y, a.end.y):
        for xx in range(a.position.x, a.end.x):
            if level_at(state, xx, yy) < level:
                state.survey_tiles[state.tile_key(xx, yy)] = level
    var found: Array = []
    for id in state.data["map"]["deposits"]:
        if state.revealed.has(id):
            continue
        var d: Dictionary = state.data["map"]["deposits"][id]
        if int(d.get("depth", 0)) <= level and a.has_point(Vector2i(int(d["x"]), int(d["y"]))):
            state.revealed[id] = true
            found.append(id)
    state.survey_stats["surveys"] = int(state.survey_stats["surveys"]) + 1
    state.survey_stats["spent_cents"] = int(state.survey_stats["spent_cents"]) + price
    state.survey_stats["found"] = int(state.survey_stats["found"]) + found.size()
    return {"ok": true, "cost": price, "found": found, "area": a, "level": level}


## How many deposits are still hidden, and how many of them a survey of this level could find. For hints only.
static func hidden_count(state) -> int:
    var n: int = 0
    for id in state.data["map"]["deposits"]:
        if not state.revealed.has(id):
            n += 1
    return n


static func reason_text(reason: String) -> String:
    match reason:
        "unknown_level":
            return "no such survey."
        "out_of_bounds":
            return "that is off the map."
        "already_surveyed":
            return "that area has already been surveyed this deep."
        "insufficient_funds":
            return "not enough money."
    return reason


# ---------- saving ----------

static func to_dict(state) -> Dictionary:
    return {"tiles": state.survey_tiles.duplicate(), "revealed": state.revealed.keys(), "stats": state.survey_stats.duplicate()}


static func reset(state) -> void:
    state.survey_tiles = {}
    state.revealed = {}
    state.survey_stats = {"surveys": 0, "spent_cents": 0, "found": 0}
    for id in state.data["map"]["deposits"]:
        if int(state.data["map"]["deposits"][id].get("depth", 0)) == 0:
            state.revealed[id] = true


## False when the save does not fit the data.
static func load_dict(state, d: Dictionary) -> bool:
    for k in ["tiles", "revealed", "stats"]:
        if not d.has(k):
            return false
    reset(state)
    var top: int = max_level(state)
    for key in d["tiles"]:
        var parts: PackedStringArray = str(key).split(",")
        if parts.size() != 2:
            return false
        var lv: int = int(d["tiles"][key])
        if lv < 1 or lv > top:
            return false
        state.survey_tiles[str(key)] = lv
    for id in d["revealed"]:
        if not state.data["map"]["deposits"].has(id):
            return false
        state.revealed[str(id)] = true
    for k in d["stats"]:
        state.survey_stats[k] = int(d["stats"][k])
    return true
