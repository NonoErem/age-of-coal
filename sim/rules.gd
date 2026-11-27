extends RefCounted
## Automation rules: standing instructions that look at your stock every day and trade to keep it where you want it.
##
##   "keep"        Keep at least N units in stock. Each day, buy what is missing.
##   "sell_above"  Keep at most N units. Each day, sell what is over.
##
## Unlike a standing order (a fixed amount for a number of days) a rule reacts to what you hold, and runs until
## you delete it. Rules trade at the market like everything else: spread, fee and price impact all apply, so they save
## effort, not money. Options on a rule:
##   limit      a buy rule pays at most this average price per unit, a sell rule accepts at least this much (0 = any)
##   per_day    the most units it will trade in a day (default `max_per_day`)
##   min_cash   a buy rule never takes your cash below this amount
##   paused     switch it off without deleting it
## A rule that cannot do its job (price outside the limit, no room, no cash) says so once, in the log.
## Rules run after production and standing orders, before the rival companies, in the order you made them.
##
## Churn guard: a keep rule's level may not be above the sell_above level of the same good, or the two would buy
## and sell the same units every day and lose the spread each time. One rule of each kind per good.

const KINDS := ["keep", "sell_above"]


static func settings(state) -> Dictionary:
    return state.data["balance"]["rules"]


static func find(state, id: int) -> Dictionary:
    for r in state.rules:
        if int(r["id"]) == id:
            return r
    return {}


## The running rule that would clash with this one, or {}. Paused rules are off, so they never clash.
static func _conflict(state, resource: String, kind: String, level: int, ignore_id: int = -1) -> Dictionary:
    for r in state.rules:
        if int(r["id"]) == ignore_id or str(r["resource"]) != resource or bool(r["paused"]):
            continue
        if kind == "keep" and str(r["kind"]) == "sell_above" and level > int(r["level"]):
            return r
        if kind == "sell_above" and str(r["kind"]) == "keep" and level < int(r["level"]):
            return r
    return {}


## For the form's live preview: the rule a new one would clash with, or {}.
static func would_conflict(state, resource: String, kind: String, level: int) -> Dictionary:
    return _conflict(state, resource, kind, level)


static func create(state, resource: String, kind: String, level: int, limit_cents: int = 0, per_day: int = 0, min_cash_cents: int = 0) -> Dictionary:
    var cfg: Dictionary = settings(state)
    if not state.data["resources"].has(resource):
        return {"ok": false, "reason": "unknown_resource"}
    if not KINDS.has(kind):
        return {"ok": false, "reason": "invalid_kind"}
    if level < 0 or level > int(cfg["max_level"]):
        return {"ok": false, "reason": "invalid_level"}
    if limit_cents < 0 or min_cash_cents < 0:
        return {"ok": false, "reason": "invalid_limit"}
    if per_day < 0 or per_day > int(cfg["max_per_day"]):
        return {"ok": false, "reason": "invalid_quantity"}
    if kind == "keep" and level < 1:
        return {"ok": false, "reason": "invalid_level"}
    if state.rules.size() >= int(cfg["max_rules"]):
        return {"ok": false, "reason": "too_many_rules"}
    for r in state.rules:
        if str(r["resource"]) == resource and str(r["kind"]) == kind:
            return {"ok": false, "reason": "duplicate", "id": int(r["id"])}
    var clash: Dictionary = _conflict(state, resource, kind, level)
    if not clash.is_empty():
        return {"ok": false, "reason": "conflict", "id": int(clash["id"]), "level": int(clash["level"]), "kind": str(clash["kind"])}
    var rule: Dictionary = {
        "id": state.rule_next_id, "resource": resource, "kind": kind, "level": level,
        "limit_cents": limit_cents, "per_day": per_day, "min_cash_cents": min_cash_cents, "paused": false,
        "units_done": 0, "cents": 0, "skipped": 0, "created_day": state.day, "last_result": "", "notified": "",
    }
    state.rule_next_id += 1
    state.rules.append(rule)
    return {"ok": true, "id": int(rule["id"])}


static func delete(state, id: int) -> Dictionary:
    var r: Dictionary = find(state, id)
    if r.is_empty():
        return {"ok": false, "reason": "unknown_rule"}
    state.rules.erase(r)
    return {"ok": true, "units_done": int(r["units_done"]), "cents": int(r["cents"])}


## Pause or resume. Resuming is refused if it would now clash with another rule.
static func set_paused(state, id: int, paused: bool) -> Dictionary:
    var r: Dictionary = find(state, id)
    if r.is_empty():
        return {"ok": false, "reason": "unknown_rule"}
    if not paused:
        var clash: Dictionary = _conflict(state, str(r["resource"]), str(r["kind"]), int(r["level"]), id)
        if not clash.is_empty():
            return {"ok": false, "reason": "conflict", "id": int(clash["id"])}
    r["paused"] = paused
    return {"ok": true}


## One day for every rule. Fills state.rule_news with what the player should hear about.
static func run_day(state) -> void:
    state.rule_news = []
    for r in state.rules:
        var result: String = "paused" if bool(r["paused"]) else _execute(state, r)
        r["last_result"] = result
        var bad: bool = ["no_money", "partial_money", "no_room", "partial_room", "price"].has(result)
        var was_bad: bool = ["no_money", "partial_money", "no_room", "partial_room", "price"].has(str(r["notified"]))
        if bad and str(r["notified"]) != result:
            state.rule_news.append({"kind": "problem", "id": r["id"], "resource": r["resource"], "rule": r["kind"], "result": result})
            r["notified"] = result
        elif not bad and was_bad and result != "paused":
            state.rule_news.append({"kind": "recovered", "id": r["id"], "resource": r["resource"], "rule": r["kind"]})
            r["notified"] = ""
        elif not bad and not was_bad:
            r["notified"] = ""


static func _cap(state, r: Dictionary) -> int:
    return int(r["per_day"]) if int(r["per_day"]) > 0 else int(settings(state)["max_per_day"])


static func _execute(state, r: Dictionary) -> String:
    var res: String = str(r["resource"])
    var level: int = int(r["level"])
    var cap: int = _cap(state, r)
    var held: int = state.stock(res)
    var result: String = "ok"
    var n: int = 0
    if str(r["kind"]) == "keep":
        var need: int = level - held
        if need <= 0:
            return "idle"
        n = mini(need, cap)
        var room: int = state.free_space()
        if room < n:
            n = room
            result = "partial_room" if n > 0 else "no_room"
        if n > 0:
            var afford: int = _affordable(state, res, n, state.money_cents - int(r["min_cash_cents"]))
            if afford < n:
                n = afford
                result = "partial_money" if n > 0 else "no_money"
    else:
        var extra: int = held - level
        if extra <= 0:
            return "idle"
        n = mini(extra, cap)
    if n > 0 and int(r["limit_cents"]) > 0:
        var selling: bool = str(r["kind"]) == "sell_above"
        var total: int = state.market.quote_sell(res, n) if selling else state.market.quote_buy(res, n)
        var avg: float = float(total) / float(n)
        if (selling and avg < float(r["limit_cents"])) or (not selling and avg > float(r["limit_cents"])):
            n = 0
            result = "price"
    if n <= 0:
        r["skipped"] = int(r["skipped"]) + 1
        return result
    var done: Dictionary = state.sell(res, n) if str(r["kind"]) == "sell_above" else state.buy(res, n)
    if not done["ok"]:
        r["skipped"] = int(r["skipped"]) + 1
        return "failed"
    r["units_done"] = int(r["units_done"]) + n
    r["cents"] = int(r["cents"]) + int(done["revenue"] if str(r["kind"]) == "sell_above" else done["cost"])
    return result


## The most units (up to n) that can be bought with this much money. Cost only rises with quantity.
static func _affordable(state, res: String, n: int, budget: int) -> int:
    var lo: int = 0
    var hi: int = n
    while lo < hi:
        var mid: int = (lo + hi + 1) / 2
        if state.market.quote_buy(res, mid) <= budget:
            lo = mid
        else:
            hi = mid - 1
    return lo


static func result_text(result: String) -> String:
    match result:
        "partial_room":
            return "bought only part: storage is full"
        "no_room":
            return "bought nothing: storage is full"
        "partial_money":
            return "bought only part: not enough cash"
        "no_money":
            return "bought nothing: not enough cash"
        "price":
            return "did nothing: the price was outside your limit"
        "failed":
            return "could not trade"
    return ""


static func reason_text(reason: String) -> String:
    match reason:
        "unknown_resource", "invalid_kind", "unknown_rule":
            return "unknown rule or good."
        "invalid_level":
            return "that stock level is not allowed."
        "invalid_limit":
            return "limits cannot be negative."
        "invalid_quantity":
            return "that daily amount is not allowed."
        "too_many_rules":
            return "you have as many rules as are allowed."
        "duplicate":
            return "you already have that kind of rule for this good. Delete it first."
        "conflict":
            return "it would clash with another rule for this good (keeping more than you would sell)."
    return reason


# ---------- saving ----------

static func to_dict(state) -> Dictionary:
    return {"list": state.rules.duplicate(true), "next_id": state.rule_next_id}


## False when the save does not fit the data.
static func load_dict(state, d: Dictionary) -> bool:
    if not d.has("list") or not d.has("next_id"):
        return false
    state.rules = []
    state.rule_news = []
    state.rule_next_id = int(d["next_id"])
    for src in d["list"]:
        for k in ["id", "resource", "kind", "level", "limit_cents", "per_day", "min_cash_cents", "paused", "units_done", "cents", "skipped", "created_day", "last_result", "notified"]:
            if not src.has(k):
                return false
        if not state.data["resources"].has(str(src["resource"])) or not KINDS.has(str(src["kind"])):
            return false
        var r: Dictionary = {"id": int(src["id"]), "resource": str(src["resource"]), "kind": str(src["kind"]), "level": int(src["level"]),
            "limit_cents": int(src["limit_cents"]), "per_day": int(src["per_day"]), "min_cash_cents": int(src["min_cash_cents"]),
            "paused": bool(src["paused"]), "units_done": int(src["units_done"]), "cents": int(src["cents"]),
            "skipped": int(src["skipped"]), "created_day": int(src["created_day"]),
            "last_result": str(src["last_result"]), "notified": str(src["notified"])}
        state.rules.append(r)
    return true
