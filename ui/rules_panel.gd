extends ScrollContainer
## Automation rules: "keep at least N" and "sell what is over N". They run every day until deleted.
## The form is built once; only the list of rules is rebuilt.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")
const Rules = preload("res://sim/rules.gd")

signal changed()
signal message(text: String, kind: String)

var state
var box: VBoxContainer
var kind_pick: OptionButton
var res_pick: OptionButton
var level_box: SpinBox
var limit_box: SpinBox
var limit_label: Label
var per_day_box: SpinBox
var cash_row: HBoxContainer
var cash_box: SpinBox
var preview: Label
var add_button: Button
var list_heading: Label
var list_box: VBoxContainer
var resource_ids: Array = []


func setup(p_state) -> void:
    state = p_state
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 6)
    add_child(box)
    var cfg: Dictionary = Rules.settings(state)

    var h1 := Label.new()
    h1.text = "New rule"
    h1.add_theme_font_size_override("font_size", 15)
    box.add_child(h1)
    box.add_child(_label("A rule looks at your stock every day and trades to keep it where you want it, until you delete it.", 12, Style.INK_SOFT))

    var row1 := HBoxContainer.new()
    row1.add_theme_constant_override("separation", 6)
    box.add_child(row1)
    kind_pick = OptionButton.new()
    kind_pick.add_item("Keep at least")
    kind_pick.add_item("Sell what is over")
    kind_pick.item_selected.connect(func(_i: int) -> void: _update_preview())
    row1.add_child(kind_pick)
    level_box = SpinBox.new()
    level_box.min_value = 0
    level_box.max_value = int(cfg["max_level"])
    level_box.value = 100
    level_box.custom_minimum_size = Vector2(90, 0)
    level_box.value_changed.connect(func(_v: float) -> void: _update_preview())
    row1.add_child(level_box)
    res_pick = OptionButton.new()
    res_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var resources: Dictionary = state.data["resources"]
    for id in resources:
        resource_ids.append(id)
        res_pick.add_item(str(resources[id]["name"]))
    res_pick.item_selected.connect(func(_i: int) -> void: _update_preview())
    row1.add_child(res_pick)

    var row2 := HBoxContainer.new()
    row2.add_theme_constant_override("separation", 6)
    box.add_child(row2)
    row2.add_child(_inline("At most"))
    per_day_box = SpinBox.new()
    per_day_box.min_value = 1
    per_day_box.max_value = int(cfg["max_per_day"])
    per_day_box.value = int(cfg["max_per_day"])
    per_day_box.custom_minimum_size = Vector2(90, 0)
    per_day_box.tooltip_text = "The most units the rule will trade in one day."
    per_day_box.value_changed.connect(func(_v: float) -> void: _update_preview())
    row2.add_child(per_day_box)
    row2.add_child(_inline("units a day"))

    var row3 := HBoxContainer.new()
    row3.add_theme_constant_override("separation", 6)
    box.add_child(row3)
    limit_label = _label("", 12, Style.INK_SOFT)
    limit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row3.add_child(limit_label)
    limit_box = _money_box("0 means any price. Otherwise the rule does nothing on a day when the average price is on the wrong side of it.")
    row3.add_child(limit_box)

    cash_row = HBoxContainer.new()
    cash_row.add_theme_constant_override("separation", 6)
    box.add_child(cash_row)
    var cash_label: Label = _label("Never spend below this cash:", 12, Style.INK_SOFT)
    cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cash_row.add_child(cash_label)
    cash_box = _money_box("A keep rule stops buying before your cash falls below this. 0 means it may spend down to nothing, but never into debt.")
    cash_row.add_child(cash_box)

    preview = _label("", 12, Style.INK)
    box.add_child(preview)
    add_button = Button.new()
    add_button.text = "Add rule"
    add_button.pressed.connect(add_pressed)
    box.add_child(add_button)

    box.add_child(HSeparator.new())
    list_heading = Label.new()
    list_heading.add_theme_font_size_override("font_size", 15)
    box.add_child(list_heading)
    list_box = VBoxContainer.new()
    list_box.add_theme_constant_override("separation", 6)
    box.add_child(list_box)
    box.add_child(_label("Rules trade at the market price with the usual spread, fee and price impact, so they save effort, not money. They never take you into debt, and a rule that cannot do its job tells you once in the log.", 12, Style.INK_SOFT))
    refresh()


func _money_box(tip: String) -> SpinBox:
    var b := SpinBox.new()
    b.min_value = 0
    b.max_value = 1000000
    b.step = 0.05
    b.value = 0
    b.prefix = "$"
    b.custom_minimum_size = Vector2(110, 0)
    b.tooltip_text = tip
    b.value_changed.connect(func(_v: float) -> void: _update_preview())
    return b


func _label(text: String, size: int = 13, color: Color = Style.INK) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l


func _inline(text: String) -> Label:
    var l: Label = _label(text, 13)
    l.autowrap_mode = TextServer.AUTOWRAP_OFF
    return l


func kind() -> String:
    return "keep" if kind_pick.selected == 0 else "sell_above"


func resource_id() -> String:
    return str(resource_ids[res_pick.selected])


func _res_name(id: String) -> String:
    return str(state.data["resources"][id]["name"]).to_lower()


func _cents(b: SpinBox) -> int:
    return int(round(b.value * 100.0))


func add_pressed() -> void:
    var keep: bool = kind() == "keep"
    var r: Dictionary = state.add_rule(resource_id(), kind(), int(level_box.value), _cents(limit_box), int(per_day_box.value), _cents(cash_box) if keep else 0)
    if r["ok"]:
        message.emit("Rule added: %s." % _describe(kind(), resource_id(), int(level_box.value)), "good")
    else:
        message.emit("Cannot add the rule: %s" % Rules.reason_text(str(r["reason"])), "warn")
    changed.emit()


func delete_rule(id: int) -> void:
    var r: Dictionary = state.delete_rule(id)
    if r["ok"]:
        message.emit("Rule deleted after %d units." % int(r["units_done"]), "info")
    changed.emit()


func toggle_pause(id: int, paused: bool) -> void:
    var r: Dictionary = state.pause_rule(id, paused)
    if not r["ok"]:
        message.emit("Cannot resume the rule: %s" % Rules.reason_text(str(r["reason"])), "warn")
    changed.emit()


func _sentence(t: String) -> String:
    return t.substr(0, 1).to_upper() + t.substr(1)


func _describe(k: String, res_id: String, level: int) -> String:
    if k == "keep":
        return "keep at least %d %s" % [level, _res_name(res_id)]
    if level == 0:
        return "sell all %s as it comes" % _res_name(res_id)
    return "sell %s over %d" % [_res_name(res_id), level]


func _update_preview() -> void:
    var keep: bool = kind() == "keep"
    var id: String = resource_id()
    var level: int = int(level_box.value)
    cash_row.visible = keep
    limit_label.text = "Only if the average price is at most:" if keep else "Only if the average price is at least:"
    var lines: Array = ["Every day: %s." % _sentence(_describe(kind(), id, level))]
    var held: int = state.stock(id)
    var warn: bool = false
    var note: String = ""
    if keep:
        if held < level:
            var n: int = mini(level - held, int(per_day_box.value))
            note = "You hold %d. It would buy %d today for about %s." % [held, n, Style.money0(state.market.quote_buy(id, n))]
        else:
            note = "You hold %d: nothing to buy today." % held
        if level > state.capacity():
            note += " Your storage holds %d in all, so it can never get there." % state.capacity()
            warn = true
    else:
        if held > level:
            var n2: int = mini(held - level, int(per_day_box.value))
            note = "You hold %d. It would sell %d today for about %s." % [held, n2, Style.money0(state.market.quote_sell(id, n2))]
        else:
            note = "You hold %d: nothing to sell today." % held
    lines.append(note)
    var clash: Dictionary = Rules.would_conflict(state, id, kind(), level)
    var dup: bool = false
    for r in state.rules:
        if str(r["resource"]) == id and str(r["kind"]) == kind():
            dup = true
    if dup:
        lines.append("You already have this kind of rule for %s. Delete it first." % _res_name(id))
        warn = true
    elif not clash.is_empty():
        lines.append("It would clash with your rule to %s: keeping more than you would sell buys and sells the same units every day." % _describe(str(clash["kind"]), id, int(clash["level"])))
        warn = true
    preview.text = "\n".join(lines)
    preview.add_theme_color_override("font_color", Style.WARN if warn else Style.INK)
    var max_rules: int = int(Rules.settings(state)["max_rules"])
    add_button.disabled = dup or not clash.is_empty() or state.rules.size() >= max_rules
    add_button.tooltip_text = "You can have %d rules at once." % max_rules if state.rules.size() >= max_rules else ""


func refresh() -> void:
    _update_preview()
    var max_rules: int = int(Rules.settings(state)["max_rules"])
    list_heading.text = "Rules (%d of %d)" % [state.rules.size(), max_rules]
    for c in list_box.get_children():
        list_box.remove_child(c)
        c.queue_free()
    if state.rules.is_empty():
        list_box.add_child(_label("None.", 13, Style.INK_SOFT))
    for r in state.rules:
        list_box.add_child(_card(r))


func _card(r: Dictionary) -> Control:
    var id: int = int(r["id"])
    var res_id: String = str(r["resource"])
    var keep: bool = str(r["kind"]) == "keep"
    var paused: bool = bool(r["paused"])
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 3)

    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 6)
    head.add_child(Style.icon_rect(ArtLibrary.resource_icon(res_id, 22), 22, Color.html(str(state.data["resources"][res_id]["color"]))))
    var title: Label = _label(_sentence(_describe(str(r["kind"]), res_id, int(r["level"]))) + (" (paused)" if paused else ""), 14, Style.INK_SOFT if paused else Style.INK)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    var pause_button := Button.new()
    pause_button.text = "Resume" if paused else "Pause"
    pause_button.pressed.connect(func() -> void: toggle_pause(id, not paused))
    head.add_child(pause_button)
    var del := Button.new()
    del.text = "Delete"
    del.pressed.connect(func() -> void: delete_rule(id))
    head.add_child(del)
    v.add_child(head)

    var done: int = int(r["units_done"])
    var line: String = "%s %d units so far for %s." % ["Bought" if keep else "Sold", done, Style.money(int(r["cents"]))]
    line += " Held now: %d." % state.stock(res_id)
    if int(r["per_day"]) > 0:
        line += " Up to %d a day." % int(r["per_day"])
    if int(r["limit_cents"]) > 0:
        line += " Limit: %s %s a unit." % ["at most" if keep else "at least", Style.money(int(r["limit_cents"]))]
    if keep and int(r["min_cash_cents"]) > 0:
        line += " Keeps %s in cash." % Style.money0(int(r["min_cash_cents"]))
    v.add_child(_label(line, 12, Style.INK_SOFT))
    var problem: String = Rules.result_text(str(r["last_result"]))
    if problem != "" and not paused:
        v.add_child(_label("Last day: %s." % problem, 12, Style.WARN))

    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", Style.box(Style.PAPER_LIGHT, Style.INK_SOFT, 1, 3, 8))
    p.add_child(v)
    return p
