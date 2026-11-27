extends PanelContainer
## The time bar: today's date, the phase of the crisis, a strip of the timeline and the threat.
## Before the announcement nobody knows what is coming, so the strip shows only the past and a blank future.

const Style = preload("res://ui/style.gd")
const Crisis = preload("res://sim/crisis.gd")

var state
var date_label: Label
var phase_label: Label
var strip: Control
var threat_label: Label


func setup(p_state) -> void:
    state = p_state
    add_theme_stylebox_override("panel", Style.box(Style.PAPER, Style.INK_SOFT, 1, 3, 4))
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    add_child(row)
    date_label = Label.new()
    date_label.add_theme_font_size_override("font_size", 14)
    date_label.custom_minimum_size = Vector2(108, 0)
    row.add_child(date_label)
    phase_label = Label.new()
    phase_label.add_theme_font_size_override("font_size", 13)
    phase_label.custom_minimum_size = Vector2(84, 0)
    phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    row.add_child(phase_label)
    strip = Control.new()
    strip.custom_minimum_size = Vector2(200, 22)
    strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    strip.mouse_filter = Control.MOUSE_FILTER_STOP
    strip.draw.connect(_draw_strip)
    row.add_child(strip)
    threat_label = Label.new()
    threat_label.add_theme_font_size_override("font_size", 13)
    threat_label.custom_minimum_size = Vector2(330, 0)
    threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    threat_label.clip_text = true
    row.add_child(threat_label)
    refresh()


## The last day the strip shows.
func horizon() -> int:
    if not Crisis.announced(state):
        return maxi(state.day + 120, 360)
    var last_start: int = 1
    for p in Crisis.phases(state):
        last_start = int(p["start"])
    return maxi(last_start + 200, state.day + 120)


func refresh() -> void:
    date_label.text = Crisis.date_text(state, state.day)
    date_label.tooltip_text = "Day %d" % state.day
    var ph: Dictionary = Crisis.phase(state)
    if ph.is_empty() or not Crisis.announced(state):
        phase_label.text = "Peace" if Crisis.enabled(state) else ""
        phase_label.add_theme_color_override("font_color", Style.INK_SOFT)
        phase_label.tooltip_text = ""
    else:
        phase_label.text = str(ph["name"]).to_upper()
        phase_label.add_theme_color_override("font_color", Color.html(str(ph["color"])).darkened(0.25))
        phase_label.tooltip_text = str(ph.get("text", ""))
    threat_label.text = threat_text()
    threat_label.add_theme_color_override("font_color", Style.BAD if not state.aliens.is_empty() else (Style.WARN if Crisis.announced(state) else Style.INK_SOFT))
    var tips: Array = []
    if Crisis.announced(state):
        for p in Crisis.phases(state):
            tips.append("%s, from %s (day %d): %s" % [str(p["name"]), Crisis.date_text(state, int(p["start"])), int(p["start"]), str(p.get("text", ""))])
    strip.tooltip_text = "\n".join(tips) if not tips.is_empty() else "%s. What lies ahead is unknown." % Crisis.date_text(state, state.day)
    strip.queue_redraw()


func threat_text() -> String:
    if not Crisis.enabled(state) or not Crisis.announced(state):
        return ""
    if not Crisis.landed(state):
        var left: int = Crisis.landing_day(state) - state.day
        return "Landings expected in %d day%s" % [left, "" if left == 1 else "s"]
    var n: int = state.aliens.size()
    return "%d creature%s on the map. Shipping %d/day per good" % [n, "" if n == 1 else "s", state.market.trade_cap]


func _draw_strip() -> void:
    var w: float = strip.size.x
    var h: float = strip.size.y
    var last: int = horizon()
    var k: float = w / float(last)
    strip.draw_rect(Rect2(0, 3, w, h - 6), Style.PAPER_DEEP)
    var font: Font = get_theme_default_font()
    if Crisis.announced(state):
        var ps: Array = Crisis.phases(state)
        for i in ps.size():
            var a: float = float(int(ps[i]["start"]) - 1) * k
            var b: float = w if i == ps.size() - 1 else float(int(ps[i + 1]["start"]) - 1) * k
            var col: Color = Color.html(str(ps[i]["color"]))
            strip.draw_rect(Rect2(a, 3, b - a, h - 6), Color(col, 0.85))
            if b - a > 50.0:
                strip.draw_string(font, Vector2(a + 4, h - 7), str(ps[i]["name"]), HORIZONTAL_ALIGNMENT_LEFT, b - a - 6, 11, Style.PAPER_LIGHT if i >= 2 else Style.INK)
    elif Crisis.enabled(state):
        var c: Color = Color.html(str(Crisis.phases(state)[0]["color"]))
        strip.draw_rect(Rect2(0, 3, float(state.day) * k, h - 6), Color(c, 0.85))
        strip.draw_string(font, Vector2(float(state.day) * k + 6, h - 7), "?", HORIZONTAL_ALIGNMENT_LEFT, 20, 12, Style.INK_SOFT)
    # Past days are shaded, today has a marker.
    var x: float = float(state.day - 1) * k
    strip.draw_rect(Rect2(0, 3, x, h - 6), Color(Style.INK, 0.18))
    strip.draw_rect(Rect2(0, 3, w, h - 6), Style.INK_SOFT, false, 1.0)
    strip.draw_line(Vector2(x, 0), Vector2(x, h), Style.INK, 3.0)
    strip.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, 0), Vector2(x + 5, 0), Vector2(x, 6)]), Style.INK)
