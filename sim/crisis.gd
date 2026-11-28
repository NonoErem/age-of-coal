extends RefCounted
## The invasion. A fixed timeline in data/crisis.json:
##   peace -> warning (announce_day: objects fall from the sky, markets panic)
##         -> invasion (landing_day: the first creature appears on your map) -> siege -> collapse.
## There is no end: the pressure keeps rising until the company cannot hold on.
##
## Everything is measured in "crisis years" since the landing: years = (day - landing_day) / year_days.
##
## Economy (applied to the market every day, never saved: it follows from the calendar):
##   price   x (1 - drop) with drop = (warning_drop + drop_per_year * years) * crash_weight of the good.
##           A negative weight (munitions) means the price rises instead. Clamped to [min_mult, max_mult].
##   spread  + warning_spread once announced, + spread_per_year * years (capped)
##   fee     + fee_per_year * years (capped)
##   depth   x max(min_depth_mult, 1 - depth_loss_per_year * years)
##   shipping limit: from the landing, at most trade_cap_start units of each good a day, halving every
##           trade_cap_halving_days, never below trade_cap_min.
##   contract offers arrive less often: x max(min_contract_mult, 1 - contract_loss_per_year * years)
##   prices wander panic_volatility times more from the announcement on.
## Rivals pay a crisis burden on top of their overhead that weighs less on big companies (size_shield),
## and after the landing a bankrupt rival is no longer restarted by investors (you can still buy it).
##
## Aliens (their own random stream, saved, so reloading a game never changes what comes):
##   spawn on the map edge: on the landing day `first_wave`, then spawn_base + spawn_growth_per_day * days a day.
##   Each walks towards your nearest building (Chebyshev distance, `speed` tiles a day) and attacks it when next to it.
##   With no building on the map they wander and leave after roam_days.
##   Stronger kinds become more common as the years pass; all of them grow tougher.
## Defenses (buildings of kind "defense") fire first each day at the nearest creature within `range`, dealing
##   `damage`, and use `ammo` from your stock for every day they fire. No ammunition, no fire.
## Damage: a building that has lost health stops working (idle upkeep) until repaired. Repairs cost
##   repair_rate x build cost x the share of health lost. At 0 health it is destroyed. Defenses keep firing while
##   damaged: they are built to take hits.

const STATUS_DAMAGED := "damaged"
const STATUS_READY := "ready"
const STATUS_FIRING := "firing"
const STATUS_NO_AMMO := "no_ammo"
const STATUS_LIT := "lit"
const STATUS_NO_CREW := "no_crew"
const STATUS_NO_SUPPLIES := "no_supplies"


static func cfg(state) -> Dictionary:
    return state.data.get("crisis", {})


static func enabled(state) -> bool:
    return bool(cfg(state).get("enabled", false))


static func announce_day(state) -> int:
    return int(cfg(state)["announce_day"]) if enabled(state) else 1 << 30


static func landing_day(state) -> int:
    return int(cfg(state)["landing_day"]) if enabled(state) else 1 << 30


static func announced(state, day: int = -1) -> bool:
    return enabled(state) and (state.day if day < 0 else day) >= announce_day(state)


static func landed(state, day: int = -1) -> bool:
    return enabled(state) and (state.day if day < 0 else day) >= landing_day(state)


static func years(state, day: int = -1) -> float:
    if not enabled(state):
        return 0.0
    var d: int = state.day if day < 0 else day
    return maxf(0.0, float(d - landing_day(state)) / float(cfg(state).get("year_days", 365)))


static func phases(state) -> Array:
    return cfg(state).get("phases", []) if enabled(state) else []


## The phase a day falls in ({} when the crisis is off).
static func phase(state, day: int = -1) -> Dictionary:
    var d: int = state.day if day < 0 else day
    var out: Dictionary = {}
    for p in phases(state):
        if int(p["start"]) <= d:
            out = p
    return out


static func next_phase(state, day: int = -1) -> Dictionary:
    var d: int = state.day if day < 0 else day
    for p in phases(state):
        if int(p["start"]) > d:
            return p
    return {}


# ---------- calendar ----------

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


static func _month_days(y: int, m: int) -> int:
    if m == 2:
        return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
    return 30 if [4, 6, 9, 11].has(m) else 31


## [year, month, day] of a game day. Day 1 is start_date.
static func date_of(state, day: int) -> Array:
    var start: Array = cfg(state).get("start_date", [1925, 1, 1])
    var y: int = int(start[0])
    var m: int = int(start[1])
    var dd: int = int(start[2]) + day - 1
    while dd > _month_days(y, m):
        dd -= _month_days(y, m)
        m += 1
        if m > 12:
            m = 1
            y += 1
    return [y, m, dd]


static func date_text(state, day: int) -> String:
    var d: Array = date_of(state, day)
    return "%d %s %d" % [d[2], MONTHS[int(d[1]) - 1], d[0]]


# ---------- night ----------

## How dark the world has grown, 0 (day) to night.max. Starts at the announcement, dusk by the landing,
## full night after years_to_full crisis years. The interface multiplies itself by night_tint().
static func night(state, day: int = -1) -> float:
    if not announced(state, day):
        return 0.0
    var n: Dictionary = cfg(state).get("night", {})
    if n.is_empty():
        return 0.0
    var d: int = state.day if day < 0 else day
    var dusk: float = float(n["dusk_at_landing"])
    if not landed(state, day):
        var span: float = float(landing_day(state) - announce_day(state))
        return dusk * float(d - announce_day(state)) / maxf(1.0, span)
    var t: float = clampf(years(state, day) / float(n["years_to_full"]), 0.0, 1.0)
    return dusk + (float(n["max"]) - dusk) * t


static func night_tint(state, day: int = -1) -> Color:
    var n: Dictionary = cfg(state).get("night", {})
    if n.is_empty():
        return Color.WHITE
    return Color.WHITE.lerp(Color.html(str(n["color"])), night(state, day))


# ---------- economy ----------

static func price_mult(state, res: String, day: int = -1) -> float:
    if not announced(state, day):
        return 1.0
    var e: Dictionary = cfg(state)["economy"]
    var w: float = float(e["crash_weight"].get(res, 1.0))
    var drop: float = (float(e["warning_drop"]) + float(e["drop_per_year"]) * years(state, day)) * w
    return clampf(1.0 - drop, float(e["min_mult"]), float(e["max_mult"]))


static func extra_spread(state, day: int = -1) -> float:
    if not announced(state, day):
        return 0.0
    var a: Dictionary = cfg(state)["access"]
    return float(a["warning_spread"]) + minf(float(a["max_extra_spread"]), float(a["spread_per_year"]) * years(state, day))


static func extra_fee(state, day: int = -1) -> float:
    if not landed(state, day):
        return 0.0
    var a: Dictionary = cfg(state)["access"]
    return minf(float(a["max_extra_fee"]), float(a["fee_per_year"]) * years(state, day))


static func depth_mult(state, day: int = -1) -> float:
    if not landed(state, day):
        return 1.0
    var a: Dictionary = cfg(state)["access"]
    return maxf(float(a["min_depth_mult"]), 1.0 - float(a["depth_loss_per_year"]) * years(state, day))


## Units of each good the market lets you trade per day, -1 = no limit.
static func trade_cap(state, day: int = -1) -> int:
    if not landed(state, day):
        return -1
    var a: Dictionary = cfg(state)["access"]
    var d: int = (state.day if day < 0 else day) - landing_day(state)
    var cap: float = float(a["trade_cap_start"]) * pow(0.5, float(d) / float(a["trade_cap_halving_days"]))
    return maxi(int(a["trade_cap_min"]), int(round(cap)))


static func contract_mult(state, day: int = -1) -> float:
    if not landed(state, day):
        return 1.0
    var a: Dictionary = cfg(state)["access"]
    return maxf(float(a["min_contract_mult"]), 1.0 - float(a["contract_loss_per_year"]) * years(state, day))


## Sets every crisis value on the market for today. Called on a new game, every day and on loading.
static func apply_market(state) -> void:
    var m = state.market
    for res in state.data["resources"]:
        m.crisis_mult[res] = price_mult(state, res)
    m.extra_spread = extra_spread(state)
    m.extra_fee = extra_fee(state)
    m.crisis_depth = depth_mult(state)
    m.trade_cap = trade_cap(state)
    m.volatility_mult = float(cfg(state)["economy"]["panic_volatility"]) if announced(state) else 1.0


## Extra daily cost for a rival company, in cents. Big companies are shielded: the burden grows with
## size^(1 - size_shield), slower than their profit does.
static func rival_burden(state, overhead: int, scale: float) -> int:
    if not landed(state):
        return 0
    var r: Dictionary = cfg(state)["rivals"]
    var b: float = float(overhead) * float(r["burden_per_year"]) * years(state) * pow(scale, 1.0 - float(r["size_shield"]))
    return int(round(b))


static func rivals_revive(state) -> bool:
    return not landed(state) or bool(cfg(state)["rivals"]["revive_after_landing"])


# ---------- building health ----------

static func max_health(state, b: Dictionary) -> int:
    var def: Dictionary = state.data["buildings"][b["type"]]
    if def.has("health"):
        return int(def["health"])
    var table: Dictionary = cfg(state).get("damage", {}).get("health", {})
    return int(table.get(str(def["kind"]), 100))


static func is_damaged(state, b: Dictionary) -> bool:
    return int(b.get("health", max_health(state, b))) < max_health(state, b)


static func repair_cost(state, b: Dictionary) -> int:
    var mx: int = max_health(state, b)
    var lost: int = mx - int(b.get("health", mx))
    if lost <= 0:
        return 0
    var def: Dictionary = state.data["buildings"][b["type"]]
    var rate: float = float(cfg(state).get("damage", {}).get("repair_rate", 0.5))
    var full: float = float(def["build_cost"]) * rate * float(lost) / float(mx)
    var share: float = float(labour_cfg(state).get("repair_labour_share", 0.0))
    return int(ceil(full * (1.0 - share * labour_discount(state, int(b["x"]), int(b["y"])))))


static func repair(state, uid: int) -> Dictionary:
    var b: Dictionary = state.building_by_uid(uid)
    if b.is_empty():
        return {"ok": false, "reason": "unknown_building"}
    var cost: int = repair_cost(state, b)
    if cost <= 0:
        return {"ok": false, "reason": "not_damaged"}
    if cost > state.money_cents:
        return {"ok": false, "reason": "insufficient_funds", "cost": cost}
    state.money_cents -= cost
    b["health"] = max_health(state, b)
    var def: Dictionary = state.data["buildings"][b["type"]]
    if bool(b.get("stopped", false)):
        b["status"] = "stopped"
    else:
        b["status"] = STATUS_READY if holds_post(str(def["kind"])) else "built"
    state.crisis_stats["repairs_cents"] = int(state.crisis_stats["repairs_cents"]) + cost
    return {"ok": true, "cost": cost}


# ---------- the daily step ----------

static func _dist(ax: int, ay: int, bx: int, by: int) -> int:
    return maxi(absi(ax - bx), absi(ay - by))


static func _nearest_building(state, x: int, y: int) -> Dictionary:
    var best: Dictionary = {}
    var best_d: int = 1 << 30
    for b in state.buildings:
        var d: int = _dist(x, y, int(b["x"]), int(b["y"]))
        if d < best_d:
            best_d = d
            best = b
    return best


## Runs after the rival companies and before the market. Fills state.alien_news.
static func run_day(state) -> void:
    state.alien_news = []
    _lights_burn(state)          # night starts at the announcement, so searchlights may already burn
    if not landed(state):
        return
    _defenses_fire(state)
    _aliens_act(state)
    _spawn(state)


## Announcements that follow the calendar, called once the new day has started.
static func calendar_news(state) -> void:
    if not enabled(state):
        return
    if state.day == announce_day(state):
        state.alien_news.append({"kind": "announced", "landing_day": landing_day(state)})
    for p in phases(state):
        if int(p["start"]) == state.day and state.day > 1:
            state.alien_news.append({"kind": "phase", "phase": str(p["id"])})


static func _defenses_fire(state) -> void:
    var defs: Dictionary = state.data["buildings"]
    for b in state.buildings:
        var def: Dictionary = defs[b["type"]]
        if str(def["kind"]) != "defense" or bool(b.get("stopped", false)):
            continue
        if _crew_ratio(def, b) <= 0.0:
            b["status"] = STATUS_NO_CREW
            continue
        var rng_tiles: int = int(def["range"])
        var target: Dictionary = {}
        var best_d: int = 1 << 30
        for a in state.aliens:
            if int(a["hp"]) <= 0:
                continue
            var d: int = _dist(int(b["x"]), int(b["y"]), int(a["x"]), int(a["y"]))
            if d <= rng_tiles and d < best_d:
                best_d = d
                target = a
        if target.is_empty():
            b["status"] = STATUS_READY
            b["ammo_warned"] = false
            continue
        var ammo: Dictionary = def.get("ammo", {})
        var have: bool = true
        for res in ammo:
            if state.stock(res) < int(ammo[res]):
                have = false
        if not have:
            b["status"] = STATUS_NO_AMMO
            if not bool(b.get("ammo_warned", false)):
                b["ammo_warned"] = true
                state.alien_news.append({"kind": "no_ammo", "uid": b["uid"], "type": b["type"], "x": b["x"], "y": b["y"]})
            continue
        for res in ammo:
            state.inventory[res] = state.stock(res) - int(ammo[res])
            state.crisis_stats["ammo_used"] = int(state.crisis_stats["ammo_used"]) + int(ammo[res])
        b["status"] = STATUS_FIRING
        b["ammo_warned"] = false
        target["hp"] = int(target["hp"]) - maxi(1, int(round(float(def["damage"]) * _crew_ratio(def, b) * aim(state, int(b["x"]), int(b["y"])))))
        if int(target["hp"]) <= 0:
            state.crisis_stats["kills"] = int(state.crisis_stats["kills"]) + 1
            state.alien_news.append({"kind": "killed", "alien": target["type"], "x": target["x"], "y": target["y"], "by": b["type"]})
    state.aliens = state.aliens.filter(func(a: Dictionary) -> bool: return int(a["hp"]) > 0)


static func _aliens_act(state) -> void:
    var hits: Dictionary = {}   # uid -> damage taken today
    var leaving: Array = []
    for a in state.aliens:
        a["age"] = int(a["age"]) + 1
        var target: Dictionary = _nearest_building(state, int(a["x"]), int(a["y"]))
        var tx: int
        var ty: int
        if target.is_empty():
            tx = int(a["wander_x"])
            ty = int(a["wander_y"])
        else:
            tx = int(target["x"])
            ty = int(target["y"])
        for _step in int(a["speed"]):
            var d: int = _dist(int(a["x"]), int(a["y"]), tx, ty)
            if d <= (1 if not target.is_empty() else 0):
                break
            a["x"] = int(a["x"]) + signi(tx - int(a["x"]))
            a["y"] = int(a["y"]) + signi(ty - int(a["y"]))
        if target.is_empty():
            if int(a["age"]) >= int(cfg(state)["aliens"]["roam_days"]):
                leaving.append(a)
            continue
        if _dist(int(a["x"]), int(a["y"]), tx, ty) <= 1:
            var uid: int = int(target["uid"])
            var was_whole: bool = not is_damaged(state, target)
            target["health"] = int(target.get("health", max_health(state, target))) - int(a["attack"])
            hits[uid] = int(hits.get(uid, 0)) + int(a["attack"])
            state.crisis_stats["damage_taken"] = int(state.crisis_stats["damage_taken"]) + int(a["attack"])
            if not holds_post(str(state.data["buildings"][target["type"]]["kind"])):
                target["status"] = STATUS_DAMAGED
            if was_whole and int(target["health"]) > 0:
                state.alien_news.append({"kind": "attacked", "uid": uid, "type": target["type"], "x": target["x"], "y": target["y"], "alien": a["type"]})
            if int(target["health"]) <= 0:
                _destroy(state, target, str(a["type"]))
    for a in leaving:
        state.aliens.erase(a)
        state.alien_news.append({"kind": "left", "alien": a["type"]})


static func _destroy(state, b: Dictionary, by: String) -> void:
    var def: Dictionary = state.data["buildings"][b["type"]]
    state.buildings.erase(b)
    state.tile_owner.erase(state.tile_key(int(b["x"]), int(b["y"])))
    state.crisis_stats["destroyed"] = int(state.crisis_stats["destroyed"]) + 1
    var lost: Dictionary = {}
    if str(def["kind"]) == "granary":
        # Food that no longer fits in the remaining granaries rots in the ruins.
        for res in state.data["resources"]:
            if str(state.data["resources"][res].get("store", "")) == "granary":
                var over_food: int = state.stock(res) - state.room_total(res)
                if over_food > 0:
                    state.inventory[res] = state.stock(res) - over_food
                    lost[res] = over_food
    if str(def["kind"]) == "storage":
        # What no longer fits is lost with the warehouse, biggest stacks first.
        var over: int = state.stored_units() - state.capacity()
        while over > 0:
            var big: String = ""
            for res in state.inventory:
                if not state.in_yard(res):
                    continue
                if big == "" or int(state.inventory[res]) > int(state.inventory[big]):
                    big = res
            if big == "" or int(state.inventory[big]) <= 0:
                break
            var take: int = mini(over, maxi(1, int(state.inventory[big]) / 4))
            state.inventory[big] = int(state.inventory[big]) - take
            lost[big] = int(lost.get(big, 0)) + take
            over -= take
    state.alien_news.append({"kind": "destroyed", "uid": b["uid"], "type": b["type"], "x": b["x"], "y": b["y"], "alien": by, "lost": lost})


static func spawn_rate(state) -> float:
    var al: Dictionary = cfg(state)["aliens"]
    var days: int = state.day - landing_day(state)
    return minf(float(al["spawn_max_per_day"]), float(al["spawn_base"]) + float(al["spawn_growth_per_day"]) * float(days))


static func type_weights(state) -> Dictionary:
    var out: Dictionary = {}
    var y: float = years(state)
    for t in cfg(state)["aliens"]["types"]:
        out[str(t["id"])] = maxf(0.0, float(t["weight"]) + float(t["weight_per_year"]) * y)
    return out


static func alien_def(state, type_id: String) -> Dictionary:
    for t in cfg(state)["aliens"]["types"]:
        if str(t["id"]) == type_id:
            return t
    return {}


static func _spawn(state) -> void:
    var al: Dictionary = cfg(state)["aliens"]
    var rng: RandomNumberGenerator = state.alien_rng
    var n: int
    if state.day == landing_day(state):
        n = int(al["first_wave"])
    else:
        var rate: float = spawn_rate(state)
        n = int(floor(rate))
        if rng.randf() < rate - floor(rate):
            n += 1
    var w: Dictionary = type_weights(state)
    var total: float = 0.0
    for k in w:
        total += float(w[k])
    var y: float = years(state)
    var mw: int = int(state.data["map"]["width"])
    var mh: int = int(state.data["map"]["height"])
    var spawned: Array = []
    for _i in n:
        if state.aliens.size() >= int(al["max_alive"]):
            break
        var type_id: String = "crawler" if state.crisis_stats["spawned"] == 0 else ""
        if type_id == "":
            var roll: float = rng.randf() * total
            for k in w:
                roll -= float(w[k])
                if roll <= 0.0:
                    type_id = k
                    break
            if type_id == "":
                type_id = str(w.keys()[0])
        var t: Dictionary = alien_def(state, type_id)
        var edge: int = rng.randi_range(0, 3)
        var x: int
        var yy: int
        match edge:
            0:
                x = rng.randi_range(0, mw - 1); yy = 0
            1:
                x = rng.randi_range(0, mw - 1); yy = mh - 1
            2:
                x = 0; yy = rng.randi_range(0, mh - 1)
            _:
                x = mw - 1; yy = rng.randi_range(0, mh - 1)
        var hp: int = int(round(float(t["hp"]) * (1.0 + float(al["hp_growth_per_year"]) * y)))
        var a: Dictionary = {
            "id": state.alien_next_id, "type": type_id, "x": x, "y": yy, "hp": hp, "max_hp": hp,
            "attack": int(round(float(t["attack"]) * (1.0 + float(al["attack_growth_per_year"]) * y))),
            "speed": int(t["speed"]), "age": 0,
            "wander_x": rng.randi_range(mw / 4, mw * 3 / 4), "wander_y": rng.randi_range(mh / 4, mh * 3 / 4),
        }
        state.alien_next_id += 1
        state.aliens.append(a)
        spawned.append(a)
        state.crisis_stats["spawned"] = int(state.crisis_stats["spawned"]) + 1
    if not spawned.is_empty():
        state.alien_news.append({"kind": "sighting", "count": spawned.size(), "first": int(state.crisis_stats["spawned"]) == spawned.size(),
            "types": spawned.map(func(a: Dictionary) -> String: return str(a["type"])), "x": spawned[0]["x"], "y": spawned[0]["y"]})


static func alien_at(state, x: int, y: int) -> Dictionary:
    for a in state.aliens:
        if int(a["x"]) == x and int(a["y"]) == y:
            return a
    return {}


## Creatures within `r` tiles of a tile.
static func aliens_near(state, x: int, y: int, r: int) -> Array:
    return state.aliens.filter(func(a: Dictionary) -> bool: return _dist(x, y, int(a["x"]), int(a["y"])) <= r)


## Is this building covered by a defense (inside its range)?
static func covered_by(state, x: int, y: int) -> Array:
    var out: Array = []
    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        if str(def["kind"]) == "defense" and _dist(x, y, int(b["x"]), int(b["y"])) <= int(def["range"]):
            out.append(b)
    return out


# ---------- refuge: cheaper labour where people are safe ----------
## The world is in flight. Hired workers still come, but fewer every year, and almost none to open ground;
## those who come to defended ground work for less. Your own people (sim/people.gd) need no wage at all.
## The wage drop also makes repairs and new buildings cheaper, since a good part of their cost is labour.

## Kinds that stand at their post: they are never "built" or idle, and act in the crisis step.
static func holds_post(kind: String) -> bool:
    return kind == "defense" or kind == "shelter" or kind == "light"


static func labour_cfg(state) -> Dictionary:
    return cfg(state).get("labour", {})


## The best wage drop a fully safe site gets today (0 until the landing).
static func wage_drop(state) -> float:
    var l: Dictionary = labour_cfg(state)
    if l.is_empty() or not landed(state):
        return 0.0
    return minf(float(l["max_wage_drop"]), float(l["drop_at_landing"]) + float(l["drop_per_year"]) * years(state))


## A defense only protects while it can fire: not stopped, and with ammunition in stock.
static func defense_supplied(state, def: Dictionary, b: Dictionary) -> bool:
    if bool(b.get("stopped", false)):
        return false
    var ammo: Dictionary = def.get("ammo", {})
    for res in ammo:
        if state.stock(res) < int(ammo[res]):
            return false
    return true


## 0 to 1: how safe the tile feels, from the protection of the supplied defenses that reach it.
static func safety(state, x: int, y: int) -> float:
    var total: float = 0.0
    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        if str(def["kind"]) != "defense" or _dist(x, y, int(b["x"]), int(b["y"])) > int(def["range"]):
            continue
        if defense_supplied(state, def, b):
            total += float(def.get("protection", 0.5))
    return minf(1.0, total)


## Share by which hired wages are lowered at this tile (0 before the landing).
static func labour_discount(state, x: int, y: int) -> float:
    var l: Dictionary = labour_cfg(state)
    if l.is_empty() or not landed(state):
        return 0.0
    var exposed: float = float(l["exposed_share"])
    return minf(float(l["max_discount"]), wage_drop(state) * (exposed + (1.0 - exposed) * safety(state, x, y)))


## Share of the empty places in a crew that hired workers will fill at this tile.
## Everybody before the landing; then fewer every year, and far fewer where no supplied defense reaches.
static func hire_share(state, x: int, y: int) -> float:
    var l: Dictionary = labour_cfg(state)
    if l.is_empty() or not landed(state):
        return 1.0
    var t: float = years(state)
    var prot: float = maxf(float(l["hire_protected_min"]), float(l["hire_protected_at_landing"]) - float(l["hire_protected_per_year"]) * t)
    var expo: float = maxf(float(l["hire_exposed_min"]), float(l["hire_exposed_at_landing"]) - float(l["hire_exposed_per_year"]) * t)
    return expo + (prot - expo) * safety(state, x, y)


## Share taken off the cost of a new building at this tile.
static func build_discount(state, x: int, y: int) -> float:
    return float(labour_cfg(state).get("build_labour_share", 0.0)) * labour_discount(state, x, y)


## For the interface: how the tile stands.
static func labour_info(state, x: int, y: int) -> Dictionary:
    return {"safety": safety(state, x, y), "discount": labour_discount(state, x, y), "wage_drop": wage_drop(state), "hire": hire_share(state, x, y)}


# ---------- darkness and searchlights ----------
## Firing gets harder as night falls: defenses hit up to `max_penalty` less in full night,
## unless a working searchlight reaches them. Searchlights burn their supplies every night.

## 0 to 1: how dark it is, from nothing to full night.
static func darkness(state) -> float:
    var n: Dictionary = cfg(state).get("night", {})
    if n.is_empty() or float(n.get("max", 0.0)) <= 0.0:
        return 0.0
    return clampf(night(state) / float(n["max"]), 0.0, 1.0)


static func _crew_ratio(def: Dictionary, b: Dictionary) -> float:
    var crew: int = int(def.get("crew", 0))
    if crew <= 0:
        return 1.0
    return clampf(float(int(b.get("crew_yours", 0)) + int(b.get("crew_hired", crew))) / float(crew), 0.0, 1.0)


## 0 to 1: the best light a working searchlight throws on this tile (scaled by its crew).
static func light_at(state, x: int, y: int) -> float:
    var best: float = 0.0
    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        if str(def["kind"]) != "light" or str(b.get("status", "")) != STATUS_LIT:
            continue
        if _dist(x, y, int(b["x"]), int(b["y"])) <= int(def["range"]):
            best = maxf(best, _crew_ratio(def, b))
    return best


## What a defense's damage is multiplied by in the dark at this tile (1 by day or in full light).
static func aim(state, x: int, y: int) -> float:
    var pen: float = float(cfg(state).get("darkness", {}).get("max_penalty", 0.0)) * darkness(state)
    return 1.0 - pen * (1.0 - light_at(state, x, y))


## Searchlights burn their supplies whenever it is dark at all; out of supplies they go dark (said once).
static func _lights_burn(state) -> void:
    var dark: bool = darkness(state) > 0.0
    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        if str(def["kind"]) != "light":
            continue
        if bool(b.get("stopped", false)) or not dark or _crew_ratio(def, b) <= 0.0:
            b["status"] = STATUS_READY
            continue
        var need: Dictionary = def.get("supplies", {})
        var ok: bool = true
        for res in need:
            if state.stock(res) < int(need[res]):
                ok = false
        if ok:
            for res in need:
                state.inventory[res] = state.stock(res) - int(need[res])
            b["status"] = STATUS_LIT
        else:
            if str(b.get("status", "")) != STATUS_NO_SUPPLIES:
                state.alien_news.append({"kind": "no_supplies", "uid": b["uid"], "type": b["type"], "x": b["x"], "y": b["y"]})
            b["status"] = STATUS_NO_SUPPLIES


# ---------- saving ----------

static func reset(state) -> void:
    state.aliens = []
    state.alien_next_id = 1
    state.alien_news = []
    state.alien_rng.seed = state.seed_value + 15485863
    state.crisis_stats = {"spawned": 0, "kills": 0, "destroyed": 0, "damage_taken": 0, "repairs_cents": 0, "ammo_used": 0}


static func to_dict(state) -> Dictionary:
    return {"aliens": state.aliens.duplicate(true), "next_id": state.alien_next_id, "rng_state": str(state.alien_rng.state), "stats": state.crisis_stats.duplicate()}


static func load_dict(state, d: Dictionary) -> bool:
    for k in ["aliens", "next_id", "rng_state", "stats"]:
        if not d.has(k):
            return false
    reset(state)
    state.alien_rng.state = String(d["rng_state"]).to_int()
    state.alien_next_id = int(d["next_id"])
    for k in d["stats"]:
        state.crisis_stats[k] = int(d["stats"][k])
    for src in d["aliens"]:
        var a: Dictionary = {}
        for k in ["id", "x", "y", "hp", "max_hp", "attack", "speed", "age", "wander_x", "wander_y"]:
            if not src.has(k):
                return false
            a[k] = int(src[k])
        a["type"] = str(src.get("type", ""))
        if enabled(state) and alien_def(state, a["type"]).is_empty():
            return false
        state.aliens.append(a)
    return true


static func reason_text(reason: String) -> String:
    match reason:
        "not_damaged":
            return "it is not damaged."
        "insufficient_funds":
            return "not enough money."
        "unknown_building":
            return "no such building."
    return reason
