extends HFlowContainer
## One button per building. Pick one, then click the map to place it.
## Press the same button again, right-click, or Esc to stop placing.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")
const Survey = preload("res://sim/survey.gd")
const Crisis = preload("res://sim/crisis.gd")

signal tool_selected(building_id: String)
signal survey_selected(level: int)

var state
var buttons: Dictionary = {}
var survey_buttons: Dictionary = {}   # level -> Button
var group: ButtonGroup
var group_labels: Array = []
const COMPACT_BELOW := 1000.0   # narrower than this: no group labels, tighter buttons


func setup(p_state) -> void:
    state = p_state
    add_theme_constant_override("h_separation", 4)
    add_theme_constant_override("v_separation", 4)
    group = ButtonGroup.new()
    group.allow_unpress = true
    var defs: Dictionary = state.data["buildings"]
    var groups: Dictionary = {"extractor": ["extractor"], "factory": ["factory"], "storage": ["storage"], "defense": ["defense", "light"], "shelter": ["shelter", "granary"]}
    for kind in ["extractor", "factory", "storage", "defense", "shelter"]:
        var label := Label.new()
        label.text = {"extractor": "Mines", "factory": "Factories", "storage": "Storage", "defense": "Defenses", "shelter": "People"}[kind]
        label.add_theme_color_override("font_color", Style.INK_SOFT)
        label.add_theme_font_size_override("font_size", 12)
        label.custom_minimum_size = Vector2(52, 0)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        group_labels.append(label)
        add_child(label)
        for id in defs:
            if not groups[kind].has(str(defs[id]["kind"])):
                continue
            var b := Button.new()
            b.toggle_mode = true
            b.button_group = group
            b.add_theme_font_size_override("font_size", 12)
            b.custom_minimum_size = Vector2(0, 42)
            b.icon = ArtLibrary.building_icon(id, 30)
            b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
            b.expand_icon = false
            b.add_theme_constant_override("h_separation", 5)
            b.toggled.connect(func(on: bool) -> void: _on_toggled(id, on))
            buttons[id] = b
            add_child(b)
    # Surveys share the group: one tool at a time.
    var slabel := Label.new()
    slabel.text = "Survey"
    slabel.add_theme_color_override("font_color", Style.INK_SOFT)
    slabel.add_theme_font_size_override("font_size", 12)
    slabel.custom_minimum_size = Vector2(52, 0)
    slabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    group_labels.append(slabel)
    add_child(slabel)
    for level in [1, 2]:
        var sb := Button.new()
        sb.toggle_mode = true
        sb.button_group = group
        sb.add_theme_font_size_override("font_size", 12)
        sb.custom_minimum_size = Vector2(0, 42)
        sb.toggled.connect(func(on: bool) -> void: survey_selected.emit(level if on else 0))
        survey_buttons[level] = sb
        add_child(sb)
    refresh()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _fit()


## On a narrow window the group labels go (the icons say enough) and the buttons get tighter.
func _fit() -> void:
    var compact: bool = size.x > 0.0 and size.x < COMPACT_BELOW
    for l in group_labels:
        l.visible = not compact
    var all: Array = buttons.values() + survey_buttons.values()
    for b in all:
        b.add_theme_font_size_override("font_size", 11 if compact else 12)
        b.add_theme_constant_override("h_separation", 2 if compact else 5)
    add_theme_constant_override("h_separation", 2 if compact else 4)


func _on_toggled(id: String, on: bool) -> void:
    tool_selected.emit(id if on else "")


func clear_tool() -> void:
    for id in buttons:
        buttons[id].set_pressed_no_signal(false)
    for level in survey_buttons:
        survey_buttons[level].set_pressed_no_signal(false)


func select_survey(level: int) -> void:
    clear_tool()
    if survey_buttons.has(level):
        survey_buttons[level].set_pressed_no_signal(true)


func select_tool(id: String) -> void:
    clear_tool()
    if buttons.has(id):
        buttons[id].set_pressed_no_signal(true)


func _refresh_surveys() -> void:
    var radius: int = int(state.data["map"]["survey"]["radius"])
    var side: int = radius * 2 + 1
    for level in survey_buttons:
        var b: Button = survey_buttons[level]
        var cost: int = Survey.cost(state, level)
        b.text = "%s\n%s" % [Survey.level_name(state, level), Style.money0(cost)]
        var deepest: String = "ore just under the surface" if level == 1 else "ore at every depth, the deepest and richest too"
        b.tooltip_text = "%s\nCost %s, paid whatever is found.\nSurveys a %d by %d area around the tile you click and reveals %s.\nRevealed deposits are used like any other: pay the land, build a mine." % [Survey.level_name(state, level), Style.money0(cost), side, side, deepest]
        var col: Color = Style.INK if cost <= state.money_cents else Style.BAD
        for k in ["font_color", "font_hover_color", "font_pressed_color"]:
            b.add_theme_color_override(k, col)


func refresh() -> void:
    _refresh_surveys()
    var defs: Dictionary = state.data["buildings"]
    var res: Dictionary = state.data["resources"]
    var idle: float = float(state.data["balance"]["idle_upkeep_factor"])
    for id in buttons:
        var def: Dictionary = defs[id]
        var cost: int = state.build_cost(id)
        var b: Button = buttons[id]
        b.text = "%s\n%s" % [str(def.get("short_name", def["name"])), Style.money0(cost)]
        var tip: Array = [str(def["name"])]
        tip.append("Cost %s (+%d%% for each you already own), plus the land price on a deposit" % [Style.money0(cost), int(round(float(state.data["balance"]["cost_growth_per_owned"]) * 100.0))])
        if int(def.get("crew", 0)) > 0:
            tip.append("Needs a crew of %d. Short of workers, it works in proportion" % int(def["crew"]))
        if Crisis.enabled(state):
            tip.append("Once the creatures land, hired labour gets cheaper on ground your supplied defenses protect, but fewer come every year")
        tip.append("Upkeep %s a day (%s when idle)" % [Style.money(int(def["upkeep_per_day"])), Style.money(int(round(float(def["upkeep_per_day"]) * idle)))])
        if def["kind"] == "defense":
            tip.append("Fires at the nearest creature within %d tiles: %d damage a day" % [int(def["range"]), int(def["damage"])])
            tip.append("Uses %s on each day it fires. No ammunition, no fire" % Style.items_text(def.get("ammo", {}), res))
            tip.append("%d health. Keeps firing while damaged" % int(def.get("health", 150)))
            tip.append("Goes on free ground. Put it where the creatures will come")
        elif def["kind"] == "shelter":
            tip.append("Houses %d of your people once the creatures have landed. They work for food, with no wage" % int(def["housing"]))
            tip.append("Refugees only come and stay where a supplied defense reaches the shelter, and while you have food")
            tip.append("Each person eats %s food a day, from your granaries" % str(float(state.data["balance"]["people"]["ration"])))
            tip.append("%d health. Goes on free ground" % int(def.get("health", 110)))
        elif def["kind"] == "granary":
            tip.append("Keeps %d food. Food keeps nowhere else, and spoils a little every day (%s%%)" % [int(def["food_capacity"]), str(float(state.data["balance"]["people"]["spoil_per_day"]) * 100.0)])
            tip.append("Goes on free ground")
        elif def["kind"] == "light":
            tip.append("Lights every defense within %d tiles, so they aim as well at night as by day" % int(def["range"]))
            tip.append("In the dark, unlit defenses hit up to %d%% less. Burns %s a night" % [int(round(float(state.data["crisis"].get("darkness", {}).get("max_penalty", 0.0)) * 100.0)), Style.items_text(def.get("supplies", {}), res)])
            tip.append("%d health. Goes on free ground" % int(def.get("health", 120)))
        elif def["kind"] == "storage":
            tip.append("Adds room for %d more units of anything" % int(def["capacity"]))
            tip.append("Goes on free ground")
        elif def["kind"] == "extractor":
            tip.append("Makes %s a day, times the deposit's richness" % Style.items_text(def["outputs"], res))
            tip.append("Goes on a %s deposit" % str(res[def["deposit"]]["name"]).to_lower())
        else:
            tip.append("Each batch turns %s into %s" % [Style.items_text(def["inputs"], res), Style.items_text(def["outputs"], res)])
            tip.append("Up to %d batches a day. Paused, never removed, when inputs run out" % int(def.get("batches_per_day", 1)))
            tip.append("Goes on free ground")
        if def.get("placeholder", false):
            tip.append("(placeholder numbers, to be confirmed)")
        b.tooltip_text = "\n".join(tip)
        b.add_theme_color_override("font_color", Style.INK if cost <= state.money_cents else Style.BAD)
        b.add_theme_color_override("font_hover_color", Style.INK if cost <= state.money_cents else Style.BAD)
        b.add_theme_color_override("font_pressed_color", Style.INK if cost <= state.money_cents else Style.BAD)
