extends RefCounted

const Crisis = preload("res://sim/crisis.gd")
## Contract board, delivery and failure. No reputation yet.
##
## Rules:
## - The better an offer pays, the shorter it stays on the board: someone else would snap it up.
##   (+30% lasts a few days, +5% a couple of weeks.)
## - No offers for goods a market event is distorting (see market_events.gd).
## - Offers pay 115-140% of the market reference price (tighter deadline and bigger quantity pay more).
## - The reference price ignores the player's own trading pressure, so it cannot be pumped.
## - Offers are only made for things the player could plausibly deliver (stock + production + buying).
## - Each delivery is paid straight away, per unit, at the contract price.
## - If the deadline passes, the undelivered part costs a penalty (40% of its value).
## - Contracts use their own random stream, so they never disturb market prices.

const MarketEvents = preload("res://sim/market_events.gd")


static func setup(state) -> void:
    var cfg: Dictionary = state.data["contracts"]
    var tut: Dictionary = cfg.get("tutorial", {})
    if tut.is_empty():
        return
    state.board.append(_make_offer(state, str(tut["client"]), str(tut["resource"]), int(tut["quantity"]),
        int(tut["deadline_days"]), float(tut["premium"]), int(tut.get("valid_days", 15))))


## How many days an offer stays on the board. The more it pays over the market, the shorter.
static func offer_lifetime(cfg: Dictionary, premium: float) -> int:
    var p_range: Array = cfg["premium"]
    var life: Dictionary = cfg["offer_lifetime"]
    var t: float = clampf((premium - float(p_range[0])) / (float(p_range[1]) - float(p_range[0])), 0.0, 1.0)
    var days: float = float(life["min_days"]) + (float(life["max_days"]) - float(life["min_days"])) * pow(1.0 - t, float(life["curve"]))
    return maxi(1, int(round(days)))


## lifetime: how many days it is on the board, today included.
static func _make_offer(state, client: String, res: String, qty: int, deadline: int, premium: float, lifetime: int) -> Dictionary:
    var offer: Dictionary = {
        "id": state.contract_next_id, "client": client, "resource": res, "quantity": qty,
        "unit_price": int(round(state.market.reference_price(res) * premium)),
        "deadline_days": deadline, "offered_day": state.day, "expires_day": state.day + lifetime - 1,
        "premium": premium,
    }
    state.contract_next_id += 1
    return offer


## Daily housekeeping, called after the day number has advanced.
static func daily_update(state) -> void:
    var cfg: Dictionary = state.data["contracts"]
    state.news = []
    var still_active: Array = []
    for c in state.active_contracts:
        if int(c["due_day"]) < state.day:
            var undelivered: int = int(c["quantity"]) - int(c["delivered"])
            var penalty: int = int(round(float(cfg["penalty_fraction"]) * float(undelivered) * float(c["unit_price"])))
            state.money_cents -= penalty
            state.contract_stats["failed"] = int(state.contract_stats["failed"]) + 1
            state.contract_stats["penalties_cents"] = int(state.contract_stats["penalties_cents"]) + penalty
            state.news.append({"kind": "failed", "client": c["client"], "resource": c["resource"], "missing": undelivered, "penalty": penalty})
        else:
            still_active.append(c)
    state.active_contracts = still_active

    var kept: Array = []
    for o in state.board:
        if int(o["expires_day"]) < state.day:
            state.news.append({"kind": "expired", "client": o["client"], "resource": o["resource"]})
        else:
            kept.append(o)
    state.board = kept

    if state.board.size() < int(cfg["board_size"]) and state.contract_rng.randf() < float(cfg["offer_chance_per_day"]) * Crisis.contract_mult(state):
        var offer: Dictionary = generate_offer(state)
        if not offer.is_empty():
            state.news.append({"kind": "offer", "client": offer["client"], "resource": offer["resource"], "quantity": offer["quantity"],
                "over_pct": int(round((float(offer["premium"]) - 1.0) * 100.0)), "days": int(offer["expires_day"]) - state.day + 1})


## Tries a few times to make a fair offer and puts it on the board. Returns {} if none was possible.
static func generate_offer(state) -> Dictionary:
    var cfg: Dictionary = state.data["contracts"]
    var rng: RandomNumberGenerator = state.contract_rng
    var clients: Dictionary = cfg["clients"]
    var client_weights: Dictionary = {}
    for id in clients:
        client_weights[id] = 1.0
    var d_range: Array = cfg["deadline_days"]
    var p_range: Array = cfg["premium"]
    var distorted: Dictionary = MarketEvents.affected_resources(state)
    for _attempt in 6:
        var client: String = _pick_weighted(rng, client_weights)
        var res: String = _pick_weighted(rng, clients[client]["wants"])
        if distorted.has(res):
            continue
        var q_range: Array = cfg["quantities"][res]
        var qmin: int = int(q_range[0])
        var qmax: int = int(q_range[1])
        var qty: int = rng.randi_range(qmin, qmax)
        var deadline: int = rng.randi_range(int(d_range[0]), int(d_range[1]))
        # Fairness: never ask for more than the player could plausibly deliver in time.
        qty = mini(qty, max_deliverable(state, res, deadline))
        if qty < qmin:
            continue
        var tight: float = 1.0 - float(deadline - int(d_range[0])) / float(maxi(1, int(d_range[1]) - int(d_range[0])))
        var size: float = float(qty - qmin) / float(maxi(1, qmax - qmin))
        var premium: float = float(p_range[0]) + (float(p_range[1]) - float(p_range[0])) * (0.5 * tight + 0.5 * size)
        premium = clampf(premium + rng.randf_range(-0.02, 0.02), float(p_range[0]), float(p_range[1]))
        var offer: Dictionary = _make_offer(state, client, res, qty, deadline, premium, offer_lifetime(cfg, premium))
        state.board.append(offer)
        return offer
    return {}


## Optimistic estimate: stock, plus what current buildings could make, plus what money could buy.
static func max_deliverable(state, res: String, days: int) -> int:
    var have: float = float(state.stock(res)) + production_rate(state, res) * float(days)
    var bal: Dictionary = state.data["balance"]
    var unit_buy: float = state.market.reference_price(res) * (1.0 + float(bal["spread"])) * (1.0 + float(bal["fee"])) * 1.5
    var buyable: float = minf(floor(float(maxi(state.money_cents, 0)) / unit_buy), float(state.room_for(res)))
    return int(have + buyable)


static func production_rate(state, res: String) -> float:
    var rate: float = 0.0
    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        if not def["outputs"].has(res) or b["status"] == "depleted" or b["status"] == "stopped":
            continue
        var per_day: float = float(def["outputs"][res])
        if def["kind"] == "extractor":
            per_day *= float(state.data["map"]["deposits"][b["deposit_id"]]["richness"])
        else:
            per_day *= float(def.get("batches_per_day", 1))
        rate += per_day
    return rate


static func accept(state, offer_id: int) -> Dictionary:
    var idx: int = -1
    for i in state.board.size():
        if int(state.board[i]["id"]) == offer_id:
            idx = i
    if idx < 0:
        return {"ok": false, "reason": "unknown_offer"}
    if state.active_contracts.size() >= int(state.data["contracts"]["max_active"]):
        return {"ok": false, "reason": "too_many_active"}
    var o: Dictionary = state.board[idx]
    state.board.remove_at(idx)
    state.active_contracts.append({
        "id": int(o["id"]), "client": o["client"], "resource": o["resource"], "quantity": int(o["quantity"]),
        "unit_price": int(o["unit_price"]), "delivered": 0,
        "accepted_day": state.day, "due_day": state.day + int(o["deadline_days"]),
    })
    return {"ok": true, "id": int(o["id"])}


static func deliver(state, contract_id: int, qty: int) -> Dictionary:
    var idx: int = -1
    for i in state.active_contracts.size():
        if int(state.active_contracts[i]["id"]) == contract_id:
            idx = i
    if idx < 0:
        return {"ok": false, "reason": "unknown_contract"}
    var c: Dictionary = state.active_contracts[idx]
    var remaining: int = int(c["quantity"]) - int(c["delivered"])
    var res: String = str(c["resource"])
    if qty <= 0:
        return {"ok": false, "reason": "invalid_quantity"}
    if qty > remaining:
        return {"ok": false, "reason": "exceeds_contract"}
    if state.stock(res) < qty:
        return {"ok": false, "reason": "insufficient_stock"}
    var paid: int = qty * int(c["unit_price"])
    state.inventory[res] = state.stock(res) - qty
    state.money_cents += paid
    c["delivered"] = int(c["delivered"]) + qty
    state.contract_stats["earned_cents"] = int(state.contract_stats["earned_cents"]) + paid
    var completed: bool = int(c["delivered"]) >= int(c["quantity"])
    if completed:
        state.active_contracts.remove_at(idx)
        state.contract_stats["completed"] = int(state.contract_stats["completed"]) + 1
    return {"ok": true, "paid": paid, "completed": completed}


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
