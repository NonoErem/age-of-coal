extends RefCounted
## The whole game state: clock, wallet, inventory, market, map, buildings, seeded RNG.
## The UI sends commands (buy, sell, build, advance_day) and reads state. It never edits state directly.
## Money is in integer cents.

const Market = preload("res://sim/market.gd")
const Production = preload("res://sim/production.gd")
const Contracts = preload("res://sim/contracts.gd")
const MarketEvents = preload("res://sim/market_events.gd")
const StandingOrders = preload("res://sim/standing_orders.gd")
const Companies = preload("res://sim/companies.gd")
const Survey = preload("res://sim/survey.gd")
const Rules = preload("res://sim/rules.gd")
const SAVE_VERSION := 9
const HISTORY_DAYS := 120

signal day_advanced(day: int)

var data: Dictionary
var rng := RandomNumberGenerator.new()
var seed_value: int = 0
var day: int = 1
var money_cents: int = 0
var inventory: Dictionary = {}
var market
var buildings: Array = []        # each: {uid, type, x, y, deposit_id, status, missing, carry}
var deposits: Dictionary = {}    # deposit id -> {"remaining": int}
var revealed: Dictionary = {}    # deposit id -> true, for every deposit the player can see (see survey.gd)
var survey_tiles: Dictionary = {}  # "x,y" -> deepest survey level done on that tile
var survey_stats: Dictionary = {"surveys": 0, "spent_cents": 0, "found": 0}
var tile_owner: Dictionary = {}  # "x,y" -> building uid
var next_uid: int = 1
var last_report: Dictionary = {}
var contract_rng := RandomNumberGenerator.new()  # separate stream: contracts never disturb market prices
var board: Array = []              # offers waiting to be accepted
var active_contracts: Array = []
var contract_next_id: int = 1
var contract_stats: Dictionary = {"completed": 0, "failed": 0, "earned_cents": 0, "penalties_cents": 0}
var news: Array = []               # what happened to contracts today (not saved)
var event_rng := RandomNumberGenerator.new()  # separate stream for market events
var market_events: Dictionary = {"upcoming": [], "active": [], "past": [], "last_end": {}, "next_uid": 1}
var event_news: Array = []         # market events announced, started, ended today (not saved)
var standing_orders: Array = []    # automatic daily buying or selling the player has asked for
var order_next_id: int = 1
var rules: Array = []              # automation rules (see rules.gd)
var rule_next_id: int = 1
var rule_news: Array = []          # what the rules want the player to know today (not saved)
var order_news: Array = []         # what the standing orders want the player to know today (not saved)
var events: Array = []             # factories paused/resumed, mines depleted today (not saved)
var rivals: Dictionary = {}        # company id -> {cash, strength, status, owned, ...} (see companies.gd)
var rival_rng := RandomNumberGenerator.new()  # separate stream: rivals taking offers never disturb prices or offers
var rival_news: Array = []         # what the rival companies did today (not saved)
var rival_stats: Dictionary = {"dividends_cents": 0, "bought": 0, "wiped_out": 0, "offers_taken": 0}
var history: Dictionary = {}       # resource id -> end-of-day spot prices in cents, newest last
var _deposit_tiles: Dictionary = {}  # "x,y" -> deposit id


func _init(game_data: Dictionary, p_seed: int = 12345) -> void:
    data = game_data
    seed_value = p_seed
    rng.seed = p_seed
    contract_rng.seed = p_seed + 7919
    event_rng.seed = p_seed + 104729
    rival_rng.seed = p_seed + 1299709
    var balance: Dictionary = data["balance"]
    money_cents = int(balance["start_money_cents"])
    var start: Dictionary = balance.get("start_inventory", {})
    for id in start:
        inventory[id] = int(start[id])
    market = Market.new(data["resources"], balance)
    Companies.setup(self)
    var map_deposits: Dictionary = data["map"]["deposits"]
    for id in map_deposits:
        var d: Dictionary = map_deposits[id]
        deposits[id] = {"remaining": int(d["amount"])}
        _deposit_tiles[tile_key(int(d["x"]), int(d["y"]))] = id
    Survey.reset(self)
    Contracts.setup(self)
    _record_history()


func _record_history() -> void:
    for id in data["resources"]:
        var arr: Array = history.get(id, [])
        arr.append(market.spot_price(id))
        while arr.size() > HISTORY_DAYS:
            arr.pop_front()
        history[id] = arr


static func tile_key(x: int, y: int) -> String:
    return "%d,%d" % [x, y]


func stock(id: String) -> int:
    return int(inventory.get(id, 0))


# ---------- storage ----------

## Units you can keep: the open yard plus every warehouse.
func capacity() -> int:
    var total: int = int(data["balance"]["base_storage"])
    for b in buildings:
        var def: Dictionary = data["buildings"][b["type"]]
        if def["kind"] == "storage":
            total += int(def["capacity"])
    return total


func stored_units() -> int:
    var total: int = 0
    for id in inventory:
        total += int(inventory[id])
    return total


func free_space() -> int:
    return maxi(0, capacity() - stored_units())


# ---------- market commands ----------

func buy(id: String, qty: int) -> Dictionary:
    if not data["resources"].has(id):
        return {"ok": false, "reason": "unknown_resource"}
    if qty <= 0:
        return {"ok": false, "reason": "invalid_quantity"}
    if qty > free_space():
        return {"ok": false, "reason": "storage_full", "free": free_space()}
    var quote: int = market.quote_buy(id, qty)
    if quote > money_cents:
        return {"ok": false, "reason": "insufficient_funds", "cost": quote}
    var cost: int = market.execute_buy(id, qty)
    money_cents -= cost
    inventory[id] = stock(id) + qty
    return {"ok": true, "cost": cost}


func sell(id: String, qty: int) -> Dictionary:
    if not data["resources"].has(id):
        return {"ok": false, "reason": "unknown_resource"}
    if qty <= 0:
        return {"ok": false, "reason": "invalid_quantity"}
    if stock(id) < qty:
        return {"ok": false, "reason": "insufficient_stock"}
    var revenue: int = market.execute_sell(id, qty)
    money_cents += revenue
    inventory[id] = stock(id) - qty
    return {"ok": true, "revenue": revenue}


# ---------- map and buildings ----------

## The deposit on this tile, as far as the player knows. Hidden ones do not exist until surveyed.
func deposit_id_at(x: int, y: int) -> String:
    var id: String = str(_deposit_tiles.get(tile_key(x, y), ""))
    return id if revealed.has(id) else ""


func is_revealed(id: String) -> bool:
    return revealed.has(id)


## The deposits the player can see, in the order of the map file.
func revealed_deposit_ids() -> Array:
    var out: Array = []
    for id in data["map"]["deposits"]:
        if revealed.has(id):
            out.append(id)
    return out


func survey(x: int, y: int, level: int) -> Dictionary:
    return Survey.run(self, x, y, level)


func building_at(x: int, y: int) -> Dictionary:
    var uid: Variant = tile_owner.get(tile_key(x, y))
    if uid == null:
        return {}
    for b in buildings:
        if int(b["uid"]) == int(uid):
            return b
    return {}


func count_owned(building_id: String) -> int:
    var n: int = 0
    for b in buildings:
        if b["type"] == building_id:
            n += 1
    return n


## Price of the next building of this type, plus the land cost when built on a deposit.
func build_cost(building_id: String, deposit_id: String = "") -> int:
    var def: Dictionary = data["buildings"][building_id]
    var growth: float = float(data["balance"]["cost_growth_per_owned"])
    var base: float = float(def["build_cost"]) * (1.0 + growth * float(count_owned(building_id)))
    var land: int = 0
    if deposit_id != "":
        land = int(data["map"]["deposits"][deposit_id]["land_cost"])
    return int(round(base)) + land


## Why a building cannot go here, or "" if it can. Costs are not checked.
func check_placement(building_id: String, x: int, y: int) -> String:
    var defs: Dictionary = data["buildings"]
    if not defs.has(building_id):
        return "unknown_building"
    var def: Dictionary = defs[building_id]
    var map: Dictionary = data["map"]
    if x < 0 or y < 0 or x >= int(map["width"]) or y >= int(map["height"]):
        return "out_of_bounds"
    if tile_owner.has(tile_key(x, y)):
        return "tile_occupied"
    var dep_id: String = deposit_id_at(x, y)
    if def["kind"] == "extractor":
        if dep_id == "":
            return "no_deposit"
        if map["deposits"][dep_id]["resource"] != def["deposit"]:
            return "wrong_deposit"
    elif dep_id != "":
        return "deposit_tile_reserved"
    return ""


## Mines and quarries go on a deposit of their resource. Factories go on free ground.
## Nothing is ever destroyed: a factory without inputs is only paused.
func build(building_id: String, x: int, y: int) -> Dictionary:
    var why: String = check_placement(building_id, x, y)
    if why != "":
        return {"ok": false, "reason": why}
    var dep_id: String = deposit_id_at(x, y)
    var cost: int = build_cost(building_id, dep_id)
    if cost > money_cents:
        return {"ok": false, "reason": "insufficient_funds", "cost": cost}
    money_cents -= cost
    var b: Dictionary = {
        "uid": next_uid, "type": building_id, "x": x, "y": y,
        "deposit_id": dep_id, "status": Production.STATUS_BUILT, "missing": [], "carry": {}, "batches": 0,
        "stopped": false, "paid": cost,
    }
    next_uid += 1
    buildings.append(b)
    tile_owner[tile_key(x, y)] = int(b["uid"])
    return {"ok": true, "cost": cost, "uid": int(b["uid"])}


func building_by_uid(uid: int) -> Dictionary:
    for b in buildings:
        if int(b["uid"]) == uid:
            return b
    return {}


## What you would get back for demolishing this building.
func demolish_refund(uid: int) -> int:
    var b: Dictionary = building_by_uid(uid)
    if b.is_empty():
        return 0
    return int(round(float(b.get("paid", 0)) * float(data["balance"]["demolish_refund"])))


## Pull a building down. Gives back part of what was paid (land included).
## A warehouse cannot go while the stock would no longer fit without it.
func demolish(uid: int) -> Dictionary:
    var b: Dictionary = building_by_uid(uid)
    if b.is_empty():
        return {"ok": false, "reason": "unknown_building"}
    var def: Dictionary = data["buildings"][b["type"]]
    if def["kind"] == "storage" and stored_units() > capacity() - int(def["capacity"]):
        return {"ok": false, "reason": "storage_in_use"}
    var refund: int = demolish_refund(uid)
    money_cents += refund
    buildings.erase(b)
    tile_owner.erase(tile_key(int(b["x"]), int(b["y"])))
    return {"ok": true, "refund": refund, "type": b["type"], "x": b["x"], "y": b["y"]}


## Stop or restart a mine or factory by hand. A stopped building makes and uses nothing
## and keeps only a skeleton crew (idle upkeep). Storage cannot be stopped.
func set_building_stopped(uid: int, stopped: bool) -> Dictionary:
    var b: Dictionary = building_by_uid(uid)
    if b.is_empty():
        return {"ok": false, "reason": "unknown_building"}
    if data["buildings"][b["type"]]["kind"] == "storage":
        return {"ok": false, "reason": "cannot_stop"}
    b["stopped"] = stopped
    b["status"] = Production.STATUS_STOPPED if stopped else Production.STATUS_BUILT
    b["missing"] = []
    b["batches"] = 0
    return {"ok": true, "stopped": stopped}


# ---------- contract commands ----------

func accept_contract(offer_id: int) -> Dictionary:
    return Contracts.accept(self, offer_id)


func deliver_contract(contract_id: int, qty: int) -> Dictionary:
    return Contracts.deliver(self, contract_id, qty)


# ---------- standing orders ----------

func start_standing_order(resource: String, side: String, qty: int, days: int, limit_cents: int = 0) -> Dictionary:
    return StandingOrders.create(self, resource, side, qty, days, limit_cents)


func cancel_standing_order(id: int) -> Dictionary:
    return StandingOrders.cancel(self, id)


# ---------- automation rules ----------

func add_rule(resource: String, kind: String, level: int, limit_cents: int = 0, per_day: int = 0, min_cash_cents: int = 0) -> Dictionary:
    return Rules.create(self, resource, kind, level, limit_cents, per_day, min_cash_cents)


func delete_rule(id: int) -> Dictionary:
    return Rules.delete(self, id)


func pause_rule(id: int, paused: bool) -> Dictionary:
    return Rules.set_paused(self, id, paused)


# ---------- rival companies ----------

func buy_company(id: String) -> Dictionary:
    return Companies.buy(self, id)


func sell_company(id: String) -> Dictionary:
    return Companies.sell(self, id)


# ---------- clock ----------

func advance_day() -> void:
    # Order of a day: production -> upkeep -> standing orders -> rules -> rival companies -> market (prices recover, presence updates) -> new day -> market events -> price history -> contracts -> rivals take offers.
    # Still to come: events before the market; transport and a bankruptcy check.
    events = []
    last_report = Production.run_day(self)
    money_cents -= int(last_report["upkeep_cents"])
    StandingOrders.run_day(self)
    Rules.run_day(self)
    Companies.run_day(self)
    market.advance_day(rng, _net_surplus(last_report))
    day += 1
    MarketEvents.daily_update(self)
    _record_history()
    Contracts.daily_update(self)
    Companies.take_offers(self)
    day_advanced.emit(day)


## What the company made beyond its own factories' needs. This is what it brings to the market.
func _net_surplus(report: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var made: Dictionary = report.get("produced", {})
    var used: Dictionary = report.get("consumed", {})
    for id in made:
        var net: int = int(made[id]) - int(used.get(id, 0))
        if net > 0:
            out[id] = net
    return out


# ---------- saving ----------

func to_dict() -> Dictionary:
    return {
        "version": SAVE_VERSION,
        "seed": seed_value,
        "rng_state": str(rng.state),  # string: a 64-bit value would lose precision as a JSON number
        "day": day,
        "money_cents": money_cents,
        "inventory": inventory.duplicate(),
        "market": market.to_dict(),
        "buildings": buildings.duplicate(true),
        "deposits": deposits.duplicate(true),
        "next_uid": next_uid,
        "history": history.duplicate(true),
        "market_events": market_events.duplicate(true),
        "orders": {"list": standing_orders.duplicate(true), "next_id": order_next_id},
        "event_rng_state": str(event_rng.state),
        "rivals": Companies.to_dict(self),
        "survey": Survey.to_dict(self),
        "rules": Rules.to_dict(self),
        "contracts": {
            "board": board.duplicate(true), "active": active_contracts.duplicate(true),
            "stats": contract_stats.duplicate(), "next_id": contract_next_id,
            "rng_state": str(contract_rng.state),
        },
    }


func load_dict(d: Dictionary) -> bool:
    if int(d.get("version", 0)) != SAVE_VERSION:
        return false
    for key in ["seed", "rng_state", "day", "money_cents", "inventory", "market", "buildings", "deposits", "next_uid", "contracts", "market_events", "event_rng_state", "orders", "rivals", "survey", "rules"]:
        if not d.has(key):
            return false
    seed_value = int(d["seed"])
    rng.seed = seed_value
    rng.state = String(d["rng_state"]).to_int()
    day = int(d["day"])
    money_cents = int(d["money_cents"])
    inventory = {}
    for id in d["inventory"]:
        inventory[id] = int(d["inventory"][id])
    market.load_dict(d["market"])
    deposits = {}
    for id in d["deposits"]:
        deposits[id] = {"remaining": int(d["deposits"][id]["remaining"])}
    # A save made on a smaller map: deposits that were not there yet start full.
    for id in data["map"]["deposits"]:
        if not deposits.has(id):
            deposits[id] = {"remaining": int(data["map"]["deposits"][id]["amount"])}
    buildings = []
    tile_owner = {}
    for src in d["buildings"]:
        var b: Dictionary = {
            "uid": int(src["uid"]), "type": str(src["type"]),
            "x": int(src["x"]), "y": int(src["y"]),
            "deposit_id": str(src["deposit_id"]), "status": str(src["status"]),
            "missing": src["missing"].duplicate(), "carry": {}, "batches": int(src.get("batches", 0)),
            "stopped": bool(src.get("stopped", false)), "paid": int(src.get("paid", 0)),
        }
        for res in src["carry"]:
            b["carry"][res] = float(src["carry"][res])
        buildings.append(b)
        tile_owner[tile_key(b["x"], b["y"])] = b["uid"]
    next_uid = int(d["next_uid"])
    # A save must fit the data files it is loaded into.
    for b in buildings:
        if not data["buildings"].has(b["type"]):
            return false
        if b["deposit_id"] != "" and not data["map"]["deposits"].has(b["deposit_id"]):
            return false

    for id in inventory:
        if not data["resources"].has(id):
            return false
    last_report = {}
    news = []
    events = []
    history = {}
    for id in d.get("history", {}):
        var arr: Array = []
        for v in d["history"][id]:
            arr.append(float(v))
        history[id] = arr
    event_rng.seed = seed_value + 104729
    event_rng.state = String(d["event_rng_state"]).to_int()
    event_news = []
    market_events = {"upcoming": [], "active": [], "past": [], "last_end": {}, "next_uid": int(d["market_events"]["next_uid"])}
    for key in ["upcoming", "active", "past"]:
        for src in d["market_events"][key]:
            var e: Dictionary = {
                "uid": int(src["uid"]), "type": str(src["type"]), "announced_day": int(src["announced_day"]),
                "start_day": int(src["start_day"]), "end_day": int(src["end_day"]), "effects": {},
            }
            for res in src["effects"]:
                e["effects"][res] = float(src["effects"][res])
            if not data["events"]["events"].has(e["type"]):
                return false
            market_events[key].append(e)
    for t in d["market_events"]["last_end"]:
        market_events["last_end"][t] = int(d["market_events"]["last_end"][t])
    standing_orders = []
    order_news = []
    order_next_id = int(d["orders"]["next_id"])
    for src in d["orders"]["list"]:
        if not data["resources"].has(str(src["resource"])):
            return false
        var o: Dictionary = src.duplicate()
        for k in ["id", "qty", "days_total", "days_left", "limit_cents", "units_done", "cents", "skipped", "started_day"]:
            o[k] = int(src[k])
        standing_orders.append(o)
    if not Companies.load_dict(self, d["rivals"]):
        return false
    if not Survey.load_dict(self, d["survey"]):
        return false
    for b in buildings:
        if b["deposit_id"] != "":
            revealed[b["deposit_id"]] = true  # a mine always stands on a deposit you know
    if not Rules.load_dict(self, d["rules"]):
        return false
    var c: Dictionary = d["contracts"]
    contract_rng.seed = seed_value + 7919
    contract_rng.state = String(c["rng_state"]).to_int()
    contract_next_id = int(c["next_id"])
    board = []
    for o in c["board"]:
        board.append(_int_fields(o, ["id", "quantity", "unit_price", "deadline_days", "offered_day", "expires_day"]))
    active_contracts = []
    for a in c["active"]:
        active_contracts.append(_int_fields(a, ["id", "quantity", "unit_price", "delivered", "accepted_day", "due_day"]))
    contract_stats = {}
    for k in c["stats"]:
        contract_stats[k] = int(c["stats"][k])
    return true


func _int_fields(src: Dictionary, keys: Array) -> Dictionary:
    var out: Dictionary = src.duplicate()
    for k in keys:
        out[k] = int(src[k])
    return out
