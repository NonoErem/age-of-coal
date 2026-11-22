extends RefCounted
## Saving and loading games as JSON files: three manual slots and an autosave.
## Files live in user://saves. Each file holds a small summary (for the menu) and the full game state.
## A save is written to a temporary file first, so a crash while saving cannot ruin an existing save.

const GameState = preload("res://sim/game_state.gd")

const FORMAT := "ironcoal-save"
const DEFAULT_DIR := "user://saves"
const AUTOSAVE := "autosave"
const MANUAL_SLOTS := ["slot_1", "slot_2", "slot_3"]


static func all_slots() -> Array:
    return MANUAL_SLOTS + [AUTOSAVE]


static func label(slot: String) -> String:
    if slot == AUTOSAVE:
        return "Autosave"
    return "Slot %s" % slot.trim_prefix("slot_")


static func path(slot: String, dir: String = DEFAULT_DIR) -> String:
    return "%s/%s.json" % [dir, slot]


## Returns OK or an Error code.
static func save(state, slot: String, dir: String = DEFAULT_DIR) -> int:
    var made: int = DirAccess.make_dir_recursive_absolute(dir)
    if made != OK:
        return made
    var payload: Dictionary = {
        "format": FORMAT,
        "meta": {
            "saved_at": int(Time.get_unix_time_from_system()),
            "day": state.day,
            "money_cents": state.money_cents,
            "buildings": state.buildings.size(),
        },
        "state": state.to_dict(),
    }
    var final_path: String = path(slot, dir)
    var tmp_path: String = final_path + ".tmp"
    var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(JSON.stringify(payload))
    f.close()
    var da: DirAccess = DirAccess.open(dir)
    if da == null:
        return ERR_CANT_OPEN
    if da.file_exists(slot + ".json"):
        da.remove(slot + ".json")
    return da.rename(slot + ".json.tmp", slot + ".json")


## {"ok": true, "payload": Dictionary} or {"ok": false, "reason": "missing" | "damaged" | "not_a_save" | "older_version"}
static func read(slot: String, dir: String = DEFAULT_DIR) -> Dictionary:
    var p: String = path(slot, dir)
    if not FileAccess.file_exists(p):
        return {"ok": false, "reason": "missing"}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "damaged"}
    if parsed.get("format", "") != FORMAT or typeof(parsed.get("state")) != TYPE_DICTIONARY or typeof(parsed.get("meta")) != TYPE_DICTIONARY:
        return {"ok": false, "reason": "not_a_save"}
    if int(parsed["state"].get("version", 0)) != GameState.SAVE_VERSION:
        return {"ok": false, "reason": "older_version"}
    return {"ok": true, "payload": parsed}


## What the menu shows for a slot.
static func describe(slot: String, dir: String = DEFAULT_DIR) -> Dictionary:
    var r: Dictionary = read(slot, dir)
    if r["ok"]:
        var m: Dictionary = r["payload"]["meta"]
        return {"exists": true, "valid": true, "day": int(m["day"]), "money_cents": int(m["money_cents"]),
            "buildings": int(m["buildings"]), "saved_at": int(m["saved_at"])}
    if r["reason"] == "missing":
        return {"exists": false, "valid": false}
    return {"exists": true, "valid": false, "reason": r["reason"]}


## Builds a new game state from a save. The current game is untouched if this fails.
## {"ok": true, "state": GameState} or {"ok": false, "reason": ...}
static func restore(game_data: Dictionary, slot: String, dir: String = DEFAULT_DIR) -> Dictionary:
    var r: Dictionary = read(slot, dir)
    if not r["ok"]:
        return r
    var src: Dictionary = r["payload"]["state"]
    var fresh = GameState.new(game_data, int(src.get("seed", 1)))
    if not fresh.load_dict(src):
        return {"ok": false, "reason": "incompatible"}
    return {"ok": true, "state": fresh}


static func delete_save(slot: String, dir: String = DEFAULT_DIR) -> void:
    if FileAccess.file_exists(path(slot, dir)):
        DirAccess.remove_absolute(path(slot, dir))


static func reason_text(reason: String) -> String:
    match reason:
        "missing": return "there is no save there."
        "damaged": return "the file is damaged."
        "not_a_save": return "that file is not a save from this game."
        "older_version": return "it was made by an older version of the game."
        "incompatible": return "it does not fit the current game data."
    return reason


## "2026-11-22 15:00" in the player's local time.
static func time_text(unix: int) -> String:
    var bias_seconds: int = int(Time.get_time_zone_from_system()["bias"]) * 60
    return Time.get_datetime_string_from_unix_time(unix + bias_seconds, true).substr(0, 16)
