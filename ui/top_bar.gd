extends PanelContainer
## Day, cash, upkeep and the time controls.

const Style = preload("res://ui/style.gd")
const Production = preload("res://sim/production.gd")
const Crisis = preload("res://sim/crisis.gd")
const People = preload("res://sim/people.gd")

signal pause_toggled()
signal speed_selected(speed: int)
signal next_day_pressed()
signal menu_requested()

var state
var day_label: Label
var money_label: Label
var upkeep_label: Label
var storage_label: Label
var people_label: Label
var play_button: Button
var speed_buttons: Dictionary = {}


func setup(p_state) -> void:
    state = p_state
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    add_child(row)

    var title := Label.new()
    title.text = "IRON & COAL"
    title.add_theme_font_size_override("font_size", 18)
    row.add_child(title)

    day_label = Label.new()
    day_label.add_theme_font_size_override("font_size", 18)
    row.add_child(day_label)

    money_label = Label.new()
    money_label.add_theme_font_size_override("font_size", 22)
    money_label.tooltip_text = "Cash on hand"
    row.add_child(money_label)

    upkeep_label = Label.new()
    upkeep_label.add_theme_color_override("font_color", Style.INK_SOFT)
    upkeep_label.tooltip_text = "What your buildings cost every day in their current state"
    row.add_child(upkeep_label)

    storage_label = Label.new()
    row.add_child(storage_label)

    people_label = Label.new()
    people_label.mouse_filter = Control.MOUSE_FILTER_PASS
    people_label.add_theme_font_size_override("font_size", 14)
    storage_label.add_theme_font_size_override("font_size", 14)
    upkeep_label.add_theme_font_size_override("font_size", 14)
    row.add_child(people_label)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(spacer)

    play_button = Button.new()
    play_button.custom_minimum_size = Vector2(76, 0)
    play_button.tooltip_text = "Play / pause (Space)"
    play_button.pressed.connect(func() -> void: pause_toggled.emit())
    row.add_child(play_button)

    var group := ButtonGroup.new()
    for s in [1, 2, 4]:
        var b := Button.new()
        b.text = "%dx" % s
        b.toggle_mode = true
        b.button_group = group
        b.custom_minimum_size = Vector2(40, 0)
        b.tooltip_text = "Speed %dx (key %d)" % [s, [1, 2, 4].find(s) + 1]
        b.pressed.connect(func() -> void: speed_selected.emit(s))
        speed_buttons[s] = b
        row.add_child(b)

    var next := Button.new()
    next.text = "Next day"
    next.tooltip_text = "Advance one day (N)"
    next.pressed.connect(func() -> void: next_day_pressed.emit())
    row.add_child(next)

    var menu := Button.new()
    menu.text = "Menu"
    menu.tooltip_text = "Save, load, new game (Esc)"
    menu.pressed.connect(func() -> void: menu_requested.emit())
    row.add_child(menu)


func refresh(running: bool, speed: int) -> void:
    day_label.text = "Day %d" % state.day
    money_label.text = Style.money(state.money_cents)
    money_label.add_theme_color_override("font_color", Style.BAD if state.money_cents < 0 else Style.INK)
    upkeep_label.text = "Upkeep %s/day" % Style.money0(Production.current_upkeep(state))
    upkeep_label.tooltip_text = "What your buildings cost every day in their current state: upkeep of the machines, and wages of the hired workers"
    if Crisis.landed(state) and not state.buildings.is_empty():
        var full: int = 0
        var idle_f: float = float(state.data["balance"]["idle_upkeep_factor"])
        for ub in state.buildings:
            full += Production.upkeep_of(state.data["buildings"][ub["type"]], str(ub["status"]), idle_f)
        var now: int = Production.current_upkeep(state)
        if full > now:
            upkeep_label.tooltip_text += "\nYour people work for food, and hired hands for less where your defenses keep them safe: %s a day saved (%d%%)" % [Style.money0(full - now), int(round(100.0 * float(full - now) / float(full)))]
    var pt: Dictionary = People.totals(state)
    var short: int = int(pt["needed"]) - int(pt["yours"]) - int(pt["hired"])
    var ptext: String = "Hired %d" % int(pt["hired"])
    if int(pt["housing"]) > 0 or state.people > 0:
        ptext = "People %d/%d · %s" % [state.people, int(pt["housing"]), ptext]

    if state.people > 0:
        ptext += " · Food %dd" % People.food_days(state)
    elif state.food_stored() > 0 or state.food_capacity() > 0:
        ptext += " · Food %d" % state.food_stored()
    people_label.text = ptext
    var hungry: bool = state.people > 0 and People.food_days(state) < 5
    people_label.add_theme_color_override("font_color", Style.BAD if hungry else (Style.WARN if short > 0 else Style.INK_SOFT))
    people_label.tooltip_text = "Your people (housed in shelters, fed with food, no wage) and hired workers (paid a wage).\nCrews: %d needed, %d of your people working, %d hired%s.\nFood: %d of %d in granaries%s." % [int(pt["needed"]), int(pt["yours"]), int(pt["hired"]), (", %d places empty: buildings work in proportion" % short) if short > 0 else "", state.food_stored(), state.food_capacity(), (", %s a day eaten" % str(snappedf(People.daily_ration(state), 0.1))) if state.people > 0 else ""]
    var used: int = state.stored_units()
    var cap: int = state.capacity()
    storage_label.text = "Store %d/%d" % [used, cap]
    var ratio: float = float(used) / float(maxi(1, cap))
    storage_label.add_theme_color_override("font_color", Style.BAD if ratio >= 1.0 else (Style.WARN if ratio >= 0.9 else Style.INK_SOFT))
    storage_label.tooltip_text = "Units in store out of the room you have. Mines and factories stop when it is full and you cannot buy more than fits. Warehouses add room."
    play_button.text = "Pause" if running else "Play"
    if speed_buttons.has(speed):
        speed_buttons[speed].set_pressed_no_signal(true)
