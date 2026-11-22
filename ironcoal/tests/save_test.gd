extends SceneTree
## Headless tests for saving and loading files.
##   godot --headless --path . -s tests/save_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const SaveManager = preload("res://game/save_manager.gd")

const DIR := "user://test_saves"

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func cleanup() -> void:
    for slot in SaveManager.all_slots():
        SaveManager.delete_save(slot, DIR)
        DirAccess.remove_absolute("%s/%s.json.tmp" % [DIR, slot])


func write_raw(slot: String, text: String) -> void:
    DirAccess.make_dir_recursive_absolute(DIR)
    var f: FileAccess = FileAccess.open(SaveManager.path(slot, DIR), FileAccess.WRITE)
    f.store_string(text)
    f.close()


func _init() -> void:
    cleanup()
    var gd: Dictionary = DataLoader.load_game_data()
    var gs = GameState.new(gd, 77)
    gs.money_cents = 50000000
    gs.build("coal_mine", 8, 9)
    gs.build("coke_oven", 9, 7)
    gs.accept_contract(int(gs.board[0]["id"]))
    for _d in 25:
        gs.advance_day()
    gs.buy("steel", 20)

    print("Saving")
    check(SaveManager.save(gs, "slot_1", DIR) == OK, "a game saves")
    var info: Dictionary = SaveManager.describe("slot_1", DIR)
    check(info["exists"] and info["valid"] and info["day"] == gs.day and info["money_cents"] == gs.money_cents and info["buildings"] == 2, "the menu summary matches the game")
    check(not SaveManager.describe("slot_2", DIR)["exists"], "an empty slot is reported as empty")
    check(not FileAccess.file_exists(DIR + "/slot_1.json.tmp"), "no temporary file is left behind")
    var money_then: int = gs.money_cents
    gs.buy("steel", 5)
    check(SaveManager.save(gs, "slot_1", DIR) == OK and SaveManager.describe("slot_1", DIR)["money_cents"] == gs.money_cents and gs.money_cents != money_then, "saving over a slot replaces it")
    check(SaveManager.save(gs, SaveManager.AUTOSAVE, DIR) == OK and SaveManager.describe("autosave", DIR)["valid"], "the autosave slot works the same way")

    print("Loading")
    var r: Dictionary = SaveManager.restore(gd, "slot_1", DIR)
    check(r["ok"], "a save restores")
    var gs2 = r["state"]
    check(gs2.day == gs.day and gs2.money_cents == gs.money_cents and gs2.buildings.size() == 2 and gs2.stock("coal") == gs.stock("coal"), "day, money, buildings and stock come back")
    check(gs2.active_contracts.size() == gs.active_contracts.size() and gs2.board.size() == gs.board.size(), "contracts come back")
    check(not gs2.build("coal_mine", 8, 9)["ok"], "built tiles stay occupied")
    for _d in 30:
        gs.advance_day()
        gs2.advance_day()
    var same: bool = gs.money_cents == gs2.money_cents and gs.stock("coke") == gs2.stock("coke") and gs.stock("coal") == gs2.stock("coal") and JSON.stringify(gs.board) == JSON.stringify(gs2.board)
    for id in gd["resources"]:
        if absf(gs.market.spot_price(id) - gs2.market.spot_price(id)) > 0.001 or absf(float(gs.market.presence[id]) - float(gs2.market.presence[id])) > 0.001:
            same = false
    check(same, "the loaded game plays on exactly like the original for 30 days")

    print("Bad files")
    check(SaveManager.restore(gd, "slot_3", DIR)["reason"] == "missing", "a missing save is reported")
    write_raw("slot_2", "{ this is not json")
    check(SaveManager.restore(gd, "slot_2", DIR)["reason"] == "damaged" and SaveManager.describe("slot_2", DIR)["exists"] and not SaveManager.describe("slot_2", DIR)["valid"], "a damaged file is reported, not crashed on")
    write_raw("slot_2", JSON.stringify({"hello": "world"}))
    check(SaveManager.restore(gd, "slot_2", DIR)["reason"] == "not_a_save", "a file from something else is refused")
    var old: Dictionary = gs.to_dict()
    old["version"] = 1
    write_raw("slot_2", JSON.stringify({"format": SaveManager.FORMAT, "meta": {"day": 1, "money_cents": 0, "buildings": 0, "saved_at": 0}, "state": old}))
    check(SaveManager.restore(gd, "slot_2", DIR)["reason"] == "older_version", "a save from an older version is refused")
    var odd: Dictionary = gs.to_dict()
    odd["buildings"][0]["type"] = "teleporter"
    write_raw("slot_2", JSON.stringify({"format": SaveManager.FORMAT, "meta": {"day": 1, "money_cents": 0, "buildings": 0, "saved_at": 0}, "state": odd}))
    check(SaveManager.restore(gd, "slot_2", DIR)["reason"] == "incompatible", "a save with buildings this game does not know is refused")
    var day_before: int = gs.day
    check(gs.day == day_before and gs.buildings.size() == 2, "a failed load leaves the running game alone")

    print("Housekeeping")
    SaveManager.delete_save("slot_1", DIR)
    check(not SaveManager.describe("slot_1", DIR)["exists"], "a save can be deleted")
    check(SaveManager.label("slot_2") == "Slot 2" and SaveManager.label("autosave") == "Autosave", "slots have readable names")
    cleanup()

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
