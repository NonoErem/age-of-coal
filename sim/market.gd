extends RefCounted
## Market model, following Kenji's draft:
##   price = base * trend * shock * pressure
## Money is returned as integer cents. Floats are used only inside the model.
## Every buy and sell goes through _simulate(), so spread, fee and pressure live in one place.
##
## How hard YOU move the price depends on how important you are in that market:
##   share  = (your presence + units traded today) / market_volume
##   factor = min_factor at share 0, rising to 1.0 at full_share
##   each unit moves the price by  factor / depth
## Presence is what you produce in surplus plus what you trade, smoothed over about 10 days.
## A small company barely moves the price. A company holding a big slice of the market moves it hard.

var _resources: Dictionary
var _balance: Dictionary
var trend: Dictionary = {}
var pressure: Dictionary = {}
var shock_mult: Dictionary = {}    # product of all running market events, set by MarketEvents
var rival_mult: Dictionary = {}    # lasting price shift from weakened or bankrupt rival companies (see companies.gd)
var depth_mult: Dictionary = {}    # how much deeper the rivals make each market (1.0 = none)
var presence: Dictionary = {}      # smoothed units per day the company puts into this market
var volume_today: Dictionary = {}  # units bought or sold on the market since the last day change


func _init(resources: Dictionary, balance: Dictionary) -> void:
    _resources = resources
    _balance = balance
    for id in _resources:
        trend[id] = 1.0
        pressure[id] = 1.0
        shock_mult[id] = 1.0
        rival_mult[id] = 1.0
        depth_mult[id] = 1.0
        presence[id] = 0.0
        volume_today[id] = 0.0


func depth(id: String) -> float:
    var def: Dictionary = _resources[id]
    return float(def.get("depth", _balance["default_depth"])) * float(depth_mult[id])


## Units per day the whole market trades (everyone, not just you).
func market_volume(id: String) -> float:
    var def: Dictionary = _resources[id]
    return float(def.get("market_volume", _balance["market_impact"]["default_volume"]))


func base_price(id: String) -> float:
    var def: Dictionary = _resources[id]
    return float(def["base_price"])


## Current mid price in cents (before spread and fee).
func spot_price(id: String) -> float:
    return base_price(id) * float(trend[id]) * float(shock_mult[id]) * float(rival_mult[id]) * float(pressure[id])


## Price without the player's own trading pressure. Contracts are priced from this,
## so buying or selling heavily cannot inflate what a contract pays.
func reference_price(id: String) -> float:
    return base_price(id) * float(trend[id]) * float(shock_mult[id]) * float(rival_mult[id])


## Your slice of this market right now (0.01 = 1%).
func share(id: String) -> float:
    return (float(presence[id]) + float(volume_today[id])) / market_volume(id)


func impact_factor_for_share(sh: float) -> float:
    var mi: Dictionary = _balance["market_impact"]
    var lowest: float = float(mi["min_factor"])
    return clampf(lowest + (1.0 - lowest) * sh / float(mi["full_share"]), lowest, 1.0)


## 0.05 to 1.0: how strongly your trades move the price right now.
func impact_factor(id: String) -> float:
    return impact_factor_for_share(share(id))


## Pressure after a trade of this size, without committing it. Used for the "price impact" preview.
func pressure_after(id: String, qty: int, is_buy: bool) -> float:
    return float(_simulate(id, qty, is_buy)["pressure"])


func quote_buy(id: String, qty: int) -> int:
    return int(round(float(_simulate(id, qty, true)["total"])))


func quote_sell(id: String, qty: int) -> int:
    return int(round(float(_simulate(id, qty, false)["total"])))


## Commits the trade to market pressure and returns the total cost in cents.
func execute_buy(id: String, qty: int) -> int:
    return _commit(id, qty, true)


## Commits the trade to market pressure and returns the total revenue in cents.
func execute_sell(id: String, qty: int) -> int:
    return _commit(id, qty, false)


func _commit(id: String, qty: int, is_buy: bool) -> int:
    var r: Dictionary = _simulate(id, qty, is_buy)
    pressure[id] = r["pressure"]
    volume_today[id] = float(volume_today[id]) + float(qty)
    return int(round(float(r["total"])))


func _simulate(id: String, qty: int, is_buy: bool) -> Dictionary:
    var spread: float = float(_balance["spread"])
    var fee: float = float(_balance["fee"])
    var side: float
    if is_buy:
        side = (1.0 + spread) * (1.0 + fee)
    else:
        side = (1.0 - spread) * (1.0 - fee)
    var d: float = depth(id)
    var volume: float = market_volume(id)
    var unit_base: float = reference_price(id)
    var p: float = float(pressure[id])
    var p_min: float = float(_balance["pressure_min"])
    var p_max: float = float(_balance["pressure_max"])
    var already: float = float(presence[id]) + float(volume_today[id])
    var total: float = 0.0
    for i in qty:
        total += unit_base * p * side
        # The trade itself adds to your importance as it goes: a huge order is a big deal even for a small company.
        var step: float = impact_factor_for_share((already + float(i)) / volume) / d
        if is_buy:
            p *= 1.0 + step
        else:
            p *= 1.0 - step
        p = clampf(p, p_min, p_max)
    return {"total": total, "pressure": p}


## Price multiplier from market events (strikes, booms, gluts). Set every day by MarketEvents.
func set_shock(id: String, mult: float) -> void:
    shock_mult[id] = mult


## One daily step: pressure recovers, trend wanders, presence updates.
## net_produced is what the company made beyond its own factories' needs, per resource.
## Resources are visited in file order so the same seed always gives the same result.
func advance_day(rng: RandomNumberGenerator, net_produced: Dictionary = {}) -> void:
    var recovery: float = float(_balance["pressure_recovery"])
    var vol: float = float(_balance["trend_volatility"])
    var reversion: float = float(_balance["trend_reversion"])
    var t_min: float = float(_balance["trend_min"])
    var t_max: float = float(_balance["trend_max"])
    var smoothing: float = float(_balance["market_impact"]["presence_smoothing"])
    for id in _resources:
        pressure[id] = float(pressure[id]) + recovery * (1.0 - float(pressure[id]))
        var t: float = float(trend[id])
        t += rng.randfn(0.0, vol) + reversion * (1.0 - t)
        trend[id] = clampf(t, t_min, t_max)
        var today: float = float(volume_today[id]) + float(net_produced.get(id, 0))
        presence[id] = float(presence[id]) * (1.0 - smoothing) + smoothing * today
        volume_today[id] = 0.0


func to_dict() -> Dictionary:
    return {
        "trend": trend.duplicate(),
        "pressure": pressure.duplicate(),
        "shock_mult": shock_mult.duplicate(),
        "rival_mult": rival_mult.duplicate(),
        "presence": presence.duplicate(),
        "volume_today": volume_today.duplicate(),
    }


func load_dict(d: Dictionary) -> void:
    for id in _resources:
        trend[id] = float(d["trend"].get(id, 1.0))
        pressure[id] = float(d["pressure"].get(id, 1.0))
        shock_mult[id] = float(d["shock_mult"].get(id, 1.0))
        rival_mult[id] = float(d.get("rival_mult", {}).get(id, 1.0))
        presence[id] = float(d.get("presence", {}).get(id, 0.0))
        volume_today[id] = float(d.get("volume_today", {}).get(id, 0.0))
