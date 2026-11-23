extends Control
## The main screen. It builds the interface and passes commands to the game state.
## Layout: top bar / (map, inspector, build bar | Market, Production, Contracts tabs) / event log.
## Keys: Space pause, 1/2/3 speed, N next day, Esc stop placing or open the menu.

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const Style = preload("res://ui/style.gd")
const Inspector = preload("res://ui/inspector.gd")
const MapView = preload("res://game/map_view.gd")
const TopBar = preload("res://ui/top_bar.gd")
const BuildBar = preload("res://ui/build_bar.gd")
const EventLog = preload("res://ui/event_log.gd")
const GameMenu = preload("res://ui/game_menu.gd")
const NewsPanel = preload("res://ui/news_panel.gd")
const SaveManager = preload("res://game/save_manager.gd")
const MarketEvents = preload("res://sim/market_events.gd")
const MarketPanel = preload("res://ui/market_panel.gd")
const ProductionPanel = preload("res://ui/production_panel.gd")
const ContractsPanel = preload("res://ui/contracts_panel.gd")

const SPEEDS := [1, 2, 4]

var state
var running: bool = false
var speed: int = 1
var acc: float = 0.0
var tool_id: String = ""
var was_negative: bool = false
var save_dir: String = SaveManager.DEFAULT_DIR
var menu

var top_bar
var map_view
var inspector
var build_bar
var event_log
var tabs: TabContainer
var market_panel
var production_panel
var contracts_panel
var news_panel


func _ready() -> void:
    var data: Dictionary = DataLoader.load_game_data()
    for e in DataLoader.validate(data):
        push_error(e)
    state = GameState.new(data, int(Time.get_unix_time_from_system()))
    get_window().min_size = Vector2i(1000, 640)
    _build_ui()
    _welcome()
    refresh_all()


func _welcome() -> void:
    event_log.add("Welcome. You have %s, 50 coal and 20 iron ore. Pick a mine at the bottom left, then click a deposit on the map. The Contracts tab has a first job waiting. Esc opens the menu to save or load." % Style.money0(state.money_cents), "info", state.day)


# ---------- building the screen ----------

func _build_ui() -> void:
    theme = Style.make_theme()
    var desk := ColorRect.new()
    desk.color = Style.DESK
    desk.set_anchors_preset(Control.PRESET_FULL_RECT)
    desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(desk)

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        margin.add_theme_constant_override(side, 10)
    add_child(margin)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 6)
    margin.add_child(root)

    top_bar = TopBar.new()
    top_bar.setup(state)
    top_bar.pause_toggled.connect(toggle_pause)
    top_bar.speed_selected.connect(set_speed)
    top_bar.next_day_pressed.connect(advance_one_day)
    top_bar.menu_requested.connect(open_menu)
    root.add_child(top_bar)

    var middle := HBoxContainer.new()
    middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
    middle.add_theme_constant_override("separation", 8)
    root.add_child(middle)

    # Left: map, inspector, build bar.
    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.add_theme_constant_override("separation", 6)
    middle.add_child(left)
    var map_panel := PanelContainer.new()
    map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_panel.add_theme_stylebox_override("panel", Style.box(Style.PAPER_LIGHT, Style.INK, 1, 3, 4))
    left.add_child(map_panel)
    map_view = MapView.new()
    map_view.setup(state)
    map_view.tile_clicked.connect(map_clicked)
    map_view.cancel_requested.connect(clear_tool)
    map_panel.add_child(map_view)
    inspector = Inspector.new()
    inspector.setup(state)
    left.add_child(inspector)
    build_bar = BuildBar.new()
    build_bar.setup(state)
    build_bar.tool_selected.connect(set_tool)
    left.add_child(build_bar)

    # Right: tabs.
    tabs = TabContainer.new()
    tabs.custom_minimum_size = Vector2(452, 0)
    middle.add_child(tabs)
    market_panel = MarketPanel.new()
    market_panel.name = "Market"
    market_panel.setup(state)
    market_panel.changed.connect(refresh_all)
    market_panel.message.connect(log_message)
    tabs.add_child(market_panel)
    production_panel = ProductionPanel.new()
    production_panel.name = "Production"
    production_panel.setup(state)
    production_panel.locate.connect(locate_tile)
    tabs.add_child(production_panel)
    contracts_panel = ContractsPanel.new()
    contracts_panel.name = "Contracts"
    contracts_panel.setup(state)
    contracts_panel.changed.connect(refresh_all)
    contracts_panel.message.connect(log_message)
    tabs.add_child(contracts_panel)
    news_panel = NewsPanel.new()
    news_panel.name = "News"
    news_panel.setup(state)
    tabs.add_child(news_panel)

    event_log = EventLog.new()
    event_log.setup()
    root.add_child(event_log)

    # The menu goes last so it sits on top of everything.
    menu = GameMenu.new()
    menu.setup()
    menu.resume_requested.connect(close_menu)
    menu.save_requested.connect(save_game)
    menu.load_requested.connect(load_game)
    menu.new_game_requested.connect(new_game)
    menu.quit_requested.connect(func() -> void: get_tree().quit())
    add_child(menu)


# ---------- menu, saving and loading ----------

func open_menu() -> void:
    menu.save_dir = save_dir
    menu.open(state.day > 1 or not state.buildings.is_empty())


func close_menu() -> void:
    menu.close()


func handle_escape() -> void:
    if menu.visible:
        close_menu()
    elif tool_id != "":
        clear_tool()
    else:
        open_menu()


func save_game(slot: String) -> void:
    var err: int = SaveManager.save(state, slot, save_dir)
    if err == OK:
        log_message("Saved to %s (day %d)." % [SaveManager.label(slot), state.day], "good")
        menu.show_message("Saved to %s." % SaveManager.label(slot), true)
    else:
        log_message("Saving failed (error %d)." % err, "bad")
        menu.show_message("Could not save (error %d). Is the disk full or read-only?" % err, false)


func load_game(slot: String) -> void:
    var r: Dictionary = SaveManager.restore(state.data, slot, save_dir)
    if not r["ok"]:
        menu.show_message("Could not load %s: %s" % [SaveManager.label(slot), SaveManager.reason_text(str(r["reason"]))], false)
        return
    _replace_state(r["state"])
    log_message("Loaded %s (day %d)." % [SaveManager.label(slot), state.day], "good")


func new_game() -> void:
    _replace_state(GameState.new(state.data, int(Time.get_unix_time_from_system())))
    _welcome()


## Swaps in a different game and rebuilds every screen around it.
func _replace_state(new_state) -> void:
    state = new_state
    for c in get_children():
        remove_child(c)
        c.queue_free()
    tool_id = ""
    running = false
    acc = 0.0
    was_negative = state.money_cents < 0
    _build_ui()
    refresh_all()


# ---------- commands from the interface ----------

func log_message(text: String, kind: String = "info") -> void:
    event_log.add(text, kind, state.day)


func set_tool(id: String) -> void:
    tool_id = id
    map_view.tool_id = id
    inspector.tool_id = id
    build_bar.select_tool(id)
    map_view.queue_redraw()
    inspector.refresh()


func clear_tool() -> void:
    set_tool("")


func map_clicked(x: int, y: int) -> void:
    if tool_id != "":
        var r: Dictionary = state.build(tool_id, x, y)
        var name_text: String = str(state.data["buildings"][tool_id]["name"])
        if r["ok"]:
            log_message("Built %s at (%d, %d) for %s." % [name_text, x, y, Style.money(int(r["cost"]))], "good")
        elif r["reason"] == "insufficient_funds":
            log_message("Cannot build %s: it costs %s." % [name_text, Style.money(int(r["cost"]))], "warn")
        else:
            log_message("Cannot build %s there: %s" % [name_text, Inspector.reason_text(str(r["reason"]))], "warn")
    select_tile(x, y)


func select_tile(x: int, y: int) -> void:
    map_view.selected = Vector2i(x, y)
    inspector.selected = Vector2i(x, y)
    refresh_all()


func locate_tile(x: int, y: int) -> void:
    select_tile(x, y)


func toggle_pause() -> void:
    running = not running
    refresh_all()


func set_speed(s: int) -> void:
    speed = s
    refresh_all()


func advance_one_day() -> void:
    state.advance_day()
    _after_day()
    refresh_all()


func _after_day() -> void:
    _log_day()
    var every: int = int(state.data["balance"]["autosave_every_days"])
    if every > 0 and state.day % every == 0:
        if SaveManager.save(state, SaveManager.AUTOSAVE, save_dir) == OK:
            log_message("Autosaved.", "info")
        else:
            log_message("Autosave failed.", "warn")


## Used by the screenshot tool: takes the first offer on the board.
func accept_offer_for_test() -> void:
    if not state.board.is_empty():
        contracts_panel.accept(int(state.board[0]["id"]))


# ---------- the clock ----------

func _process(delta: float) -> void:
    if not running or menu.visible:
        return
    acc += delta * speed
    var day_len: float = float(state.data["balance"]["day_seconds"])
    var advanced: bool = false
    while acc >= day_len:
        acc -= day_len
        state.advance_day()
        _after_day()
        advanced = true
    if advanced:
        refresh_all()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            handle_escape()
            return
        if menu.visible:
            return
        match event.keycode:
            KEY_SPACE:
                toggle_pause()
            KEY_1:
                set_speed(1)
            KEY_2:
                set_speed(2)
            KEY_3:
                set_speed(4)
            KEY_N:
                advance_one_day()


## Turns what the simulation reported today into log lines.
func _log_day() -> void:
    var res: Dictionary = state.data["resources"]
    var defs: Dictionary = state.data["buildings"]
    var clients: Dictionary = state.data["contracts"]["clients"]
    _log_market_events()
    for e in state.events:
        var name_text: String = str(defs[e["type"]]["name"])
        match str(e["kind"]):
            "paused":
                log_message("%s at (%d, %d) is paused: missing %s." % [name_text, int(e["x"]), int(e["y"]), Style.names_text(e["missing"], res)], "warn")
            "resumed":
                log_message("%s at (%d, %d) is running again." % [name_text, int(e["x"]), int(e["y"])], "good")
            "depleted":
                log_message("%s at (%d, %d): the deposit is exhausted." % [name_text, int(e["x"]), int(e["y"])], "warn")
    for n in state.news:
        var client: String = str(clients[n["client"]]["name"])
        var item: String = str(res[n["resource"]]["name"]).to_lower()
        match str(n["kind"]):
            "failed":
                log_message("Contract failed: %s, %d %s short. Penalty %s." % [client, int(n["missing"]), item, Style.money(int(n["penalty"]))], "bad")
            "expired":
                log_message("The offer from %s for %s has expired." % [client, item], "info")
            "offer":
                log_message("New offer from %s for %s." % [client, item], "info")
    for c in state.active_contracts:
        var left: int = int(c["due_day"]) - state.day + 1
        if left == 5 or left == 2:
            log_message("%s contract due in %d days: %d of %d %s delivered." % [str(clients[c["client"]]["name"]), left, int(c["delivered"]), int(c["quantity"]), str(res[c["resource"]]["name"]).to_lower()], "warn")
    if state.money_cents < 0 and not was_negative:
        log_message("You are out of cash. Upkeep keeps running: sell something.", "bad")
    was_negative = state.money_cents < 0


func _log_market_events() -> void:
    var res: Dictionary = state.data["resources"]
    var defs: Dictionary = state.data["events"]["events"]
    var me: Dictionary = state.market_events
    for n in state.event_news:
        var def: Dictionary = defs[n["type"]]
        match str(n["kind"]):
            "announced":
                for e in me["upcoming"]:
                    if int(e["uid"]) == int(n["uid"]):
                        log_message("%s announced. %s Prices: %s from day %d, for about %d days." % [
                            str(def["name"]), str(def["text"]), MarketEvents.effects_text(e["effects"], res),
                            int(e["start_day"]), int(e["end_day"]) - int(e["start_day"]) + 1], "warn")
            "started":
                log_message("%s has begun." % str(def["name"]), "warn")
            "ended":
                log_message("%s is over. Prices are settling back." % str(def["name"]), "info")
            "withdrawn":
                log_message("%s withdrew its offer for %s until prices settle." % [str(state.data["contracts"]["clients"][n["client"]]["name"]), str(res[n["resource"]]["name"]).to_lower()], "info")


# ---------- refreshing ----------

func refresh_all() -> void:
    top_bar.refresh(running, speed)
    market_panel.refresh()
    production_panel.refresh()
    contracts_panel.refresh()
    news_panel.refresh()
    inspector.refresh()
    build_bar.refresh()
    map_view.queue_redraw()
    tabs.set_tab_title(1, "Production (%d!)" % production_panel.attention_count if production_panel.attention_count > 0 else "Production")
    tabs.set_tab_title(2, "Contracts (%d)" % state.board.size() if not state.board.is_empty() else "Contracts")
    tabs.set_tab_title(3, "News (%d)" % news_panel.count if news_panel.count > 0 else "News")
