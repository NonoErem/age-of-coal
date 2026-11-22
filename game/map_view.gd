extends Control
## The map: deposits, buildings, selection, and build mode.
## With a tool chosen, every legal tile is tinted green and the hovered tile shows whether it fits.
## The tile size follows the window size.

const Style = preload("res://ui/style.gd")

signal tile_clicked(x: int, y: int)
signal cancel_requested()

var state
var selected: Vector2i = Vector2i(-1, -1)
var hover: Vector2i = Vector2i(-1, -1)
var tool_id: String = ""
var tile: int = 32
var origin: Vector2 = Vector2.ZERO


func setup(p_state) -> void:
    state = p_state
    custom_minimum_size = Vector2(360, 240)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    queue_redraw()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()
    elif what == NOTIFICATION_MOUSE_EXIT:
        hover = Vector2i(-1, -1)
        queue_redraw()


func _layout() -> void:
    var m: Dictionary = state.data["map"]
    var cols: int = int(m["width"])
    var rows: int = int(m["height"])
    tile = maxi(12, floori(minf(size.x / cols, size.y / rows)))
    origin = ((size - Vector2(cols * tile, rows * tile)) / 2.0).floor()


func tile_at(pos: Vector2) -> Vector2i:
    _layout()
    var m: Dictionary = state.data["map"]
    var x: int = floori((pos.x - origin.x) / tile)
    var y: int = floori((pos.y - origin.y) / tile)
    if x < 0 or y < 0 or x >= int(m["width"]) or y >= int(m["height"]):
        return Vector2i(-1, -1)
    return Vector2i(x, y)


func _tile_rect(x: int, y: int) -> Rect2:
    return Rect2(origin + Vector2(x * tile, y * tile), Vector2(tile, tile))


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        var t: Vector2i = tile_at(event.position)
        if t != hover:
            hover = t
            queue_redraw()
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            var t2: Vector2i = tile_at(event.position)
            if t2.x >= 0:
                tile_clicked.emit(t2.x, t2.y)
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            cancel_requested.emit()


func _get_tooltip(at_position: Vector2) -> String:
    var t: Vector2i = tile_at(at_position)
    if t.x < 0:
        return ""
    var lines: Array = []
    var dep_id: String = state.deposit_id_at(t.x, t.y)
    if dep_id != "":
        var info: Dictionary = state.data["map"]["deposits"][dep_id]
        lines.append("%s deposit, richness x%.1f" % [str(state.data["resources"][info["resource"]]["name"]), float(info["richness"])])
        lines.append("%s of %s left" % [Style.num(int(state.deposits[dep_id]["remaining"])), Style.num(int(info["amount"]))])
    var b: Dictionary = state.building_at(t.x, t.y)
    if not b.is_empty():
        lines.append(str(state.data["buildings"][b["type"]]["name"]))
    if lines.is_empty():
        return ""
    return "\n".join(lines)


func _draw() -> void:
    if state == null:
        return
    _layout()
    var m: Dictionary = state.data["map"]
    var cols: int = int(m["width"])
    var rows: int = int(m["height"])
    var font: Font = get_theme_default_font()
    var map_rect := Rect2(origin, Vector2(cols * tile, rows * tile))

    draw_rect(map_rect, Style.PAPER_LIGHT)
    for x in range(cols + 1):
        draw_line(origin + Vector2(x * tile, 0), origin + Vector2(x * tile, rows * tile), Color(Style.PAPER_DEEP, 0.7), 1.0)
    for y in range(rows + 1):
        draw_line(origin + Vector2(0, y * tile), origin + Vector2(cols * tile, y * tile), Color(Style.PAPER_DEEP, 0.7), 1.0)

    # Legal tiles for the chosen building.
    if tool_id != "":
        var strong: bool = state.data["buildings"][tool_id]["kind"] == "extractor"
        for y in rows:
            for x in cols:
                if state.check_placement(tool_id, x, y) == "":
                    var tr: Rect2 = _tile_rect(x, y).grow(-1)
                    draw_rect(tr, Color(Style.GOOD, 0.38 if strong else 0.12))
                    if strong:
                        draw_rect(tr, Color(Style.GOOD, 0.9), false, 2.0)

    for id in m["deposits"]:
        var d: Dictionary = m["deposits"][id]
        var c: Vector2 = _tile_rect(int(d["x"]), int(d["y"])).get_center()
        var col: Color = Color.html(str(state.data["resources"][d["resource"]]["color"]))
        var frac: float = float(state.deposits[id]["remaining"]) / float(d["amount"])
        if frac <= 0.0:
            col.a = 0.25
        var radius: float = tile * (0.16 + 0.11 * float(d["richness"]))
        draw_circle(c, radius, col)
        draw_arc(c, radius, 0.0, TAU, 24, Style.INK, 1.5, true)
        if frac > 0.0:
            draw_arc(c, radius + 3.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 28, Style.INK_SOFT, 2.0, true)

    for b in state.buildings:
        var def: Dictionary = state.data["buildings"][b["type"]]
        var r: Rect2 = _tile_rect(int(b["x"]), int(b["y"])).grow(-3)
        draw_rect(r, Style.SOOT if def["kind"] == "extractor" else Style.FACTORY)
        draw_rect(r, Style.INK, false, 2.0)
        draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.74), str(def.get("symbol", "?")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, maxi(10, int(tile * 0.36)), Style.PAPER)
        draw_circle(r.position + Vector2(r.size.x - 2, 2), 4.5, Style.INK)
        draw_circle(r.position + Vector2(r.size.x - 2, 2), 3.0, _status_color(str(b["status"])))

    draw_rect(map_rect, Style.INK, false, 2.0)

    if selected.x >= 0:
        draw_rect(_tile_rect(selected.x, selected.y), Style.SELECT, false, 3.0)
    if hover.x >= 0:
        var hr: Rect2 = _tile_rect(hover.x, hover.y)
        if tool_id != "":
            var ok: bool = state.check_placement(tool_id, hover.x, hover.y) == ""
            draw_rect(hr, Color(Style.GOOD if ok else Style.BAD, 0.30))
            draw_rect(hr, Style.GOOD if ok else Style.BAD, false, 3.0)
            var sym: String = str(state.data["buildings"][tool_id].get("symbol", "?"))
            draw_string(font, Vector2(hr.position.x, hr.position.y + hr.size.y * 0.66), sym, HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, maxi(11, int(tile * 0.4)), Style.INK)
        else:
            draw_rect(hr, Style.INK_SOFT, false, 1.5)


static func _status_color(status: String) -> Color:
    match status:
        "running":
            return Style.GOOD
        "paused_missing_input":
            return Style.WARN
        "depleted":
            return Style.INK_SOFT
    return Style.PAPER_DEEP
