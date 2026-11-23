extends ScrollContainer
## Market events: what is announced, what is happening now, and what ended recently.

const Style = preload("res://ui/style.gd")
const MarketEvents = preload("res://sim/market_events.gd")

var state
var box: VBoxContainer
var count: int = 0            # announced + running, for the tab title
var shown_titles: Array = []  # names of the events on screen, for tests


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


func _card(e: Dictionary, timing: String, accent: Color) -> PanelContainer:
    var def: Dictionary = state.data["events"]["events"][e["type"]]
    var res: Dictionary = state.data["resources"]
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 2)
    v.add_child(_label(str(def["name"]), 14))
    v.add_child(_label(str(def["text"]), 12, Style.INK_SOFT))
    v.add_child(_label("Prices: %s" % MarketEvents.effects_text(e["effects"], res), 13, Style.INK))
    v.add_child(_label(timing, 12, accent))
    var held: Array = []
    for id in e["effects"]:
        if state.stock(id) > 0:
            held.append("%s %d" % [str(res[id]["name"]).to_lower(), state.stock(id)])
    v.add_child(_label("You hold: %s" % ", ".join(held) if not held.is_empty() else "You hold none of these.", 12, Style.INK_SOFT))
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", Style.box(Style.PAPER_LIGHT, Style.INK_SOFT, 1, 3, 8))
    p.add_child(v)
    shown_titles.append(str(def["name"]))
    return p


func refresh() -> void:
    for c in box.get_children():
        c.queue_free()
    shown_titles = []
    var me: Dictionary = state.market_events
    count = me["upcoming"].size() + me["active"].size()

    box.add_child(_label("Coming up", 15))
    if me["upcoming"].is_empty():
        box.add_child(_label("Nothing announced.", 13, Style.INK_SOFT))
    for e in me["upcoming"]:
        var days_to: int = int(e["start_day"]) - state.day
        var when: String = "tomorrow" if days_to == 1 else "in %d days" % days_to
        var length: int = int(e["end_day"]) - int(e["start_day"]) + 1
        box.add_child(_card(e, "Starts %s (day %d) and lasts about %d days. Prices are already drifting." % [when, int(e["start_day"]), length], Style.WARN))

    box.add_child(HSeparator.new())
    box.add_child(_label("Happening now", 15))
    if me["active"].is_empty():
        box.add_child(_label("Nothing at the moment.", 13, Style.INK_SOFT))
    for e in me["active"]:
        var left: int = int(e["end_day"]) - state.day + 1
        box.add_child(_card(e, "Ends after day %d (%d days left)." % [int(e["end_day"]), left], Style.BAD))

    box.add_child(HSeparator.new())
    box.add_child(_label("Recently", 15))
    if me["past"].is_empty():
        box.add_child(_label("Nothing yet.", 13, Style.INK_SOFT))
    var recent: Array = me["past"].duplicate()
    recent.reverse()
    for e in recent.slice(0, 5):
        var def: Dictionary = state.data["events"]["events"][e["type"]]
        box.add_child(_label("%s, days %d to %d: %s" % [str(def["name"]), int(e["start_day"]), int(e["end_day"]), MarketEvents.effects_text(e["effects"], state.data["resources"])], 12, Style.INK_SOFT))

    box.add_child(HSeparator.new())
    box.add_child(_label("While an event runs, clients make no new offers for the goods it affects, and their old offers are withdrawn when it is announced. Events that crash prices are likelier the bigger you are in that market.", 12, Style.INK_SOFT))
