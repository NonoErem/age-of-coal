extends HFlowContainer
## One button per building. Pick one, then click the map to place it.
## Press the same button again, right-click, or Esc to stop placing.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")
const Survey = preload("res://sim/survey.gd")

signal tool_selected(building_id: String)
signal survey_selected(level: int)

var state
var buttons: Dictionary = {}
var survey_buttons: Dictionary = {}   # level -> Button
var group: ButtonGroup


func setup(p_state) -> void:
    state = p_state
    add_theme_constant_override("h_separation", 4)
    add_theme_constant_override("v_separation", 4)
    group = ButtonGroup.new()
    group.allow_unpress = true
    var defs: Dictionary = state.data["buildings"]
    for kind in ["extractor", "factory", "storage"]:
        var label := Label.new()
        label.text = "Mines" if kind == "extractor" else ("Factories" if kind == "factory" else "Storage")
        label.add_theme_color_override("font_color", Style.INK_SOFT)
        label.add_theme_font_size_override("font_size", 12)
        label.custom_minimum_size = Vector2(52, 0)
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        add_child(label)
        for id in defs:
            if defs[id]["kind"] != kind:
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
        tip.append("Upkeep %s a day (%s when idle)" % [Style.money(int(def["upkeep_per_day"])), Style.money(int(round(float(def["upkeep_per_day"]) * idle)))])
        if def["kind"] == "storage":
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
