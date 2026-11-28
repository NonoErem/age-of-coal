extends RefCounted
## Standing orders: sell or buy the same amount of something every day, for a number of days.
## The player can start one at any time (no waiting for an offer). They trade at market prices:
## the usual spread, fee and price impact apply, so they cannot beat the market, only save the effort.
## A day when nothing can be traded (no stock, no room, no cash, price outside the limit) is lost.
## Orders run once a day, after production and before prices recover.


static func settings(state) -> Dictionary:
    return state.data["contracts"]["standing"]


## limit_cents: for a sell, the lowest average price per unit you accept; for a buy, the highest. 0 means no limit.
static func create(state, resource: String, side: String, qty: int, days: int, limit_cents: int = 0) -> Dictionary:
    var cfg: Dictionary = settings(state)
    if not state.data["resources"].has(resource):
        return {"ok": false, "reason": "unknown_resource"}
    if side != "sell" and side != "buy":
        return {"ok": false, "reason": "invalid_side"}
    if qty < 1 or qty > int(cfg["max_qty_per_day"]):
        return {"ok": false, "reason": "invalid_quantity"}
    if days < 1 or days > int(cfg["max_days"]):
        return {"ok": false, "reason": "invalid_days"}
    if limit_cents < 0:
        return {"ok": false, "reason": "invalid_limit"}
    if state.standing_orders.size() >= int(cfg["max_orders"]):
        return {"ok": false, "reason": "too_many_orders"}
    var o: Dictionary = {
        "id": state.order_next_id, "resource": resource, "side": side, "qty": qty,
        "days_total": days, "days_left": days, "limit_cents": limit_cents,
        "units_done": 0, "cents": 0, "skipped": 0, "started_day": state.day,
        "last_result": "", "notified": "",
    }
    state.order_next_id += 1
    state.standing_orders.append(o)
    return {"ok": true, "id": int(o["id"])}


static func cancel(state, id: int) -> Dictionary:
    for o in state.standing_orders:
        if int(o["id"]) == id:
            state.standing_orders.erase(o)
            return {"ok": true, "units_done": int(o["units_done"]), "cents": int(o["cents"])}
    return {"ok": false, "reason": "unknown_order"}


## One day for every order. Fills state.order_news with what the player should hear about.
static func run_day(state) -> void:
    state.order_news = []
    var running: Array = []
    for o in state.standing_orders:
        var result: String = _execute(state, o)
        o["last_result"] = result
        if result != str(o["notified"]):
            # Only speak up when something changes, so a long dry spell is one line, not thirty.
            if not (result == "ok" and str(o["notified"]) == ""):
                state.order_news.append({"kind": "recovered" if result == "ok" else "problem", "id": o["id"], "resource": o["resource"], "side": o["side"], "result": result})
            o["notified"] = result
        o["days_left"] = int(o["days_left"]) - 1
        if int(o["days_left"]) <= 0:
            state.order_news.append({"kind": "finished", "id": o["id"], "resource": o["resource"], "side": o["side"],
                "units": o["units_done"], "cents": o["cents"], "days": o["days_total"]})
        else:
            running.append(o)
    state.standing_orders = running


static func _execute(state, o: Dictionary) -> String:
    var res: String = str(o["resource"])
    var want: int = int(o["qty"])
    var is_sell: bool = o["side"] == "sell"
    var n: int = want
    var result: String = "ok"
    if is_sell:
        n = mini(want, state.stock(res))
        if n < want:
            result = "partial_stock" if n > 0 else "no_stock"
    else:
        n = mini(want, state.room_for(res))
        if n < want:
            result = "partial_room" if n > 0 else "no_room"
        var afford: int = _affordable(state, res, n)
        if afford < n:
            n = afford
            result = "partial_money" if n > 0 else "no_money"
    var room: int = state.market.trade_room(res)
    if room >= 0 and n > room:
        n = room
        result = "partial_limit" if n > 0 else "market_limit"
    if n > 0 and int(o["limit_cents"]) > 0:
        var total: int = state.market.quote_sell(res, n) if is_sell else state.market.quote_buy(res, n)
        var avg: float = float(total) / float(n)
        if (is_sell and avg < float(o["limit_cents"])) or (not is_sell and avg > float(o["limit_cents"])):
            n = 0
            result = "price"
    if n <= 0:
        o["skipped"] = int(o["skipped"]) + 1
        return result
    var r: Dictionary = state.sell(res, n) if is_sell else state.buy(res, n)
    if not r["ok"]:
        o["skipped"] = int(o["skipped"]) + 1
        return "failed"
    o["units_done"] = int(o["units_done"]) + n
    o["cents"] = int(o["cents"]) + int(r["revenue"] if is_sell else r["cost"])
    return result


## The most units (up to n) the player can pay for right now. Cost only goes up with quantity, so a binary search works.
static func _affordable(state, res: String, n: int) -> int:
    var lo: int = 0
    var hi: int = n
    while lo < hi:
        var mid: int = (lo + hi + 1) / 2
        if state.market.quote_buy(res, mid) <= state.money_cents:
            lo = mid
        else:
            hi = mid - 1
    return lo
