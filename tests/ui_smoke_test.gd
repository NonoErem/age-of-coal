extends SceneTree
## Loads the screen and uses it the way a player would: pick a building, click the map, trade, take a contract.
##   godot --headless --path . -s tests/ui_smoke_test.gd

var failures: int = 0


const SaveManager = preload("res://game/save_manager.gd")
const TEST_DIR := "user://test_saves_ui"


func clean_test_dir() -> void:
    for slot in SaveManager.all_slots():
        SaveManager.delete_save(slot, TEST_DIR)


func check(cond: bool, label: String) -> void:
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func _initialize() -> void:
    print("UI smoke test")
    # Watchdog: if a script error stops this coroutine early, still exit instead of hanging.
    create_timer(30.0).timeout.connect(func() -> void:
        print("  FAIL  timed out (a script error stopped the test)")
        quit(2))
    var scene: Control = load("res://game/main.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    var s = scene.state
    check(scene.tabs.get_tab_count() == 3, "screen builds with Market, Production and Contracts tabs")
    check(scene.tabs.get_tab_title(2) == "Contracts (1)", "the contracts tab shows the waiting offer")

    print("Map and build mode")
    var coal: Dictionary = s.data["map"]["deposits"]["coal_2"]
    var cx: int = int(coal["x"])
    var cy: int = int(coal["y"])
    var c: Vector2 = scene.map_view._tile_rect(cx, cy).get_center()
    check(scene.map_view.tile_at(c) == Vector2i(cx, cy), "a click position maps back to the right tile")
    scene.build_bar.buttons["coal_mine"].button_pressed = true
    check(scene.tool_id == "coal_mine" and scene.map_view.tool_id == "coal_mine", "choosing a building starts build mode")
    scene.select_tile(cx, cy)
    check("Click to place Coal mine for $2,000.00" in scene.inspector.detail_label.text, "inspector shows the price on a legal tile")
    scene.select_tile(0, 0)
    check("needs a deposit" in scene.inspector.detail_label.text, "inspector explains an illegal tile")
    scene.map_clicked(cx, cy)
    check(s.buildings.size() == 1 and s.money_cents == 800000, "clicking a legal tile builds and charges")
    check("Built Coal mine" in scene.event_log.text.get_parsed_text(), "the log records it")
    scene.map_clicked(0, 0)
    check(s.buildings.size() == 1 and "Cannot build" in scene.event_log.text.get_parsed_text(), "a bad click builds nothing and says why")
    scene.clear_tool()
    check(scene.tool_id == "" and not scene.build_bar.buttons["coal_mine"].button_pressed, "Esc / right-click leaves build mode")

    print("Time")
    scene.advance_one_day()
    check(s.stock("coal") == 60 and s.day == 2, "next day: the mine produced coal")
    scene.toggle_pause()
    scene.set_speed(4)
    check(scene.running and scene.speed == 4 and scene.top_bar.play_button.text == "Pause", "play and speed controls work")
    scene.toggle_pause()

    print("Market")
    scene.market_panel.select_resource("iron_ore")
    check("Iron ore" in scene.market_panel.detail_title.text, "selecting a row shows that resource")
    scene.market_panel.qty_box.value = 10
    check("Sell 10" in scene.market_panel.sell_preview.text and not scene.market_panel.sell_button.disabled, "trade preview shows the sale")
    scene.market_panel.qty_box.value = 1000
    check(scene.market_panel.sell_button.disabled and "only hold 20" in scene.market_panel.sell_preview.text, "selling more than you hold is blocked and explained")
    scene.market_panel.qty_box.value = 10
    var money_before: int = s.money_cents
    scene.market_panel._on_sell()
    check(s.stock("iron_ore") == 10 and s.money_cents > money_before, "the sell button sells")

    print("Contracts")
    var offer_id: int = int(s.board[0]["id"])
    scene.contracts_panel.accept(offer_id)
    check(s.active_contracts.size() == 1, "accepting takes the contract")
    money_before = s.money_cents
    scene.contracts_panel.deliver_max(offer_id)
    check(s.money_cents - money_before == 40 * 1300 and s.active_contracts.is_empty(), "delivering pays and completes it")
    check("Contract complete" in scene.event_log.text.get_parsed_text(), "the log records the delivery")

    print("Production")
    scene.set_tool("blast_furnace")
    scene.map_clicked(9, 7)
    scene.clear_tool()
    check(s.buildings.size() == 2, "a factory goes on free ground")
    scene.advance_one_day()
    check(scene.production_panel.attention_count == 1 and scene.tabs.get_tab_title(1) == "Production (1!)", "a paused factory flags the Production tab")
    check("paused: missing coke, limestone" in scene.event_log.text.get_parsed_text(), "and shows in the log with the resource name")
    scene.production_panel.locate.emit(9, 7)
    check(scene.map_view.selected == Vector2i(9, 7) and "Paused: missing coke, limestone" in scene.inspector.detail_label.text, "'Show' selects the building on the map")

    print("Menu, saving and loading")
    scene.save_dir = TEST_DIR
    clean_test_dir()
    check(scene.tool_id == "" and not scene.menu.visible, "the menu starts closed")
    scene.handle_escape()
    check(scene.menu.visible and scene.menu.rows_box.get_child_count() == 4, "Esc opens the menu with three slots and an autosave")
    scene.handle_escape()
    check(not scene.menu.visible, "Esc closes it again")
    scene.set_tool("coal_mine")
    scene.handle_escape()
    check(scene.tool_id == "" and not scene.menu.visible, "Esc first leaves build mode, it does not open the menu")

    scene.open_menu()
    scene.menu.on_save_pressed("slot_1")
    var saved_day: int = scene.state.day
    check(SaveManager.describe("slot_1", TEST_DIR)["valid"] and SaveManager.describe("slot_1", TEST_DIR)["day"] == saved_day, "saving to an empty slot just saves")
    check("Saved to Slot 1" in scene.menu.message_label.text, "the menu confirms it")
    scene.close_menu()
    scene.advance_one_day()
    scene.advance_one_day()
    var later_day: int = scene.state.day
    scene.open_menu()
    scene.menu.on_save_pressed("slot_1")
    check(scene.menu.confirming.get("kind", "") == "save", "saving over a used slot asks first")
    scene.menu.on_confirm(false)
    check(SaveManager.describe("slot_1", TEST_DIR)["day"] == saved_day, "saying no keeps the old save")

    var old_state = scene.state
    scene.menu.on_load_pressed("slot_1")
    check(scene.menu.confirming.get("kind", "") == "load", "loading while you have progress asks first")
    scene.menu.on_confirm(true)
    check(scene.state != old_state and scene.state.day == saved_day and saved_day < later_day, "loading brings back the saved day (%d, not %d)" % [saved_day, later_day])
    check(scene.market_panel.state == scene.state and scene.top_bar.state == scene.state and not scene.menu.visible, "every screen now shows the loaded game and the menu closed")
    check(scene.state.buildings.size() == 2, "buildings are back on the map")
    check("Loaded Slot 1" in scene.event_log.text.get_parsed_text(), "the log records the load")

    while scene.state.day < 10:
        scene.advance_one_day()
    check(SaveManager.describe("autosave", TEST_DIR)["valid"] and SaveManager.describe("autosave", TEST_DIR)["day"] == 10, "the game autosaves every 10 days")

    scene.open_menu()
    scene.menu.on_load_pressed("slot_3")
    scene.menu.on_confirm(true)
    check(scene.menu.visible and "Could not load" in scene.menu.message_label.text and scene.state.day == 10, "loading an empty slot fails politely and keeps the game")

    scene.menu.on_new_pressed()
    check(scene.menu.confirming.get("kind", "") == "new", "new game asks first")
    scene.menu.on_confirm(true)
    check(scene.state.day == 1 and scene.state.buildings.is_empty() and scene.state.money_cents == 1000000, "new game starts fresh")
    clean_test_dir()

    print("%s" % ("all ok" if failures == 0 else "%d failed" % failures))
    quit(1 if failures > 0 else 0)
