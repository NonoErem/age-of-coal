extends RefCounted
## People: every building needs a crew to work, and runs in proportion to the crew it has.
##
## Two kinds of workers fill a crew:
## - your people: refugees housed in your shelters and fed with food. They earn no wage. Nobody lives with you before the landing.
## - hired workers: they come from the towns and are paid a wage. Before the landing you can hire as many as you want;
##   after it fewer come every year, and almost none to sites your defenses do not protect (see Crisis.hire_share).
## Crews are filled from your people first (defenses and searchlights first, then in the order things were built), then hired.
##
## Upkeep = maintenance (the share of the listed upkeep that is not wages, never cheaper)
##        + wages of the hired workers actually there (lowered by the invasion's wage drop on safe ground, Crisis.labour_discount).
## Before the landing every crew is fully hired, so upkeep is exactly the listed upkeep.
##
## Food lives only in granaries and spoils slowly. Your people eat a ration a day; hungry people leave, a share at a time.
## New refugees come to shelters that stand on defended ground, while there is room and food.

const Crisis = preload("res://sim/crisis.gd")

const PRIORITY_KINDS := ["defense", "light"]


static func cfg(state) -> Dictionary:
    return state.data["balance"].get("people", {})


static func crew_of(def: Dictionary) -> int:
    return int(def.get("crew", 0))


## Share of the empty places in a crew that hired workers fill at this tile (1 before the landing).
static func hire_share(state, x: int, y: int) -> float:
    return Crisis.hire_share(state, x, y)


## Fills every crew for today. Called at the start of a day, and whenever buildings change, so the interface is right.
static func staff(state) -> void:
    var free: int = state.people
    var defs: Dictionary = state.data["buildings"]
    var order: Array = []
    for b in state.buildings:
        if PRIORITY_KINDS.has(str(defs[b["type"]]["kind"])):
            order.append(b)
    for b in state.buildings:
        if not PRIORITY_KINDS.has(str(defs[b["type"]]["kind"])):
            order.append(b)
    for b in order:
        var def: Dictionary = defs[b["type"]]
        var crew: int = crew_of(def)
        var yours: int = 0
        # Your people do not waste their days at a works you stopped or one waiting for repair.
        var working: bool = not bool(b.get("stopped", false)) and not (Crisis.is_damaged(state, b) and not Crisis.holds_post(str(def["kind"])))
        if working:
            yours = mini(crew, free)
            free -= yours
        var hired: int = int(round(float(crew - yours) * hire_share(state, int(b["x"]), int(b["y"]))))
        b["crew_yours"] = yours
        b["crew_hired"] = hired
        if str(def["kind"]) == "shelter":
            if bool(b.get("stopped", false)):
                b["status"] = "stopped"
            elif not Crisis.landed(state):
                b["status"] = "ready"
            else:
                b["status"] = "housing" if shelter_open(state, b) else "unsafe"


## 0 to 1: how much of its crew a building has today.
static func crew_ratio(state, b: Dictionary) -> float:
    var crew: int = crew_of(state.data["buildings"][b["type"]])
    if crew <= 0:
        return 1.0
    return clampf(float(int(b.get("crew_yours", 0)) + int(b.get("crew_hired", crew))) / float(crew), 0.0, 1.0)


## What a building's listed upkeep is multiplied by today: maintenance always, wages only for the hired workers there.
static func upkeep_mult(state, b: Dictionary) -> float:
    var def: Dictionary = state.data["buildings"][b["type"]]
    var w: float = float(cfg(state).get("wage_share", 0.8))
    var crew: int = crew_of(def)
    var hired_share: float = 1.0
    if crew > 0:
        hired_share = float(int(b.get("crew_hired", crew))) / float(crew)
    var wage_cut: float = Crisis.labour_discount(state, int(b["x"]), int(b["y"]))
    return (1.0 - w) + w * hired_share * (1.0 - wage_cut)


## Totals for the interface.
static func totals(state) -> Dictionary:
    var yours: int = 0
    var hired: int = 0
    var needed: int = 0
    for b in state.buildings:
        needed += crew_of(state.data["buildings"][b["type"]])
        yours += int(b.get("crew_yours", 0))
        hired += int(b.get("crew_hired", 0))
    return {"people": state.people, "housing": housing(state), "yours": yours, "hired": hired, "needed": needed, "idle": state.people - yours}


# ---------- housing and food ----------

## Places in shelters where refugees will stay: shelters you have not stopped, on ground a supplied defense protects.
static func housing(state) -> int:
    var total: int = 0
    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        if str(def["kind"]) == "shelter" and shelter_open(state, b):
            total += int(def.get("housing", 0))
    return total


static func shelter_open(state, b: Dictionary) -> bool:
    return not bool(b.get("stopped", false)) and Crisis.safety(state, int(b["x"]), int(b["y"])) > 0.0


## Food a day for everybody you house.
static func daily_ration(state) -> float:
    return float(state.people) * float(cfg(state).get("ration", 0.1))


## Days your food lasts at today's ration (-1: nobody to feed).
static func food_days(state) -> int:
    var r: float = daily_ration(state)
    if r <= 0.0:
        return -1
    return int(floor(float(state.stock("food")) / r))


## Granary goods spoil a little every day (fractions carry over, so small stocks spoil too).
static func spoil(state) -> int:
    var rate: float = float(cfg(state).get("spoil_per_day", 0.0))
    var lost: int = 0
    for id in state.data["resources"]:
        if str(state.data["resources"][id].get("store", "")) != "granary" or state.stock(id) <= 0:
            continue
        var acc: float = float(state.spoil_carry.get(id, 0.0)) + float(state.stock(id)) * rate
        var whole: int = mini(int(floor(acc)), state.stock(id))
        state.spoil_carry[id] = acc - float(whole)
        state.inventory[id] = state.stock(id) - whole
        lost += whole
    return lost


## The end of the day for your people: food spoils, they eat, the hungry and the homeless leave, newcomers arrive.
static func run_day(state) -> void:
    var c: Dictionary = cfg(state)
    var spoiled: int = spoil(state)
    state.people_stats["spoiled"] = int(state.people_stats.get("spoiled", 0)) + spoiled
    # Eating.
    if state.people > 0:
        state.ration_carry += daily_ration(state)
        var need: int = int(floor(state.ration_carry))
        var eaten: int = mini(need, state.stock("food"))
        state.inventory["food"] = state.stock("food") - eaten
        state.ration_carry -= float(eaten)
        if eaten < need:
            # Nobody lets debt pile up: what was not eaten is gone, and some people leave.
            state.ration_carry = 0.0
            var unfed: float = float(need - eaten) / float(c.get("ration", 0.1))
            var leave: int = mini(state.people, int(ceil(unfed * float(c.get("hunger_leave", 0.25)))))
            state.people -= leave
            state.people_stats["left"] = int(state.people_stats.get("left", 0)) + leave
            if not bool(state.people_flags.get("hungry", false)):
                state.people_news.append({"kind": "hungry", "left": leave})
            state.people_flags["hungry"] = true
        else:
            state.people_flags["hungry"] = false
    # Room: if shelters were lost or left unprotected, the people who no longer have a place go.
    var room: int = housing(state)
    if state.people > room:
        var gone: int = state.people - room
        state.people = room
        state.people_stats["left"] = int(state.people_stats.get("left", 0)) + gone
        state.people_news.append({"kind": "homeless", "left": gone})
    # Newcomers: only once the creatures have landed, and only while there is food to share.
    if Crisis.landed(state) and room > state.people and state.stock("food") > 0:
        var free: int = room - state.people
        var come: int = mini(free, maxi(int(c.get("arrivals_min", 1)), int(ceil(float(free) * float(c.get("arrivals_share", 0.1))))))
        state.people += come
        state.people_stats["arrived"] = int(state.people_stats.get("arrived", 0)) + come
        if not bool(state.people_flags.get("first", false)):
            state.people_flags["first"] = true
            state.people_news.append({"kind": "first", "count": come})
        if state.people >= room and not bool(state.people_flags.get("full", false)):
            state.people_news.append({"kind": "full", "count": state.people})
        state.people_flags["full"] = state.people >= room
    elif state.people < room:
        state.people_flags["full"] = false


static func to_dict(state) -> Dictionary:
    return {"people": state.people, "ration_carry": state.ration_carry, "spoil_carry": state.spoil_carry.duplicate(),
        "stats": state.people_stats.duplicate(), "flags": state.people_flags.duplicate()}


static func load_dict(state, d: Dictionary) -> void:
    state.people = maxi(0, int(d.get("people", 0)))
    state.ration_carry = float(d.get("ration_carry", 0.0))
    state.spoil_carry = {}
    for id in d.get("spoil_carry", {}):
        state.spoil_carry[id] = float(d["spoil_carry"][id])
    state.people_stats = {}
    for k in d.get("stats", {}):
        state.people_stats[k] = int(d["stats"][k])
    state.people_flags = {}
    for k in d.get("flags", {}):
        state.people_flags[k] = bool(d["flags"][k])


static func reset(state) -> void:
    state.people = 0
    state.ration_carry = 0.0
    state.spoil_carry = {}
    state.people_stats = {"arrived": 0, "left": 0, "spoiled": 0}
    state.people_flags = {}
