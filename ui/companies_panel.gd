extends ScrollContainer
## The rival companies: who they are, how they are doing, what they do to the market, and a way to buy them.

const Crisis = preload("res://sim/crisis.gd")
const Style = preload("res://ui/style.gd")
const Companies = preload("res://sim/companies.gd")

signal changed()
signal message(text: String, kind: String)

var state
var box: VBoxContainer
var attention_count: int = 0   # rivals in trouble that you do not own, for the tab title
var armed: String = ""         # the company whose purchase is waiting for a second click
var shown_names: Array = []    # for tests


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
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return l


func _inline(text: String, size: int = 12, color: Color = Style.INK) -> Label:
    var l := _label(text, size, color)
    l.autowrap_mode = TextServer.AUTOWRAP_OFF
    l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    return l


## Only the first letter in capitals (String.capitalize() would title-case every word).
static func _sentence(text: String) -> String:
    return text.substr(0, 1).to_upper() + text.substr(1)


static func status_color(status: String) -> Color:
    match status:
        "healthy":
            return Style.GOOD
        "weakened":
            return Style.WARN
    return Style.BAD


func _items(items: Dictionary) -> String:
    var parts: Array = []
    for id in items:
        parts.append("%s %d" % [str(state.data["resources"][id]["name"]).to_lower(), int(items[id])])
    return ", ".join(parts)


func _depth_text(id: String) -> String:
    var def: Dictionary = state.data["companies"]["list"][id]
    var s: float = float(state.rivals[id]["strength"])
    var parts: Array = []
    for res in def.get("depth_bonus", {}):
        parts.append("%s %+d%%" % [str(state.data["resources"][res]["name"]).to_lower(), int(round(float(def["depth_bonus"][res]) * s * 100.0))])
    return ", ".join(parts)


## Owned first, then the ones in trouble (the chances), then the healthy ones.
func ordered_ids() -> Array:
    var ids: Array = state.rivals.keys()
    var rank: Dictionary = {"weakened": 1, "bankrupt": 1, "healthy": 2}
    ids.sort_custom(func(a: String, b: String) -> bool:
        var ra: int = 0 if bool(state.rivals[a]["owned"]) else int(rank[state.rivals[a]["status"]])
        var rb: int = 0 if bool(state.rivals[b]["owned"]) else int(rank[state.rivals[b]["status"]])
        return ra < rb)
    return ids


func _buy(id: String) -> void:
    var name_text: String = str(state.data["companies"]["list"][id]["name"])
    if armed != id:
        armed = id
        refresh()
        return
    armed = ""
    var r: Dictionary = state.buy_company(id)
    if r["ok"]:
        if bool(r["restarted"]):
            message.emit("You bought bankrupt %s for %s and restarted it. It is weak: give it time." % [name_text, Style.money0(int(r["cost"]))], "good")
        else:
            message.emit("You bought %s for %s. You will receive half of its daily profit." % [name_text, Style.money0(int(r["cost"]))], "good")
    else:
        message.emit("Cannot buy %s: %s" % [name_text, Companies.reason_text(str(r["reason"]))], "warn")
    changed.emit()


func _sell(id: String) -> void:
    var name_text: String = str(state.data["companies"]["list"][id]["name"])
    if armed != id:
        armed = id
        refresh()
        return
    armed = ""
    var r: Dictionary = state.sell_company(id)
    if r["ok"]:
        message.emit("You sold %s for %s." % [name_text, Style.money0(int(r["revenue"]))], "info")
    else:
        message.emit("Cannot sell %s: %s" % [name_text, Companies.reason_text(str(r["reason"]))], "warn")
    changed.emit()


func _card(id: String) -> PanelContainer:
    var def: Dictionary = state.data["companies"]["list"][id]
    var r: Dictionary = state.rivals[id]
    var status: String = str(r["status"])
    var owned: bool = bool(r["owned"])
    var s: float = float(r["strength"])
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 3)

    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 6)
    var title: Label = _label(str(def["name"]) + ("  (yours)" if owned else ""), 14)
    head.add_child(title)
    var badge: Label = _inline(Companies.status_text(status).to_upper(), 11, status_color(status))
    head.add_child(badge)
    var size_label: Label = _inline("size x%.1f" % float(r["scale"]), 11, Style.INK_SOFT)
    size_label.tooltip_text = "Size: 1.0 is the company as it started. A healthy, profitable company reinvests and grows, which raises its price and its pull on the market. Debt shrinks it."
    head.add_child(size_label)
    v.add_child(head)
    v.add_child(_label(str(def["text"]), 12, Style.INK_SOFT))

    var bar := ProgressBar.new()
    bar.show_percentage = false
    bar.custom_minimum_size = Vector2(0, 10)
    bar.max_value = 1.0
    bar.value = s
    bar.tooltip_text = "How much of its usual output it manages. Below full strength it supplies and buys less than the market expects."
    v.add_child(bar)

    v.add_child(_label("Makes %s a day. Uses %s." % [_items(def["outputs"]), _items(def["inputs"]) if not def["inputs"].is_empty() else "nothing it has to buy"], 12))
    if status == "bankrupt":
        if Crisis.rivals_revive(state):
            v.add_child(_label("Out of business. Investors restart it in about %d days. %s." % [int(r["bankrupt_days"]), _sentence(Companies.effect_text(state, id))], 12, Style.BAD))
        else:
            v.add_child(_label("Out of business. Nobody invests during the invasion: it stays closed unless you buy it. %s." % _sentence(Companies.effect_text(state, id)), 12, Style.BAD))
    else:
        var money_line: String = "Cash %s. Yesterday %s." % [Style.money0(int(r["cash"])), ("a profit of %s" % Style.money0(int(r["profit"]))) if int(r["profit"]) >= 0 else ("a loss of %s" % Style.money0(-int(r["profit"])))]
        v.add_child(_label(money_line, 12, Style.BAD if int(r["cash"]) < 0 else Style.INK_SOFT))
        if status == "weakened":
            v.add_child(_label("Running at %d%%. %s." % [int(round(s * 100.0)), _sentence(Companies.effect_text(state, id))], 12, Style.WARN))
        var depth: String = _depth_text(id)
        if depth != "":
            v.add_child(_label("Makes the market deeper: %s." % depth, 12, Style.INK_SOFT))

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    if owned:
        var left: int = Companies.hold_days_left(state, id)
        var info: String = "Dividends so far %s." % Style.money0(int(r["dividends"]))
        var sell_info: Label = _label(info, 12, Style.GOOD)
        row.add_child(sell_info)
        var sb := Button.new()
        sb.text = "Click again to sell for %s" % Style.money0(Companies.sell_price(state, id)) if armed == id else "Sell (%s)" % Style.money0(Companies.sell_price(state, id))
        sb.disabled = left > 0
        sb.tooltip_text = "You can sell in %d days." % left if left > 0 else "Selling returns only part of what it would cost to buy."
        sb.pressed.connect(func() -> void: _sell(id))
        row.add_child(sb)
    else:
        var price: int = Companies.value(state, id)
        var note: String = "Price %s" % Style.money0(price)
        if status == "bankrupt":
            note += " (bargain, restarts at once)"
        var price_l: Label = _label(note, 12)
        row.add_child(price_l)
        var bb := Button.new()
        bb.text = "Click again to buy" if armed == id else "Buy"
        var why: String = ""
        if Companies.owned_count(state) >= int(state.data["companies"]["max_owned"]):
            why = "You can hold at most %d companies." % int(state.data["companies"]["max_owned"])
        elif price > state.money_cents:
            why = "You need %s." % Style.money0(price)
        bb.disabled = why != ""
        if why != "":
            bb.tooltip_text = why
        bb.pressed.connect(func() -> void: _buy(id))
        row.add_child(bb)
    v.add_child(row)

    var p := PanelContainer.new()
    var border: Color = Style.SELECT if owned else Style.INK_SOFT
    p.add_theme_stylebox_override("panel", Style.box(Style.PAPER_LIGHT, border, 2 if owned else 1, 3, 8))
    p.add_child(v)
    shown_names.append(str(def["name"]))
    return p


func refresh() -> void:
    for c in box.get_children():
        c.queue_free()
    shown_names = []
    attention_count = 0
    if not Companies.enabled(state):
        box.add_child(_label("There are no rival companies in this game.", 13, Style.INK_SOFT))
        return
    if armed != "" and (not state.rivals.has(armed) or (not bool(state.rivals[armed]["owned"]) and Companies.value(state, armed) > state.money_cents)):
        armed = ""
    for id in state.rivals:
        if str(state.rivals[id]["status"]) != "healthy" and not bool(state.rivals[id]["owned"]):
            attention_count += 1

    var st: Dictionary = state.rival_stats
    var max_owned: int = int(state.data["companies"]["max_owned"])
    box.add_child(_label("Rival companies", 15))
    box.add_child(_label("They are not on your map. Each makes certain goods from certain inputs. While they thrive they keep those markets deep. When they lose money they weaken: they supply and buy less, prices shift and the market thins. They take contract offers too. Successful ones grow, and the bigger they are the more they cost. You hold %d of %d possible companies. Dividends received: %s." % [Companies.owned_count(state), max_owned, Style.money0(int(st["dividends_cents"]))], 12, Style.INK_SOFT))
    for id in ordered_ids():
        box.add_child(_card(id))
    box.add_child(_label("Buying a company costs more the healthier and the bigger it is. A company you own still grows, but slower, because you take half of its profit. You receive half of its profit each day. It still trades as before, so buying it does not change the market, and it stops taking contract offers. If it goes bankrupt while you own it, you lose everything you paid. Selling is possible after %d days and returns only %d%% of the purchase price." % [int(state.data["companies"]["min_hold_days"]), int(round(float(state.data["companies"]["sell_back"]) * 100.0))], 12, Style.INK_SOFT))
