extends ScrollContainer
## Standing orders: sell or buy the same amount every day for a number of days. The form stays put
## (it is built once), only the list of running orders is rebuilt.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")

signal changed()
signal message(text: String, kind: String)

var state
var box: VBoxContainer
var side_pick: OptionButton
var res_pick: OptionButton
var qty_box: SpinBox
var days_box: SpinBox
var limit_box: SpinBox
var limit_label: Label
var preview: Label
var start_button: Button
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

    var h1 := Label.new()
    h1.text = "New standing order"
    h1.add_theme_font_size_override("font_size", 15)
    box.add_child(h1)
    var hint := _label("The same amount every day, at market prices. Start one whenever you like.", 12, Style.INK_SOFT)
    box.add_child(hint)

    var row1 := HBoxContainer.new()
    row1.add_theme_constant_override("separation", 6)
    box.add_child(row1)
    side_pick = OptionButton.new()
    side_pick.add_item("Sell")
    side_pick.add_item("Buy")
    side_pick.item_selected.connect(func(_i: int) -> void: _update_preview())
    row1.add_child(side_pick)
    res_pick = OptionButton.new()
    res_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var resources: Dictionary = state.data["resources"]
    for id in resources:
        resource_ids.append(id)
        res_pick.add_item(str(resources[id]["name"]))
    res_pick.item_selected.connect(func(_i: int) -> void: _update_preview())
    row1.add_child(res_pick)

    var cfg: Dictionary = state.data["contracts"]["standing"]
    var row2 := HBoxContainer.new()
    row2.add_theme_constant_override("separation", 6)
    box.add_child(row2)
    row2.add_child(_inline("Each day"))
    qty_box = SpinBox.new()
    qty_box.min_value = 1
    qty_box.max_value = int(cfg["max_qty_per_day"])
    qty_box.value = 20
    qty_box.custom_minimum_size = Vector2(90, 0)
    qty_box.value_changed.connect(func(_v: float) -> void: _update_preview())
    row2.add_child(qty_box)
    row2.add_child(_inline("for"))
    days_box = SpinBox.new()
    days_box.min_value = 1
    days_box.max_value = int(cfg["max_days"])
    days_box.value = 30
    days_box.custom_minimum_size = Vector2(90, 0)
    days_box.value_changed.connect(func(_v: float) -> void: _update_preview())
    row2.add_child(days_box)
    row2.add_child(_inline("days"))

    var row3 := HBoxContainer.new()
    row3.add_theme_constant_override("separation", 6)
    box.add_child(row3)
    limit_label = _label("", 12, Style.INK_SOFT)
    limit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row3.add_child(limit_label)
    limit_box = SpinBox.new()
    limit_box.min_value = 0
    limit_box.max_value = 100000
    limit_box.step = 0.05
    limit_box.value = 0
    limit_box.prefix = "$"
    limit_box.custom_minimum_size = Vector2(110, 0)
    limit_box.tooltip_text = "0 means no limit. Otherwise a day is skipped when the average price would be on the wrong side of it."
    limit_box.value_changed.connect(func(_v: float) -> void: _update_preview())
    row3.add_child(limit_box)

    preview = _label("", 12, Style.INK)
    box.add_child(preview)
    start_button = Button.new()
    start_button.text = "Start order"
    start_button.pressed.connect(start_pressed)
    box.add_child(start_button)

    box.add_child(HSeparator.new())
    list_heading = Label.new()
    list_heading.add_theme_font_size_override("font_size", 15)
    box.add_child(list_heading)
    list_box = VBoxContainer.new()
    list_box.add_theme_constant_override("separation", 6)
    box.add_child(list_box)
    box.add_child(_label("Orders trade at the market price with the usual spread, fee and price impact, so they save effort, not money. A day with no stock, room or cash, or with the price outside your limit, is lost.", 12, Style.INK_SOFT))
    refresh()


func _label(text: String, size: int = 13, color: Color = Style.INK) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l


## A short label that never wraps, for use next to input fields.
func _inline(text: String) -> Label:
    var l: Label = _label(text, 13)
    l.autowrap_mode = TextServer.AUTOWRAP_OFF
    return l


func side() -> String:
    return "sell" if side_pick.selected == 0 else "buy"


func resource_id() -> String:
    return str(resource_ids[res_pick.selected])


func limit_cents() -> int:
    return int(round(limit_box.value * 100.0))


func _res_name(id: String) -> String:
    return str(state.data["resources"][id]["name"]).to_lower()


func start_pressed() -> void:
    var r: Dictionary = state.start_standing_order(resource_id(), side(), int(qty_box.value), int(days_box.value), limit_cents())
    if r["ok"]:
        message.emit("Standing order started: %s %d %s a day for %d days." % [side(), int(qty_box.value), _res_name(resource_id()), int(days_box.value)], "good")
    elif r["reason"] == "too_many_orders":
        message.emit("You can run %d standing orders at once. Cancel one first." % int(state.data["contracts"]["standing"]["max_orders"]), "warn")
    else:
        message.emit("Cannot start the order: %s" % str(r["reason"]), "warn")
    changed.emit()


func cancel(id: int) -> void:
    var r: Dictionary = state.cancel_standing_order(id)
    if r["ok"]:
        message.emit("Standing order cancelled after %d units." % int(r["units_done"]), "info")
    changed.emit()


## What each result means, for the list and the log.
static func result_text(result: String) -> String:
    match result:
        "partial_stock": return "only part was sold: you ran short of stock"
        "no_stock": return "nothing was sold: you have none"
        "partial_room": return "only part was bought: storage is full"
        "no_room": return "nothing was bought: storage is full"
        "partial_money": return "only part was bought: not enough cash"
        "no_money": return "nothing was bought: not enough cash"
        "price": return "skipped: the price was outside your limit"
        "failed": return "it could not trade"
    return ""


func _update_preview() -> void:
    var selling: bool = side() == "sell"
    limit_label.text = "Only if the average price is at least:" if selling else "Only if the average price is at most:"
    var id: String = resource_id()
    var qty: int = int(qty_box.value)
    var days: int = int(days_box.value)
    var name_text: String = _res_name(id)
    var total: int = state.market.quote_sell(id, qty) if selling else state.market.quote_buy(id, qty)
    var lines: Array = ["%s %d %s a day for %d days: about %s a day at today's prices, %d %s in all." % ["Sell" if selling else "Buy", qty, name_text, days, Style.money0(total), qty * days, name_text]]
    var note: String = ""
    var warn: bool = false
    if selling:
        var held: int = state.stock(id)
        if held < qty * days:
            note = "You hold %d %s, enough for %d days at this rate. Production or purchases must cover the rest." % [held, name_text, int(held / maxi(1, qty))]
    else:
        note = "You have room for %d more units." % state.free_space()
        if qty > state.free_space():
            note += " That is less than one day's order."
            warn = true
    var lim: int = limit_cents()
    if lim > 0:
        var avg: float = float(total) / float(maxi(1, qty))
        if (selling and avg < float(lim)) or (not selling and avg > float(lim)):
            note += (" " if note != "" else "") + "Today's average price is %s, outside your limit, so it would not trade right now." % Style.money(int(avg))
            warn = true
    if note != "":
        lines.append(note)
    preview.text = "\n".join(lines)
    preview.add_theme_color_override("font_color", Style.WARN if warn else Style.INK)
    var max_orders: int = int(state.data["contracts"]["standing"]["max_orders"])
    start_button.disabled = state.standing_orders.size() >= max_orders
    start_button.tooltip_text = "You can run %d standing orders at once." % max_orders if start_button.disabled else ""


func refresh() -> void:
    _update_preview()
    var max_orders: int = int(state.data["contracts"]["standing"]["max_orders"])
    list_heading.text = "Running (%d of %d)" % [state.standing_orders.size(), max_orders]
    for c in list_box.get_children():
        list_box.remove_child(c)
        c.queue_free()
    if state.standing_orders.is_empty():
        list_box.add_child(_label("None.", 13, Style.INK_SOFT))
    for o in state.standing_orders:
        list_box.add_child(_card(o))


func _card(o: Dictionary) -> Control:
    var id: int = int(o["id"])
    var res_id: String = str(o["resource"])
    var selling: bool = o["side"] == "sell"
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 3)

    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 6)
    head.add_child(Style.icon_rect(ArtLibrary.resource_icon(res_id, 22), 22, Color.html(str(state.data["resources"][res_id]["color"]))))
    var title: Label = _label("%s %d %s a day" % ["Selling" if selling else "Buying", int(o["qty"]), _res_name(res_id)], 14)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    var cancel_button := Button.new()
    cancel_button.text = "Cancel"
    cancel_button.pressed.connect(func() -> void: cancel(id))
    head.add_child(cancel_button)
    v.add_child(head)

    var bar := ProgressBar.new()
    bar.show_percentage = false
    bar.custom_minimum_size = Vector2(0, 10)
    bar.max_value = float(o["days_total"])
    bar.value = float(int(o["days_total"]) - int(o["days_left"]))
    v.add_child(bar)

    var done: int = int(o["units_done"])
    var avg_text: String = ""
    if done > 0:
        avg_text = " (average %s)" % Style.money(int(float(o["cents"]) / float(done)))
    var progress: String = "%d days left. %s %d so far for %s%s." % [int(o["days_left"]), "Sold" if selling else "Bought", done, Style.money(int(o["cents"])), avg_text]
    if int(o["limit_cents"]) > 0:
        progress += " Limit: %s %s a unit." % ["at least" if selling else "at most", Style.money(int(o["limit_cents"]))]
    v.add_child(_label(progress, 12, Style.INK_SOFT))
    var problem: String = result_text(str(o["last_result"]))
    if problem != "":
        v.add_child(_label("Last day: %s." % problem, 12, Style.WARN))

    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", Style.box(Style.PAPER_LIGHT, Style.INK_SOFT, 1, 3, 8))
    p.add_child(v)
    return p
