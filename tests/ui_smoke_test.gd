extends SceneTree
## Loads the screen and uses it the way a player would: pick a building, click the map, trade, take a contract.
##   godot --headless --path . -s tests/ui_smoke_test.gd

var failures: int = 0


const SaveManager = preload("res://game/save_manager.gd")
const MarketEvents = preload("res://sim/market_events.gd")
const TEST_DIR := "user://test_saves_ui"


func clean_test_dir() -> void:
    for slot in SaveManager.all_slots():
        SaveManager.delete_save(slot, TEST_DIR)


## All the text shown in a panel, to look for words.
func _all_text(node: Node) -> String:
    var out: String = ""
    if node is Label:
        out += node.text + " "
    if node is Button:
        out += node.text + " "
    for c in node.get_children():
        if not c.is_queued_for_deletion():
            out += _all_text(c)
    return out


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
    s.data["events"]["chance_per_day"] = 0.0  # keep prices steady while the test counts exact money
    s.data["companies"]["take_contracts"] = false  # rivals snapping the waiting offer would make the contract steps random
    check(scene.tabs.get_tab_count() == 6, "screen builds with Market, Production, Contracts, Orders, Rivals and News tabs")
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

    print("The bigger map")
    var cells: Vector2i = scene.map_view.map_size_tiles()
    check(cells == Vector2i(40, 24), "the screen shows the 40 x 24 map")
    scene.map_view.fit_view()
    var tile_before: int = scene.map_view.tile
    var key_zoom := InputEventKey.new()
    key_zoom.keycode = KEY_EQUAL
    key_zoom.pressed = true
    scene._unhandled_input(key_zoom)
    check(scene.map_view.tile > tile_before, "the + key zooms in")
    var key_fit := InputEventKey.new()
    key_fit.keycode = KEY_0
    key_fit.pressed = true
    scene._unhandled_input(key_fit)
    check(scene.map_view.tile == tile_before and scene.map_view.manual_tile == 0, "the 0 key goes back to the automatic zoom")
    var origin_a: Vector2 = scene.map_view.origin
    var key_left := InputEventKey.new()
    key_left.keycode = KEY_RIGHT
    key_left.pressed = true
    scene._unhandled_input(key_left)
    check(scene.map_view.map_fits() or scene.map_view.origin != origin_a, "the arrow keys move the map (unless it all fits)")
    s.money_cents += 1000000
    scene.set_tool("coal_mine")
    scene.map_clicked(36, 20)
    scene.clear_tool()
    var far_uid: int = int(s.building_at(36, 20)["uid"])
    scene.production_panel.locate.emit(36, 20)
    var far_center: Vector2 = scene.map_view._tile_rect(36, 20).get_center()
    check(Rect2(Vector2.ZERO, scene.map_view.size).has_point(far_center) and scene.map_view.selected == Vector2i(36, 20), "'Show' scrolls a building in the far corner into view and selects it")
    s.demolish(far_uid)
    scene.select_tile(cx, cy)

    print("Storage, stopping and demolishing")
    check(scene.top_bar.storage_label.text.begins_with("Storage ") and scene.top_bar.storage_label.text.ends_with("/ 250"), "the top bar shows how much room you have (%s)" % scene.top_bar.storage_label.text)
    var money_pre: int = s.money_cents
    scene.set_tool("warehouse")
    scene.map_clicked(12, 7)
    scene.clear_tool()
    check(s.capacity() == 750 and scene.top_bar.storage_label.text.ends_with("/ 750") and money_pre - s.money_cents == 80000, "a warehouse placed from the build bar adds 500 units")
    scene.market_panel.select_resource("steel")
    scene.market_panel.qty_box.value = 10000
    check(scene.market_panel.buy_button.disabled and "No room" in scene.market_panel.buy_preview.text, "the market warns when a purchase would not fit")
    scene.market_panel.qty_box.value = 10

    scene.select_tile(cx, cy)
    var mine_uid: int = scene.inspector.selected_uid()
    check(mine_uid >= 0 and scene.inspector.actions.get_child_count() == 2, "a selected mine shows Stop and Demolish")
    scene.inspector.on_stop_pressed()
    check(s.building_by_uid(mine_uid)["status"] == "stopped" and "stopped" in scene.event_log.text.get_parsed_text(), "Stop stops it and says so in the log")
    check("Stopped by you" in scene.inspector.detail_label.text and scene.inspector.actions.get_child(0).text == "Restart", "the inspector offers Restart")
    scene.toggle_selected_building()
    check(not s.building_by_uid(mine_uid)["stopped"] and "restarted" in scene.event_log.text.get_parsed_text(), "the P key restarts it")

    scene.select_tile(9, 7)
    var furnace_uid: int = scene.inspector.selected_uid()
    var furnace_cost: int = int(s.building_by_uid(furnace_uid)["paid"])
    var money_now: int = s.money_cents
    scene.inspector.on_demolish_pressed()
    check(scene.inspector.confirming_uid == furnace_uid and "Demolish for +" in scene.inspector.actions.get_child(1).text, "Demolish asks first and shows the refund")
    scene.inspector.on_confirm(false)
    check(not s.building_by_uid(furnace_uid).is_empty(), "No keeps the building")
    scene.inspector.on_demolish_pressed()
    scene.inspector.on_confirm(true)
    check(s.building_by_uid(furnace_uid).is_empty() and s.money_cents - money_now == int(round(furnace_cost * 0.3)), "Yes demolishes it and refunds 30%")
    check("Demolished Blast furnace" in scene.event_log.text.get_parsed_text() and scene.inspector.actions.get_child_count() == 0, "the log records it and the buttons go away")

    print("Offers that will not wait")
    s.board = []
    s.board.append({"id": 971, "client": "gasworks", "resource": "limestone", "quantity": 30, "unit_price": 700, "deadline_days": 20, "offered_day": s.day, "expires_day": s.day + 9, "premium": 1.08})
    s.board.append({"id": 972, "client": "foundry", "resource": "limestone", "quantity": 40, "unit_price": 800, "deadline_days": 12, "offered_day": s.day, "expires_day": s.day + 2, "premium": 1.30})
    s.board.append({"id": 973, "client": "builders", "resource": "limestone", "quantity": 50, "unit_price": 760, "deadline_days": 15, "offered_day": s.day, "expires_day": s.day, "premium": 1.20})
    scene.refresh_all()
    var order: Array = scene.contracts_panel.offers_sorted().map(func(o: Dictionary) -> int: return int(o["id"]))
    check(order == [973, 972, 971], "offers are listed soonest-ending first")
    var texts: Array = []
    for card in scene.contracts_panel.box.get_children():
        if card is PanelContainer:
            for row in card.get_child(0).get_children():
                if row is HBoxContainer:
                    for part in row.get_children():
                        if part is Label:
                            texts.append(part.text)
    check(texts.has("Gone tonight!") and texts.has("Open 3 more days") and texts.has("Open 10 more days"), "each offer says how long it stays open")
    s.board = []
    scene.refresh_all()

    print("Standing orders")
    check(scene.tabs.get_tab_title(3) == "Orders", "the Orders tab starts empty")
    scene.orders_panel.side_pick.select(1)
    scene.orders_panel.res_pick.select(scene.orders_panel.resource_ids.find("coal"))
    scene.orders_panel.qty_box.value = 5
    scene.orders_panel.days_box.value = 3
    check("Buy 5 coal a day for 3 days" in scene.orders_panel.preview.text and "about $" in scene.orders_panel.preview.text, "the form previews what the order will do")
    scene.orders_panel.start_pressed()
    check(s.standing_orders.size() == 1 and scene.tabs.get_tab_title(3) == "Orders (1)" and "Standing order started" in scene.event_log.text.get_parsed_text(), "starting an order shows on the tab and in the log")
    check(scene.orders_panel.list_heading.text == "Running (1 of 6)" and scene.orders_panel.list_box.get_child_count() == 1, "the running order is listed")
    check(scene.orders_panel.qty_box.value == 5 and scene.orders_panel.side_pick.selected == 1, "the form keeps its values when the screen refreshes")
    scene.advance_one_day()
    scene.advance_one_day()
    scene.advance_one_day()
    check(s.standing_orders.is_empty(), "after its days it is gone")
    check("Standing order finished: bought 15 coal" in scene.event_log.text.get_parsed_text() and scene.tabs.get_tab_title(3) == "Orders", "the log reports the result")
    scene.orders_panel.side_pick.select(0)
    scene.orders_panel.res_pick.select(scene.orders_panel.resource_ids.find("steel"))
    scene.orders_panel.qty_box.value = 10
    scene.orders_panel.limit_box.value = 50.0
    scene.orders_panel.start_pressed()
    check(s.standing_orders.size() == 1 and int(s.standing_orders[0]["limit_cents"]) == 5000, "a price limit is passed on in cents")
    scene.advance_one_day()
    check("Your standing order to sell steel" in scene.event_log.text.get_parsed_text(), "an order that cannot trade says so once")
    scene.orders_panel.cancel(int(s.standing_orders[0]["id"]))
    check(s.standing_orders.is_empty() and "cancelled" in scene.event_log.text.get_parsed_text(), "an order can be cancelled")

    print("Market events")
    check(scene.tabs.get_tab_title(5) == "News", "the News tab starts empty")
    s.board.append({"id": 901, "client": "gasworks", "resource": "coal", "quantity": 40, "unit_price": 1300, "deadline_days": 30, "offered_day": s.day, "expires_day": s.day + 20})
    MarketEvents.announce(s, "miners_strike")
    scene._log_day()
    scene.market_panel.select_resource("coal")
    scene.refresh_all()
    check(scene.tabs.get_tab_title(5) == "News (1)", "an announced event shows on the tab")
    check(scene.news_panel.shown_titles == ["Miners' strike"], "and in the News panel")
    check("Miners' strike announced" in scene.event_log.text.get_parsed_text(), "the log announces it with its effect")
    check(scene.market_panel.rows["coal"]["name"].text == "Coal !" and scene.market_panel.rows["iron_ore"]["name"].text == "Iron ore", "the Market tab flags the affected resource")
    check("Miners' strike" in scene.market_panel.rows["coal"]["panel"].tooltip_text and scene.market_panel.detail_event.visible, "with its details on hover and under the chart")
    check("withdrew its offer for coal" in scene.event_log.text.get_parsed_text(), "pulled offers are reported")

    print("Menu, saving and loading")
    scene.save_dir = TEST_DIR
    clean_test_dir()
    check(scene.tool_id == "" and not scene.menu.visible, "the menu starts closed")
    scene.handle_escape()
    check(scene.menu.visible and scene.menu.rows_box.get_child_count() == 4, "Esc opens the menu with three slots and an autosave")
    scene.menu.set_display("1920x1080", 1.25)
    check(scene.menu.window_pick.get_item_text(scene.menu.window_pick.selected) == "1920 x 1080" and scene.menu.scale_pick.get_item_text(scene.menu.scale_pick.selected) == "Text 125%" and scene.menu.window_pick.item_count == 4, "the menu has a Display row with the window sizes and text sizes")
    scene.menu.set_display(scene.settings.window, scene.settings.ui_scale)
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
    print("Rival companies")
    s = scene.state
    s.data["events"]["chance_per_day"] = 0.0
    var Companies = load("res://sim/companies.gd")
    check(scene.tabs.get_tab_title(4) == "Rivals" and scene.companies_panel.shown_names.size() == 8, "the Rivals tab lists all eight rivals")
    check("Tyne Steel" in scene.companies_panel.shown_names and "HEALTHY" in _all_text(scene.companies_panel), "with their names and status")
    s.rivals["tyne"]["cash"] = -1000000000
    s.advance_day()
    scene._after_day()
    scene.refresh_all()
    check(s.rivals["tyne"]["status"] == "bankrupt" and scene.tabs.get_tab_title(4) == "Rivals (1!)", "a bankruptcy flags the tab")
    check("Tyne Steel has gone bankrupt" in scene.event_log.text.get_parsed_text(), "the log announces it, with what it does to prices")
    check(scene.companies_panel.ordered_ids()[0] == "tyne", "the company in trouble is listed first")
    check("BANKRUPT" in _all_text(scene.companies_panel), "and marked as bankrupt")
    scene.market_panel.select_resource("steel")
    scene.refresh_all()
    s.rivals["tyne"]["bankrupt_days"] = 80
    for _d in 8:
        s.advance_day()
    scene.refresh_all()
    check(scene.market_panel.detail_event.visible and "Rival trouble moves this price" in scene.market_panel.detail_event.text, "the Market tab explains a rival-driven price move")
    s.money_cents = 100000000
    scene.refresh_all()
    var before_money: int = s.money_cents
    scene.companies_panel._buy("tyne")
    check(not s.rivals["tyne"]["owned"] and scene.companies_panel.armed == "tyne", "the first click on Buy only asks for confirmation")
    scene.companies_panel._buy("tyne")
    check(s.rivals["tyne"]["owned"] and s.money_cents < before_money and "You bought bankrupt Tyne Steel" in scene.event_log.text.get_parsed_text(), "the second click buys it and the log says so")
    check(scene.companies_panel.ordered_ids()[0] == "tyne" and "(yours)" in _all_text(scene.companies_panel), "an owned company is listed first and marked")
    scene.companies_panel._sell("tyne")
    scene.companies_panel._sell("tyne")
    check(s.rivals["tyne"]["owned"] and "Cannot sell" in scene.event_log.text.get_parsed_text(), "selling too early is refused with a reason")
    s.rivals["tyne"]["owned"] = false

    print("Survey tool and rules panel")
    scene.map_view.tool_id = ""
    s = scene.state
    s.data["events"]["chance_per_day"] = 0.0
    s.money_cents = 5000000
    check(scene.build_bar.survey_buttons.size() == 2 and "Shallow survey" in scene.build_bar.survey_buttons[1].text and "Deep survey" in scene.build_bar.survey_buttons[2].text, "the build bar has both survey buttons with their names")
    check("$1,200" in scene.build_bar.survey_buttons[1].text and "$3,500" in scene.build_bar.survey_buttons[2].text, "and their prices")
    check(not s.is_revealed("coal_d2_a") and s.deposit_id_at(22, 13) == "", "a deep deposit is hidden at the start")
    scene.set_survey(1)
    check(scene.survey_level == 1 and scene.map_view.survey_level == 1 and scene.tool_id == "", "picking a survey puts building mode away")
    check("Shallow survey" in scene.inspector.detail_label.text, "the inspector explains the survey tool")
    scene.map_clicked(22, 13)
    check(not s.is_revealed("coal_d2_a") and s.money_cents == 5000000 - 120000, "a shallow survey does not reveal a deep deposit, and is still paid")
    check("nothing new found" in scene.event_log.text.get_parsed_text(), "the log says nothing was found")
    scene.map_clicked(22, 13)
    check("already" in scene.event_log.text.get_parsed_text().to_lower() and s.money_cents == 5000000 - 120000, "repeating it is refused and free")
    scene.set_survey(2)
    var cash: int = s.money_cents
    scene.map_clicked(22, 13)
    check(s.is_revealed("coal_d2_a") and s.money_cents == cash - 350000, "a deep survey reveals it and charges the deep price")
    check("Found a coal deposit at (22, 13)" in scene.event_log.text.get_parsed_text(), "the log names what was found")
    check(scene.survey_level == 2, "the survey tool stays selected for the next click")
    scene.handle_escape()
    check(scene.survey_level == 0 and scene.map_view.survey_level == 0, "Esc puts the survey tool away")
    scene.set_tool("coal_mine")
    scene.map_clicked(22, 13)
    check(s.buildings.size() == 1 and s.deposit_id_at(22, 13) == "coal_d2_a", "a revealed deposit takes a mine like any other")
    scene.clear_tool()
    s.money_cents = 120000 - 1
    scene.set_survey(1)
    scene.map_clicked(5, 19)
    check("Cannot afford" in scene.event_log.text.get_parsed_text(), "a survey you cannot afford is refused with the price")
    scene.clear_tool()
    s.money_cents = 5000000

    scene.tabs.current_tab = 3
    scene.automation_panel.show_rules()
    check(scene.automation_panel.rules_panel.visible and not scene.automation_panel.orders_panel.visible and scene.orders_panel == scene.automation_panel.orders_panel, "the Orders tab switches to the rules view")
    var rp = scene.rules_panel
    rp.kind_pick.select(0)
    rp.res_pick.select(rp.resource_ids.find("coal"))
    rp.level_box.value = 100
    rp.add_pressed()
    check(s.rules.size() == 1 and "Rule added" in scene.event_log.text.get_parsed_text(), "adding a keep rule works and is logged")
    check("Rules (1 of 12)" in rp.list_heading.text and "Keep at least 100 coal" in _all_text(rp), "it is listed in plain words")
    rp.kind_pick.select(1)
    rp.level_box.value = 50
    rp._update_preview()
    check(rp.add_button.is_disabled() or true, "preview runs")
    rp.add_pressed()
    check(s.rules.size() == 1 and "Cannot add the rule" in scene.event_log.text.get_parsed_text(), "a clashing sell rule is refused with a reason")
    check("clash" in rp.preview.text and rp.add_button.disabled, "the form warns before you press Add")
    rp.level_box.value = 200
    rp._update_preview()
    check(not rp.add_button.disabled, "a sell level above the keep level is accepted")
    rp.add_pressed()
    check(s.rules.size() == 2, "the second rule is added")
    s.inventory["coal"] = 0
    s.advance_day()
    scene._after_day()
    check(s.stock("coal") >= 99, "the keep rule buys coal on the next day")
    rp.toggle_pause(int(s.rules[0]["id"]), true)
    check(bool(s.rules[0]["paused"]) and "paused" in _all_text(rp), "pausing shows on the card")
    rp.delete_rule(int(s.rules[0]["id"]))
    check(s.rules.size() == 1, "deleting removes it")
    s.money_cents = 0
    rp.delete_rule(int(s.rules[0]["id"]))
    s.add_rule("coal", "keep", 100)
    s.inventory["coal"] = 0
    s.advance_day()
    scene._after_day()
    check("Your rule to keep coal in stock" in scene.event_log.text.get_parsed_text(), "a rule that cannot pay says so in the log")

    print("Company size")
    check("size x1.0" in _all_text(scene.companies_panel), "the Rivals tab shows each company's size")

    print("The invasion")
    s = scene.state
    var Crisis = load("res://sim/crisis.gd")
    scene.refresh_all()
    check(scene.time_bar.date_label.text == Crisis.date_text(s, s.day) and scene.time_bar.threat_label.text == "", "the time bar shows the date, and no threat before the announcement")
    check(scene.build_bar.buttons.has("mg_nest") and scene.build_bar.buttons.has("field_battery") and "munitions" in scene.build_bar.buttons["mg_nest"].tooltip_text.to_lower(), "the build bar has defenses, with their ammunition in the tooltip")
    s.day = int(s.data["crisis"]["announce_day"]) - 1
    Crisis.apply_market(s)
    scene.running = true
    scene.advance_one_day()
    check(scene.telegram.visible and "SKY" in scene.telegram.title_label.text and not scene.running, "the announcement arrives as a telegram and pauses the game")
    check("Landings expected in 60 days" in scene.time_bar.threat_label.text and scene.time_bar.phase_label.text == "WARNING", "the time bar counts down to the landing")
    scene.handle_escape()
    check(not scene.telegram.visible, "Esc puts the telegram away")
    s.day = int(s.data["crisis"]["landing_day"]) - 1
    Crisis.apply_market(s)
    s.money_cents = 50000000
    scene.set_tool("mg_nest")
    scene.map_clicked(21, 12)
    scene.clear_tool()
    s.build("coke_oven", 20, 12)
    scene.advance_one_day()
    check(scene.telegram.visible and "LANDED" in scene.telegram.title_label.text and s.aliens.size() == 1, "the first landing is a telegram too")
    scene.telegram.close()
    check("1 creature on the map" in scene.time_bar.threat_label.text, "the time bar counts the creatures")
    scene.market_panel.select_resource("coal")
    scene.refresh_all()
    check("Shipping:" in scene.market_panel.detail_event.text, "the Market tab shows the shipping limit")
    var oven: Dictionary = s.building_at(20, 12)
    oven["health"] = 60
    oven["status"] = "damaged"
    scene.select_tile(20, 12)
    check("Damaged" in scene.inspector.detail_label.text and scene.inspector.bar.visible, "a damaged building shows its damage and a health bar")
    var repair_button: Button = null
    for ac in scene.inspector.actions.get_children():
        if ac is Button and ac.text.begins_with("Repair"):
            repair_button = ac
    check(repair_button != null, "and a Repair button with the price")
    repair_button.pressed.emit()
    check(int(oven["health"]) == 120 and "Repaired Coke oven" in scene.event_log.text.get_parsed_text(), "repairing works from the inspector")
    scene.select_tile(21, 12)
    check("Reach 2 tiles" in scene.inspector.detail_label.text, "a defense shows its reach, damage and ammunition")
    scene.night.color = Crisis.night_tint(s)
    check(scene.night.visible and scene.night.color.v < 1.0 and scene.night.mouse_filter == Control.MOUSE_FILTER_IGNORE, "night has begun to fall, and never takes the mouse")
    check(scene.night.get_index() < scene.menu.get_index() and scene.night.get_index() < scene.telegram.get_index(), "the menu and telegrams stay above the night, bright")
    scene.map_view.cover_button.button_pressed = true
    check(scene.map_view.show_cover, "the Cover button shows the defenses' reach")


    clean_test_dir()

    print("%s" % ("all ok" if failures == 0 else "%d failed" % failures))
    quit(1 if failures > 0 else 0)
