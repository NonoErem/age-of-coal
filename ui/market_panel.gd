extends ScrollContainer
## Prices with history charts, and trading with a preview of what the trade does to the price.

const Style = preload("res://ui/style.gd")
const Sparkline = preload("res://ui/sparkline.gd")
const MarketEvents = preload("res://sim/market_events.gd")
const Companies = preload("res://sim/companies.gd")
const ArtLibrary = preload("res://game/art_library.gd")

signal changed()
signal message(text: String, kind: String)

var state
var selected_id: String = "coal"
var rows: Dictionary = {}
var detail_title: Label
var detail_sub: Label
var detail_share: Label
var detail_event: Label
var big_chart
var qty_box: SpinBox
var buy_preview: Label
var sell_preview: Label
var buy_button: Button
var sell_button: Button


func setup(p_state) -> void:
    state = p_state
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 2)
    add_child(box)

    box.add_child(_header_row())
    for id in state.data["resources"]:
        var row: PanelContainer = _make_row(id)
        box.add_child(row)

    box.add_child(HSeparator.new())
    detail_title = Label.new()
    detail_title.add_theme_font_size_override("font_size", 16)
    box.add_child(detail_title)
    detail_sub = Label.new()
    detail_sub.add_theme_font_size_override("font_size", 12)
    detail_sub.add_theme_color_override("font_color", Style.INK_SOFT)
    box.add_child(detail_sub)
    detail_share = Label.new()
    detail_share.add_theme_font_size_override("font_size", 12)
    detail_share.mouse_filter = Control.MOUSE_FILTER_STOP
    box.add_child(detail_share)
    detail_event = Label.new()
    detail_event.add_theme_font_size_override("font_size", 12)
    detail_event.add_theme_color_override("font_color", Style.WARN)
    detail_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail_event.visible = false
    box.add_child(detail_event)
    big_chart = Sparkline.new()
    big_chart.show_labels = true
    big_chart.custom_minimum_size = Vector2(0, 58)
    box.add_child(big_chart)

    var trade := HBoxContainer.new()
    trade.add_theme_constant_override("separation", 4)
    box.add_child(trade)
    qty_box = SpinBox.new()
    qty_box.min_value = 1
    qty_box.max_value = 10000
    qty_box.value = 10
    qty_box.custom_minimum_size = Vector2(86, 0)
    qty_box.value_changed.connect(func(_v: float) -> void: _update_preview())
    trade.add_child(qty_box)
    for n in [1, 10, 50, 100]:
        var q := Button.new()
        q.text = str(n)
        q.pressed.connect(func() -> void: qty_box.value = n)
        trade.add_child(q)
    buy_button = Button.new()
    buy_button.text = "Buy"
    buy_button.custom_minimum_size = Vector2(56, 0)
    buy_button.pressed.connect(_on_buy)
    trade.add_child(buy_button)
    sell_button = Button.new()
    sell_button.text = "Sell"
    sell_button.custom_minimum_size = Vector2(56, 0)
    sell_button.pressed.connect(_on_sell)
    trade.add_child(sell_button)

    buy_preview = Label.new()
    buy_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    buy_preview.add_theme_font_size_override("font_size", 12)
    box.add_child(buy_preview)
    sell_preview = Label.new()
    sell_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    sell_preview.add_theme_font_size_override("font_size", 12)
    box.add_child(sell_preview)
    refresh()


func _cell(width: int, align: int = HORIZONTAL_ALIGNMENT_RIGHT, size: int = 13) -> Label:
    var l := Label.new()
    l.custom_minimum_size = Vector2(width, 0)
    l.horizontal_alignment = align
    l.clip_text = true
    l.add_theme_font_size_override("font_size", size)
    return l


func _header_row() -> Control:
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", 6)
    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(20, 0)
    h.add_child(spacer)
    var cols: Array = [["Resource", 88, HORIZONTAL_ALIGNMENT_LEFT], ["Stock", 34, HORIZONTAL_ALIGNMENT_RIGHT], ["Buy", 58, HORIZONTAL_ALIGNMENT_RIGHT], ["Sell", 58, HORIZONTAL_ALIGNMENT_RIGHT], ["Last 120 days", 64, HORIZONTAL_ALIGNMENT_CENTER], ["5 days", 46, HORIZONTAL_ALIGNMENT_RIGHT]]
    for c in cols:
        var l: Label = _cell(int(c[1]), int(c[2]), 11)
        l.text = str(c[0])
        l.add_theme_color_override("font_color", Style.INK_SOFT)
        h.add_child(l)
    return h


func _make_row(id: String) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    panel.gui_input.connect(func(ev: InputEvent) -> void:
        if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
            select_resource(id))
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", 6)
    panel.add_child(h)
    h.add_child(Style.icon_rect(ArtLibrary.resource_icon(id, 20), 20, Color.html(str(state.data["resources"][id]["color"]))))
    var name_l: Label = _cell(88, HORIZONTAL_ALIGNMENT_LEFT)
    name_l.text = str(state.data["resources"][id]["name"])
    h.add_child(name_l)
    var stock_l: Label = _cell(34)
    h.add_child(stock_l)
    var buy_l: Label = _cell(58)
    h.add_child(buy_l)
    var sell_l: Label = _cell(58)
    h.add_child(sell_l)
    var spark = Sparkline.new()
    spark.custom_minimum_size = Vector2(64, 22)
    h.add_child(spark)
    var chg_l: Label = _cell(46)
    h.add_child(chg_l)
    rows[id] = {"panel": panel, "name": name_l, "stock": stock_l, "buy": buy_l, "sell": sell_l, "spark": spark, "change": chg_l}
    return panel


func select_resource(id: String) -> void:
    selected_id = id
    refresh()


func refresh() -> void:
    for id in rows:
        var r: Dictionary = rows[id]
        var hist: Array = state.history.get(id, [])
        var touching: Array = MarketEvents.touching(state, id)
        var res_name: String = str(state.data["resources"][id]["name"])
        r["name"].text = res_name + (" !" if not touching.is_empty() else "")
        r["name"].add_theme_color_override("font_color", Style.WARN if not touching.is_empty() else Style.INK)
        var tip: Array = []
        for t in touching:
            tip.append(_event_line(t["event"], t["status"], id))
        r["panel"].tooltip_text = "\n".join(tip)
        r["stock"].text = str(state.stock(id))
        r["buy"].text = Style.money(state.market.quote_buy(id, 1))
        r["sell"].text = Style.money(state.market.quote_sell(id, 1))
        r["spark"].set_data(hist, state.market.base_price(id))
        var pct: float = 0.0
        if hist.size() >= 6:
            pct = (float(hist[-1]) / float(hist[-6]) - 1.0) * 100.0
        r["change"].text = "%+.1f%%" % pct
        r["change"].add_theme_color_override("font_color", Style.GOOD if pct > 0.5 else (Style.BAD if pct < -0.5 else Style.INK_SOFT))
        var selected: bool = id == selected_id
        r["panel"].add_theme_stylebox_override("panel", Style.box(Style.PAPER_DEEP if selected else Style.PAPER, Style.SELECT if selected else Style.PAPER, 2 if selected else 1, 3, 1))
    var id2: String = selected_id
    var name_text: String = str(state.data["resources"][id2]["name"])
    var m = state.market
    detail_title.text = "%s: %s" % [name_text, Style.money(int(m.spot_price(id2)))]
    detail_sub.text = "Base %s. Trend x%.2f. Pressure x%.2f. Depth %d." % [
        Style.money(int(m.base_price(id2))), float(m.trend[id2]), float(m.pressure[id2]), int(m.depth(id2))]
    detail_sub.tooltip_text = "Trend: the slow market drift. Pressure: below 1 means your own sales have pushed the price down; it recovers by 10% of the gap each day. Depth: how many units the market absorbs before the price moves a lot."
    detail_sub.mouse_filter = Control.MOUSE_FILTER_STOP
    var share_pct: float = m.share(id2) * 100.0
    var strength: float = m.impact_factor(id2) * 100.0
    detail_share.text = "You are %.1f%% of this market, so your trades move the price at %d%% strength." % [share_pct, int(round(strength))]
    detail_share.add_theme_color_override("font_color", Style.INK_SOFT if strength < 50.0 else Style.WARN)
    detail_share.tooltip_text = "The market trades %d units of this a day. Your presence is what you produce beyond your own needs plus what you trade, averaged over about 10 days. A small company barely moves prices. At a quarter of the market you move them at full strength." % int(m.market_volume(id2))
    var lines: Array = []
    for t in MarketEvents.touching(state, id2):
        lines.append(_event_line(t["event"], t["status"], id2))
    if lines.size() > 2:
        lines = [lines[0], "and %d more, see the News tab" % (lines.size() - 1)]
    var rival_pct: int = int(round((float(m.rival_mult[id2]) - 1.0) * 100.0))
    var troubled: Array = Companies.troubled_for(state, id2)
    if not troubled.is_empty() and abs(rival_pct) >= 1:
        var names: Array = []
        for t in troubled:
            names.append("%s (%s)" % [str(state.data["companies"]["list"][t["company"]]["name"]), str(t["status"])])
        lines.append("Rival trouble moves this price %+d%%: %s." % [rival_pct, ", ".join(names)])
    detail_event.visible = not lines.is_empty()
    detail_event.text = "\n".join(lines)
    big_chart.set_data(state.history.get(id2, []), m.base_price(id2))
    _update_preview()


func _event_line(e: Dictionary, status: String, id: String) -> String:
    var def: Dictionary = state.data["events"]["events"][e["type"]]
    var pct: int = int(round((float(e["effects"][id]) - 1.0) * 100.0))
    if status == "active":
        return "%s: %+d%%, until day %d" % [str(def["name"]), pct, int(e["end_day"])]
    return "%s: %+d%%, starts day %d" % [str(def["name"]), pct, int(e["start_day"])]


func _update_preview() -> void:
    var id: String = selected_id
    var qty: int = int(qty_box.value)
    var m = state.market
    var p0: float = float(m.pressure[id])

    var cost: int = m.quote_buy(id, qty)
    var up: float = (m.pressure_after(id, qty, true) / p0 - 1.0) * 100.0
    var has_room: bool = qty <= state.free_space()
    var can_buy: bool = cost <= state.money_cents and has_room
    var why_not: String = ""
    if not has_room:
        why_not = ". No room: only %d free (warehouses add more)" % state.free_space()
    elif cost > state.money_cents:
        why_not = ". Not enough cash"
    buy_preview.text = "Buy %d: %s (avg %s), price rises %.1f%%%s" % [qty, Style.money(cost), Style.money(int(float(cost) / qty)), up, why_not]
    buy_preview.add_theme_color_override("font_color", Style.INK_SOFT if can_buy else Style.BAD)
    buy_button.disabled = not can_buy

    var held: int = state.stock(id)
    var revenue: int = m.quote_sell(id, qty)
    var down: float = (1.0 - m.pressure_after(id, qty, false) / p0) * 100.0
    var can_sell: bool = qty <= held
    sell_preview.text = "Sell %d: +%s (avg %s), price falls %.1f%%%s" % [qty, Style.money(revenue), Style.money(int(float(revenue) / qty)), down, "" if can_sell else ". You only hold %d" % held]
    sell_preview.add_theme_color_override("font_color", Style.INK_SOFT if can_sell else Style.BAD)
    sell_button.disabled = not can_sell


func _on_buy() -> void:
    var qty: int = int(qty_box.value)
    var r: Dictionary = state.buy(selected_id, qty)
    if r["ok"]:
        message.emit("Bought %d %s for %s." % [qty, str(state.data["resources"][selected_id]["name"]).to_lower(), Style.money(int(r["cost"]))], "info")
    else:
        message.emit("Cannot buy: %s" % str(r["reason"]), "warn")
    changed.emit()


func _on_sell() -> void:
    var qty: int = int(qty_box.value)
    var r: Dictionary = state.sell(selected_id, qty)
    if r["ok"]:
        message.emit("Sold %d %s for %s." % [qty, str(state.data["resources"][selected_id]["name"]).to_lower(), Style.money(int(r["revenue"]))], "info")
    else:
        message.emit("Cannot sell: %s" % str(r["reason"]), "warn")
    changed.emit()
