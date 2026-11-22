extends Control
## A small price chart. With show_labels it also draws the high and low values, for the big chart.
## Values are in cents. A dashed line marks the base price.

const Style = preload("res://ui/style.gd")

var values: Array = []
var base: float = 0.0
var line_color: Color = Style.INK
var show_labels: bool = false


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_values: Array, p_base: float) -> void:
    values = p_values
    base = p_base
    queue_redraw()


func _draw() -> void:
    if values.is_empty():
        return
    var lo: float = minf(float(values.min()), base)
    var hi: float = maxf(float(values.max()), base)
    var pad: float = maxf((hi - lo) * 0.12, base * 0.02)
    lo -= pad
    hi += pad
    var left: float = 46.0 if show_labels else 2.0
    var r := Rect2(left, 4, size.x - left - 3, size.y - 8)
    if show_labels:
        draw_rect(r, Style.PAPER_LIGHT)
        draw_rect(r, Style.PAPER_DEEP, false, 1.0)
    var yb: float = r.end.y - (base - lo) / (hi - lo) * r.size.y
    draw_dashed_line(Vector2(r.position.x, yb), Vector2(r.end.x, yb), Style.INK_SOFT, 1.0, 4.0)
    var pts := PackedVector2Array()
    var n: int = values.size()
    for i in n:
        var x: float = r.position.x + (r.size.x * float(i) / float(n - 1) if n > 1 else r.size.x)
        pts.append(Vector2(x, r.end.y - (float(values[i]) - lo) / (hi - lo) * r.size.y))
    if n > 1:
        draw_polyline(pts, line_color, 1.6, true)
    draw_circle(pts[n - 1], 2.5, line_color)
    if show_labels:
        var font: Font = get_theme_default_font()
        draw_string(font, Vector2(2, r.position.y + 11), Style.money(int(float(values.max()))), HORIZONTAL_ALIGNMENT_LEFT, 44, 11, Style.INK_SOFT)
        draw_string(font, Vector2(2, r.end.y), Style.money(int(float(values.min()))), HORIZONTAL_ALIGNMENT_LEFT, 44, 11, Style.INK_SOFT)
        draw_string(font, Vector2(r.position.x + 4, r.end.y + 1), "%d days" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Style.INK_SOFT)
