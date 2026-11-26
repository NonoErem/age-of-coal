extends ScrollContainer
## Offers you can take and contracts you are working on.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")

signal changed()
signal message(text: String, kind: String)

var state
var box: VBoxContainer


func setup(p_state) -> void:
    state = p_state
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 6)
    add_child(box)
    refresh()


func _label(text: String, size: int = 13, color: Color = Style.INK) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l


func client_name(id: String) -> String:
    return str(state.data["contracts"]["clients"][id]["name"])


func res_name(id: String) -> String:
    return str(state.data["resources"][id]["name"]).to_lower()


func accept(offer_id: int) -> void:
    var r: Dictionary = state.accept_contract(offer_id)
    if r["ok"]:
        message.emit("Contract accepted.", "good")
    else:
        message.emit("Cannot accept: %s" % str(r["reason"]), "warn")
    changed.emit()


func deliver_max(contract_id: int) -> void:
    for c in state.active_contracts:
        if int(c["id"]) != contract_id:
            continue
        var n: int = mini(state.stock(str(c["resource"])), int(c["quantity"]) - int(c["delivered"]))
        if n <= 0:
            message.emit("You have none of that to deliver.", "warn")
            return
        var r: Dictionary = state.deliver_contract(contract_id, n)
        if r["ok"]:
            var done: String = " Contract complete." if r["completed"] else ""
            message.emit("Delivered %d %s to %s for %s.%s" % [n, res_name(str(c["resource"])), client_name(str(c["client"])), Style.money(int(r["paid"])), done], "good")
        else:
            message.emit("Cannot deliver: %s" % str(r["reason"]), "warn")
        changed.emit()
        return


func _title_row(res_id: String, text: String) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    row.add_child(Style.icon_rect(ArtLibrary.resource_icon(res_id, 22), 22, Color.html(str(state.data["resources"][res_id]["color"]))))
    var l: Label = _label(text, 14)
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(l)
    return row


func _card(body: Control) -> PanelContainer:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", Style.box(Style.PAPER_LIGHT, Style.INK_SOFT, 1, 3, 8))
    p.add_child(body)
    return p


## Offers that end soonest first: those are the ones that will not wait.
func offers_sorted() -> Array:
    var list: Array = state.board.duplicate()
    list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["expires_day"]) < int(b["expires_day"]))
    return list


func refresh() -> void:
    for c in box.get_children():
        c.queue_free()
    var max_active: int = int(state.data["contracts"]["max_active"])

    var h1 := _label("Offers", 15)
    box.add_child(h1)
    if state.board.is_empty():
        box.add_child(_label("No offers right now. New ones turn up every few days.", 13, Style.INK_SOFT))
    for o in offers_sorted():
        var oid: int = int(o["id"])
        var res_id: String = str(o["resource"])
        var qty: int = int(o["quantity"])
        var unit: int = int(o["unit_price"])
        var ref: float = state.market.reference_price(res_id)
        var over: float = (float(unit) / ref - 1.0) * 100.0
        var v := VBoxContainer.new()
        v.add_theme_constant_override("separation", 2)
        v.add_child(_title_row(res_id, "%s wants %d %s" % [client_name(str(o["client"])), qty, res_name(res_id)]))
        v.add_child(_label("%s a unit, %s in all (+%.0f%% over market). %d days to deliver once accepted." % [Style.money(unit), Style.money0(unit * qty), over, int(o["deadline_days"])], 12, Style.INK_SOFT))
        var held: int = state.stock(res_id)
        var row := HBoxContainer.new()
        var hold: Label = _label("You hold %d of %d" % [held, qty], 12, Style.GOOD if held >= qty else Style.INK_SOFT)
        hold.autowrap_mode = TextServer.AUTOWRAP_OFF
        hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(hold)
        var left_days: int = int(o["expires_day"]) - state.day + 1
        var ends: Label = _label("Gone tonight!" if left_days <= 1 else "Open %d more days" % left_days, 12, Style.BAD if left_days <= 1 else (Style.WARN if left_days <= 3 else Style.INK_SOFT))
        ends.autowrap_mode = TextServer.AUTOWRAP_OFF
        ends.tooltip_text = "The better an offer pays, the sooner someone else takes it. Last day to accept: day %d." % int(o["expires_day"])
        ends.mouse_filter = Control.MOUSE_FILTER_STOP
        row.add_child(ends)
        var b := Button.new()
        b.text = "Accept"
        b.disabled = state.active_contracts.size() >= max_active
        if b.disabled:
            b.tooltip_text = "You can have %d contracts running at once" % max_active
        b.pressed.connect(func() -> void: accept(oid))
        row.add_child(b)
        v.add_child(row)
        box.add_child(_card(v))

    box.add_child(HSeparator.new())
    box.add_child(_label("Active (%d of %d)" % [state.active_contracts.size(), max_active], 15))
    if state.active_contracts.is_empty():
        box.add_child(_label("None. Accept an offer above.", 13, Style.INK_SOFT))
    for c in state.active_contracts:
        var cid: int = int(c["id"])
        var rid: String = str(c["resource"])
        var left_days_c: int = int(c["due_day"]) - state.day + 1
        var v2 := VBoxContainer.new()
        v2.add_theme_constant_override("separation", 3)
        v2.add_child(_title_row(rid, "%s: %d %s at %s a unit" % [client_name(str(c["client"])), int(c["quantity"]), res_name(rid), Style.money(int(c["unit_price"]))]))
        var bar := ProgressBar.new()
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(0, 10)
        bar.max_value = float(c["quantity"])
        bar.value = float(c["delivered"])
        v2.add_child(bar)
        var row2 := HBoxContainer.new()
        var due_color: Color = Style.BAD if left_days_c <= 3 else (Style.WARN if left_days_c <= 7 else Style.INK_SOFT)
        var prog: Label = _label("%d of %d delivered. %d days left." % [int(c["delivered"]), int(c["quantity"]), left_days_c], 12, due_color)
        prog.autowrap_mode = TextServer.AUTOWRAP_OFF
        prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row2.add_child(prog)
        var held2: int = state.stock(rid)
        var btn := Button.new()
        btn.text = "Deliver %d" % mini(held2, int(c["quantity"]) - int(c["delivered"]))
        btn.disabled = held2 <= 0
        btn.tooltip_text = "Hand over what you hold. Each delivery is paid straight away."
        btn.pressed.connect(func() -> void: deliver_max(cid))
        row2.add_child(btn)
        v2.add_child(row2)
        box.add_child(_card(v2))

    var st: Dictionary = state.contract_stats
    box.add_child(_label("Done %d, failed %d. Earned %s, penalties %s." % [int(st["completed"]), int(st["failed"]), Style.money0(int(st["earned_cents"])), Style.money0(int(st["penalties_cents"]))], 12, Style.INK_SOFT))
