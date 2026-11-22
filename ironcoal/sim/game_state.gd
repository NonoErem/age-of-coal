extends RefCounted
## The whole game state: clock, wallet, inventory, market, map, buildings, seeded RNG.
## The UI sends commands (buy, sell, build, advance_day) and reads state. It never edits state directly.
## Money is in integer cents.

const Market = preload("res://sim/market.gd")
const Production = preload("res://sim/production.gd")
const Contracts = preload("res://sim/contracts.gd")
const SAVE_VERSION := 4
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
var tile_owner: Dictionary = {}  # "x,y" -> building uid
var next_uid: int = 1
var last_report: Dictionary = {}
var contract_rng := RandomNumberGenerator.new()  # separate stream: contracts never disturb market prices
var board: Array = []              # offers waiting to be accepted
var active_contracts: Array = []
var contract_next_id: int = 1
var contract_stats: Dictionary = {"completed": 0, "failed": 0, "earned_cents": 0, "penalties_cents": 0}
var news: Array = []               # what happened to contracts today (not saved)
var events: Array = []             # factories paused/resumed, mines depleted today (not saved)
var history: Dictionary = {}       # resource id -> end-of-day spot prices in cents, newest last
var _deposit_tiles: Dictionary = {}  # "x,y" -> deposit id


func _init(game_data: Dictionary, p_seed: int = 12345) -> void:
    data = game_data
    seed_value = p_seed
    rng.seed = p_seed
    contract_rng.seed = p_seed + 7919
    var balance: Dictionary = data["balance"]
    money_cents = int(balance["start_money_cents"])
    var start: Dictionary = balance.get("start_inventory", {})
    for id in start:
        inventory[id] = int(start[id])
    market = Market.new(data["resources"], balance)
    var map_deposits: Dictionary = data["map"]["deposits"]
    for id in map_deposits:
        var d: Dictionary = map_deposits[id]
        deposits[id] = {"remaining": int(d["amount"])}
        _deposit_tiles[tile_key(int(d["x"]), int(d["y"]))] = id
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


# ---------- market commands ----------

func buy(id: String, qty: int) -> Dictionary:
    if not data["resources"].has(id):
        return {"ok": false, "reason": "unknown_resource"}
    if qty <= 0:
        return {"ok": false, "reason": "invalid_quantity"}
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

func deposit_id_at(x: int, y: int) -> String:
    return str(_deposit_tiles.get(tile_key(x, y), ""))


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
    if def["kind"] == "storage":
        return "not_available_yet"
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
    }
    next_uid += 1
    buildings.append(b)
    tile_owner[tile_key(x, y)] = int(b["uid"])
    return {"ok": true, "cost": cost, "uid": int(b["uid"])}


# ---------- contract commands ----------

func accept_contract(offer_id: int) -> Dictionary:
    return Contracts.accept(self, offer_id)


func deliver_contract(contract_id: int, qty: int) -> Dictionary:
    return Contracts.deliver(self, contract_id, qty)


# ---------- clock ----------

func advance_day() -> void:
    # Order of a day: production -> upkeep -> market (prices recover, presence updates) -> new day -> contracts.
    # Still to come: events before the market; transport and a bankruptcy check.
    events = []
    last_report = Production.run_day(self)
    money_cents -= int(last_report["upkeep_cents"])
    market.advance_day(rng, _net_surplus(last_report))
    day += 1
    _record_history()
    Contracts.daily_update(self)
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
        "contracts": {
            "board": board.duplicate(true), "active": active_contracts.duplicate(true),
            "stats": contract_stats.duplicate(), "next_id": contract_next_id,
            "rng_state": str(contract_rng.state),
        },
    }


func load_dict(d: Dictionary) -> bool:
    if int(d.get("version", 0)) != SAVE_VERSION:
        return false
    for key in ["seed", "rng_state", "day", "money_cents", "inventory", "market", "buildings", "deposits", "next_uid", "contracts"]:
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
    buildings = []
    tile_owner = {}
    for src in d["buildings"]:
        var b: Dictionary = {
            "uid": int(src["uid"]), "type": str(src["type"]),
            "x": int(src["x"]), "y": int(src["y"]),
            "deposit_id": str(src["deposit_id"]), "status": str(src["status"]),
            "missing": src["missing"].duplicate(), "carry": {}, "batches": int(src.get("batches", 0)),
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
