extends RefCounted
## Rival companies. They are not on the map: they exist in the market and in the Companies tab.
##
## Each rival is a specialist. At full strength it makes its outputs from its inputs every day, and its
## presence is already part of the normal market. What the player sees are DEVIATIONS from that normal:
##   - A weakened or bankrupt producer supplies less than usual: its products get dearer.
##   - It also buys fewer inputs than usual: the raw materials it consumes get cheaper.
##   - These shifts are a slowly moving price multiplier (market.rival_mult), so they act like a lasting
##     market pressure on the basic goods, and contract prices follow them.
##   - Market DEPTH: every healthy specialist makes its products' market deeper (more buyers and sellers
##     to absorb an order). When it fails the market gets thin, and your own orders move prices harder.
##
## A rival's day (at today's market prices, with spread and fee softened by `friction`):
##   variable margin = what its outputs sell for - what its inputs cost, scaled by its strength
##   It idles for the day when that margin is negative or an input costs too much, and then pays only
##   a share of its overhead (`idle_overhead`).
##   cash += margin - overhead
##   cash below zero      -> strength shrinks every day
##   cash above comfort   -> strength grows back while it is profitable
##   cash below the debt limit -> bankrupt: no output for `revival_days`, then investors restart it.
##
## Growth: a healthy, profitable rival reinvests part of what it keeps (`growth_reinvest`) and grows its SIZE
##   (`scale`, 1.0 at the start, at most `growth_max_scale`; growth slows as it nears the cap). Size multiplies its
##   output, inputs and overhead, so profit grows with it; it deepens its markets more, and its failure would be felt
##   more. Dividends paid to an owner are not reinvested, so an owned company grows more slowly. A company in debt
##   shrinks, and when it goes bankrupt it restarts no bigger than `restart_scale`.
##
## Buying a rival (max 3):
##   price = base_value * size * (buy_floor + (1 - buy_floor) * strength), the floor for a bankrupt one.
##   So a company that has done well for a long time costs much more than it did at the start.
##   You then get dividends: `dividend_rate` of its positive daily profit. It still trades as before, so
##   buying one does not change the market, and an owned rival does not snap up contract offers.
##   If it goes bankrupt while you own it, your stake is wiped out.
##   Selling gives back only sell_back * price, and not before min_hold_days: no quick flips.
##
## Rivals take contract offers too, but only for goods they make, and the better an offer pays, the likelier.
## Their random choices use their own stream, so they never disturb market prices or contract offers.


static func enabled(state) -> bool:
    return bool(state.data.get("companies", {}).get("enabled", false)) and not state.data["companies"]["list"].is_empty()


static func cfg(state) -> Dictionary:
    return state.data["companies"]


static func setup(state) -> void:
    state.rivals = {}
    if not enabled(state):
        return
    var list: Dictionary = cfg(state)["list"]
    for id in list:
        state.rivals[id] = {
            "cash": int(list[id]["start_cash"]), "strength": 1.0, "scale": 1.0, "status": "healthy", "owned": false,
            "bankrupt_days": 0, "profit": 0, "bought_day": 0, "paid": 0, "dividends": 0,
        }
    update_market(state, "instant")


# ---------- the daily step ----------

static func run_day(state) -> void:
    state.rival_news = []
    if not enabled(state):
        return
    var c: Dictionary = cfg(state)
    var list: Dictionary = c["list"]
    for id in list:
        var def: Dictionary = list[id]
        var r: Dictionary = state.rivals[id]
        if str(r["status"]) == "bankrupt":
            r["bankrupt_days"] = int(r["bankrupt_days"]) - 1
            r["profit"] = 0
            if int(r["bankrupt_days"]) <= 0:
                _restart(state, id, false)
                state.rival_news.append({"kind": "revived", "company": id})
            continue
        var scale: float = float(r["scale"])
        var margin: int = variable_margin(state, id)
        # An idle company keeps only a skeleton crew, like your own paused factories.
        var overhead_full: int = int(round(float(def["overhead"]) * scale))
        var overhead: int = overhead_full if margin > 0 else int(round(float(overhead_full) * float(c["idle_overhead"])))
        var profit: int = margin - overhead
        r["profit"] = profit
        r["cash"] = int(r["cash"]) + profit
        var kept: int = maxi(0, profit)
        if bool(r["owned"]) and profit > 0:
            var dividend: int = int(floor(float(profit) * float(c["dividend_rate"])))
            r["cash"] = int(r["cash"]) - dividend
            kept -= dividend
            r["dividends"] = int(r["dividends"]) + dividend
            state.money_cents += dividend
            state.rival_stats["dividends_cents"] = int(state.rival_stats["dividends_cents"]) + dividend
        var s: float = float(r["strength"])
        var cash_base: float = float(def["start_cash"]) * scale
        var comfort: float = cash_base * float(c["comfort_cash"])
        if int(r["cash"]) < 0:
            s -= float(c["shrink"])
            r["scale"] = maxf(float(c["min_scale"]), scale * (1.0 - float(c["scale_decay"])))
        elif float(r["cash"]) >= comfort and profit > 0:
            s += float(c["grow"])
            # Healthy and profitable: put part of what it keeps back into the business and grow.
            if str(r["status"]) == "healthy" and s >= 0.999:
                var spend: int = int(floor(float(kept) * float(c["growth_reinvest"])))
                var room: float = maxf(0.0, 1.0 - scale / float(c["growth_max_scale"]))
                r["cash"] = int(r["cash"]) - spend
                r["scale"] = minf(float(c["growth_max_scale"]), scale + float(spend) / float(def["base_value"]) * room)
        s = clampf(s, 0.0, 1.0)
        r["strength"] = s
        var limit: float = -float(c["debt_limit"]) * cash_base
        if float(r["cash"]) < limit or s <= 0.02:
            _go_bankrupt(state, id)
            continue
        var old_status: String = str(r["status"])
        if old_status == "healthy" and s < float(c["weak_below"]):
            r["status"] = "weakened"
            state.rival_news.append({"kind": "weakened", "company": id})
        elif old_status == "weakened" and s >= float(c["healthy_above"]):
            r["status"] = "healthy"
            state.rival_news.append({"kind": "recovered", "company": id})
    update_market(state, "smooth")


## What the rival makes minus what it spends on inputs today, in cents, at its current strength.
## Zero when it would lose money on the day's prices or an input has run away.
static func variable_margin(state, id: String) -> int:
    var c: Dictionary = cfg(state)
    var def: Dictionary = c["list"][id]
    var r: Dictionary = state.rivals[id]
    var bal: Dictionary = state.data["balance"]
    var fr: float = float(c["friction"])
    var sell_f: float = (1.0 - float(bal["spread"]) * fr) * (1.0 - float(bal["fee"]) * fr)
    var buy_f: float = (1.0 + float(bal["spread"]) * fr) * (1.0 + float(bal["fee"]) * fr)
    var revenue: float = 0.0
    var cost: float = 0.0
    for res in def["outputs"]:
        revenue += float(def["outputs"][res]) * rival_price(state, res) * sell_f
    for res in def["inputs"]:
        if rival_price(state, res) > float(c["max_input_mult"]) * state.market.base_price(res):
            return 0
        cost += float(def["inputs"][res]) * rival_price(state, res) * buy_f
    var m: float = (revenue - cost) * float(r["strength"]) * float(r["scale"])
    return maxi(0, int(round(m)))


## The price a rival trades at. It feels the weather (trends, events, your own pressure) in full, but only a
## part (`rival_feel`) of the shift caused by other rivals' trouble. Without that, one failure would topple
## its customers and suppliers in turn, and a single bust would become a lasting depression.
static func rival_price(state, res: String) -> float:
    var mult: float = float(state.market.rival_mult[res])
    var felt: float = 1.0 + float(cfg(state)["rival_feel"]) * (mult - 1.0)
    return state.market.spot_price(res) / mult * felt


static func _go_bankrupt(state, id: String) -> void:
    var r: Dictionary = state.rivals[id]
    var was_owned: bool = bool(r["owned"])
    r["status"] = "bankrupt"
    r["strength"] = 0.0
    r["cash"] = 0
    r["bankrupt_days"] = int(cfg(state)["revival_days"])
    r["owned"] = false
    r["scale"] = maxf(float(cfg(state)["min_scale"]), minf(float(r["scale"]), float(cfg(state)["restart_scale"])))
    if was_owned:
        state.rival_stats["wiped_out"] = int(state.rival_stats["wiped_out"]) + 1
    state.rival_news.append({"kind": "bankrupt", "company": id, "was_owned": was_owned})


static func _restart(state, id: String, owned: bool) -> void:
    var c: Dictionary = cfg(state)
    var r: Dictionary = state.rivals[id]
    r["status"] = "weakened"
    r["strength"] = float(c["revival_strength"])
    r["cash"] = int(round(float(c["list"][id]["start_cash"]) * float(r["scale"]) * float(c["comfort_cash"])))
    r["bankrupt_days"] = 0
    r["owned"] = owned


# ---------- effects on the market ----------

static func strength_of(state, id: String) -> float:
    return float(state.rivals[id]["strength"])


## Slowly moves each good's rival multiplier towards its target, and sets the depth multipliers.
## mode "instant": the multipliers jump to the target (a new game). "smooth": the daily step.
## "depth_only": leave the price multipliers alone (a loaded game brings its own).
static func update_market(state, mode: String) -> void:
    var m = state.market
    if not enabled(state):
        for id in state.data["resources"]:
            m.rival_mult[id] = 1.0
            m.depth_mult[id] = 1.0
        return
    var c: Dictionary = cfg(state)
    var supply_gap: Dictionary = {}
    var demand_gap: Dictionary = {}
    var depth_sum: Dictionary = {}
    for id in c["list"]:
        var def: Dictionary = c["list"][id]
        var s: float = strength_of(state, id)
        var scale: float = float(state.rivals[id]["scale"])
        for res in def["outputs"]:
            supply_gap[res] = float(supply_gap.get(res, 0.0)) + float(def["outputs"][res]) * scale * (1.0 - s)
            depth_sum[res] = float(depth_sum.get(res, 0.0)) + float(def.get("depth_bonus", {}).get(res, 0.0)) * s * scale
        for res in def["inputs"]:
            demand_gap[res] = float(demand_gap.get(res, 0.0)) + float(def["inputs"][res]) * scale * (1.0 - s)
    for res in state.data["resources"]:
        var net: float = (float(supply_gap.get(res, 0.0)) - float(demand_gap.get(res, 0.0))) / m.market_volume(res)
        var target: float = clampf(1.0 + float(c["price_sensitivity"]) * net, float(c["mult_min"]), float(c["mult_max"]))
        if mode == "instant":
            m.rival_mult[res] = target
        elif mode == "smooth":
            m.rival_mult[res] = float(m.rival_mult[res]) + float(c["mult_smoothing"]) * (target - float(m.rival_mult[res]))
        m.depth_mult[res] = 1.0 + float(depth_sum.get(res, 0.0))


# ---------- contract offers ----------

## Chance that this rival takes this offer today.
static func take_chance(state, id: String, offer: Dictionary) -> float:
    var c: Dictionary = cfg(state)
    var def: Dictionary = c["list"][id]
    var r: Dictionary = state.rivals[id]
    if bool(r["owned"]) or str(r["status"]) == "bankrupt" or not def["outputs"].has(str(offer["resource"])):
        return 0.0
    var p_range: Array = state.data["contracts"]["premium"]
    var t: float = clampf((float(offer["premium"]) - float(p_range[0])) / (float(p_range[1]) - float(p_range[0])), 0.0, 1.0)
    var p: float = float(c["take_base"]) + (float(c["take_peak"]) - float(c["take_base"])) * t
    return p * float(r["strength"]) * minf(float(c["take_scale_cap"]), sqrt(float(r["scale"])))


## Called after the contract board is updated for the new day. Offers that arrived today are safe until tomorrow.
static func take_offers(state) -> void:
    if not enabled(state) or not bool(cfg(state)["take_contracts"]):
        return
    var kept: Array = []
    for o in state.board:
        var taken_by: String = ""
        if int(o["offered_day"]) < state.day:
            for id in state.rivals:
                var p: float = take_chance(state, id, o)
                if p > 0.0 and state.rival_rng.randf() < p:
                    taken_by = id
                    break
        if taken_by == "":
            kept.append(o)
        else:
            state.rival_news.append({"kind": "took_offer", "company": taken_by, "client": o["client"], "resource": o["resource"], "quantity": o["quantity"]})
            state.rival_stats["offers_taken"] = int(state.rival_stats["offers_taken"]) + 1
    state.board = kept


# ---------- buying and selling ----------

static func owned_count(state) -> int:
    var n: int = 0
    for id in state.rivals:
        if bool(state.rivals[id]["owned"]):
            n += 1
    return n


## What it costs to buy this company today.
static func value(state, id: String) -> int:
    var c: Dictionary = cfg(state)
    var r: Dictionary = state.rivals[id]
    var floor_f: float = float(c["buy_floor"])
    var s: float = float(r["strength"])
    return int(round(float(c["list"][id]["base_value"]) * float(r["scale"]) * (floor_f + (1.0 - floor_f) * s)))


static func sell_price(state, id: String) -> int:
    return int(round(float(value(state, id)) * float(cfg(state)["sell_back"])))


## Days until you may sell (0 = now).
static func hold_days_left(state, id: String) -> int:
    var r: Dictionary = state.rivals[id]
    return maxi(0, int(r["bought_day"]) + int(cfg(state)["min_hold_days"]) - state.day)


static func buy(state, id: String) -> Dictionary:
    if not enabled(state) or not state.rivals.has(id):
        return {"ok": false, "reason": "unknown_company"}
    var r: Dictionary = state.rivals[id]
    if bool(r["owned"]):
        return {"ok": false, "reason": "already_owned"}
    if owned_count(state) >= int(cfg(state)["max_owned"]):
        return {"ok": false, "reason": "too_many_owned"}
    var price: int = value(state, id)
    if price > state.money_cents:
        return {"ok": false, "reason": "insufficient_funds", "cost": price}
    state.money_cents -= price
    var was_bankrupt: bool = str(r["status"]) == "bankrupt"
    if was_bankrupt:
        _restart(state, id, true)
    r["owned"] = true
    r["bought_day"] = state.day
    r["paid"] = price
    r["dividends"] = 0
    state.rival_stats["bought"] = int(state.rival_stats["bought"]) + 1
    return {"ok": true, "cost": price, "restarted": was_bankrupt}


static func sell(state, id: String) -> Dictionary:
    if not enabled(state) or not state.rivals.has(id):
        return {"ok": false, "reason": "unknown_company"}
    var r: Dictionary = state.rivals[id]
    if not bool(r["owned"]):
        return {"ok": false, "reason": "not_owned"}
    var left: int = hold_days_left(state, id)
    if left > 0:
        return {"ok": false, "reason": "hold_period", "days": left}
    var price: int = sell_price(state, id)
    state.money_cents += price
    r["owned"] = false
    return {"ok": true, "revenue": price}


# ---------- text for the interface ----------

## Rivals that are in trouble and make or use this good, for the Market tab. [{company, status}]
static func troubled_for(state, res: String) -> Array:
    var out: Array = []
    if not enabled(state):
        return out
    for id in cfg(state)["list"]:
        var def: Dictionary = cfg(state)["list"][id]
        if (def["outputs"].has(res) or def["inputs"].has(res)) and str(state.rivals[id]["status"]) != "healthy":
            out.append({"company": id, "status": str(state.rivals[id]["status"])})
    return out


## How the company's trouble shows up in prices, in words: "steel dearer, pig iron cheaper".
static func effect_text(state, id: String) -> String:
    var def: Dictionary = cfg(state)["list"][id]
    var res: Dictionary = state.data["resources"]
    var dearer: Array = []
    var cheaper: Array = []
    for r in def["outputs"]:
        dearer.append(str(res[r]["name"]).to_lower())
    for r in def["inputs"]:
        cheaper.append(str(res[r]["name"]).to_lower())
    var parts: Array = []
    if not dearer.is_empty():
        parts.append("%s scarcer and dearer" % ", ".join(dearer))
    if not cheaper.is_empty():
        parts.append("%s in less demand and cheaper" % ", ".join(cheaper))
    return "; ".join(parts)


static func status_text(status: String) -> String:
    match status:
        "healthy":
            return "Healthy"
        "weakened":
            return "Weakened"
        "bankrupt":
            return "Bankrupt"
    return status


static func reason_text(reason: String) -> String:
    match reason:
        "unknown_company":
            return "no such company."
        "already_owned":
            return "you already own it."
        "too_many_owned":
            return "you cannot hold more companies."
        "insufficient_funds":
            return "not enough money."
        "not_owned":
            return "you do not own it."
        "hold_period":
            return "you must keep it a little longer."
    return reason


# ---------- saving ----------

static func to_dict(state) -> Dictionary:
    return {"list": state.rivals.duplicate(true), "rng_state": str(state.rival_rng.state), "stats": state.rival_stats.duplicate()}


## Returns false when the save does not fit the data files.
static func load_dict(state, d: Dictionary) -> bool:
    for k in ["list", "rng_state", "stats"]:
        if not d.has(k):
            return false
    var saved_mult: Dictionary = state.market.rival_mult.duplicate()
    setup(state)
    state.market.rival_mult = saved_mult
    state.rival_news = []
    state.rival_rng.seed = state.seed_value + 1299709
    state.rival_rng.state = String(d["rng_state"]).to_int()
    state.rival_stats = {"dividends_cents": 0, "bought": 0, "wiped_out": 0, "offers_taken": 0}
    for k in d["stats"]:
        state.rival_stats[k] = int(d["stats"][k])
    if not enabled(state):
        return true
    for id in d["list"]:
        if not state.rivals.has(id):
            return false
        var src: Dictionary = d["list"][id]
        for k in ["cash", "strength", "scale", "status", "owned", "bankrupt_days", "profit", "bought_day", "paid", "dividends"]:
            if not src.has(k):
                return false
        var r: Dictionary = state.rivals[id]
        r["cash"] = int(src["cash"])
        r["strength"] = clampf(float(src["strength"]), 0.0, 1.0)
        r["scale"] = clampf(float(src["scale"]), float(cfg(state)["min_scale"]), float(cfg(state)["growth_max_scale"]))
        r["status"] = str(src["status"])
        r["owned"] = bool(src["owned"])
        for k in ["bankrupt_days", "profit", "bought_day", "paid", "dividends"]:
            r[k] = int(src[k])
        if not ["healthy", "weakened", "bankrupt"].has(r["status"]):
            return false
    update_market(state, "depth_only")
    return true
