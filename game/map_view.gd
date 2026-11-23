extends Control
## The map: ground, deposits, buildings, selection, and build mode. Drawn like a survey sheet:
## paper ground with hatching, a ruled grid and coordinates along the edges.
## With a tool chosen, every legal tile is tinted green and the hovered tile shows the building ghosted in,
## green if it fits and red if not. The tile size follows the window size.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")

signal tile_clicked(x: int, y: int)
signal cancel_requested()

const LABEL := 16  # room for the coordinates along the top and left edges

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
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
    var avail: Vector2 = size - Vector2(LABEL, LABEL)
    tile = maxi(12, floori(minf(avail.x / cols, avail.y / rows)))
    origin = Vector2(LABEL, LABEL) + ((avail - Vector2(cols * tile, rows * tile)) / 2.0).floor()


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
    _draw_ground(cols, rows)
    for x in range(cols + 1):
        draw_line(origin + Vector2(x * tile, 0), origin + Vector2(x * tile, rows * tile), Color(Style.PAPER_DEEP, 0.65), 1.0)
    for y in range(rows + 1):
        draw_line(origin + Vector2(0, y * tile), origin + Vector2(cols * tile, y * tile), Color(Style.PAPER_DEEP, 0.65), 1.0)

    # Coordinates, like the margin of a survey sheet. Every other one when tiles are small.
    var step: int = 1 if tile >= 20 else 2
    for x in range(0, cols, step):
        draw_string(font, Vector2(origin.x + x * tile, origin.y - 4), str(x), HORIZONTAL_ALIGNMENT_CENTER, tile, 10, Style.INK_SOFT)
    for y in range(0, rows, step):
        draw_string(font, Vector2(origin.x - LABEL, origin.y + y * tile + tile * 0.66), str(y), HORIZONTAL_ALIGNMENT_RIGHT, LABEL - 4, 10, Style.INK_SOFT)

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
        _draw_deposit(id, m["deposits"][id])

    for b in state.buildings:
        _draw_building(b, font)

    # How much is left in each deposit that has been used: a ring that shrinks.
    for id in m["deposits"]:
        var d: Dictionary = m["deposits"][id]
        var frac: float = float(state.deposits[id]["remaining"]) / float(d["amount"])
        if frac < 0.999 and frac > 0.0:
            var c: Vector2 = _tile_rect(int(d["x"]), int(d["y"])).get_center()
            draw_arc(c, tile * 0.47, -PI / 2.0, -PI / 2.0 + TAU * frac, 28, Style.INK_SOFT, 2.5, true)

    draw_rect(map_rect, Style.INK, false, 2.0)

    if selected.x >= 0:
        draw_rect(_tile_rect(selected.x, selected.y), Style.SELECT, false, 3.0)
    if hover.x >= 0:
        _draw_hover(font)


## Light pencil hatching on empty ground, different on every tile but the same every time.
func _draw_ground(cols: int, rows: int) -> void:
    for y in rows:
        for x in cols:
            if state.deposit_id_at(x, y) != "" or not state.building_at(x, y).is_empty():
                continue
            var h: int = (x * 73856093 ^ y * 19349663) & 0x7fffffff
            if h % 100 < 38:
                var r: Rect2 = _tile_rect(x, y)
                var ox: float = float((h >> 8) % 100) / 100.0 * tile * 0.45 + tile * 0.12
                var oy: float = float((h >> 16) % 100) / 100.0 * tile * 0.45 + tile * 0.12
                var len: float = tile * 0.22
                var col := Color(Style.PAPER_DEEP, 0.75)
                draw_line(r.position + Vector2(ox, oy + len), r.position + Vector2(ox + len, oy), col, 1.0)
                draw_line(r.position + Vector2(ox + len * 0.5, oy + len * 1.3), r.position + Vector2(ox + len * 1.5, oy + len * 0.3), col, 1.0)


func _draw_deposit(id: String, d: Dictionary) -> void:
    # A mine standing on the deposit hides it: the mine picture and the remaining-ore ring say it all.
    if not state.building_at(int(d["x"]), int(d["y"])).is_empty():
        return
    var r: Rect2 = _tile_rect(int(d["x"]), int(d["y"]))
    var depleted: bool = int(state.deposits[id]["remaining"]) <= 0
    var tex: Texture2D = ArtLibrary.deposit(str(d["resource"]))
    if tex != null:
        # Richer deposits are drawn bigger.
        var k: float = lerpf(0.88, 1.0, clampf((float(d["richness"]) - 0.6) / 0.9, 0.0, 1.0))
        var side: float = tile * k
        var box := Rect2(r.get_center() - Vector2(side, side) / 2.0, Vector2(side, side))
        draw_texture_rect(tex, box, false, Color(1, 1, 1, 0.3) if depleted else Color.WHITE)
    else:
        var col: Color = Color.html(str(state.data["resources"][d["resource"]]["color"]))
        if depleted:
            col.a = 0.25
        var c: Vector2 = r.get_center()
        draw_circle(c, tile * (0.16 + 0.11 * float(d["richness"])), col)
        draw_arc(c, tile * (0.16 + 0.11 * float(d["richness"])), 0.0, TAU, 24, Style.INK, 1.5, true)


func _draw_building(b: Dictionary, font: Font) -> void:
    var def: Dictionary = state.data["buildings"][b["type"]]
    var r: Rect2 = _tile_rect(int(b["x"]), int(b["y"])).grow(-1)
    var tex: Texture2D = ArtLibrary.building(str(b["type"]))
    if tex != null:
        if def["kind"] != "extractor":
            # Factories get a plot of ground. Mines stand directly on their deposit.
            draw_rect(r, Style.PAPER_DARK)
            draw_rect(r, Style.INK_SOFT, false, 1.0)
        draw_texture_rect(tex, r.grow(-1), false)
    else:
        draw_rect(r.grow(-2), Style.SOOT if def["kind"] == "extractor" else Style.FACTORY)
        draw_rect(r.grow(-2), Style.INK, false, 2.0)
        draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.7), str(def.get("symbol", "?")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, maxi(10, int(tile * 0.36)), Style.PAPER)
    var dot: Vector2 = r.position + Vector2(r.size.x - 3, 3)
    draw_circle(dot, 5.0, Style.INK)
    draw_circle(dot, 3.5, _status_color(str(b["status"])))


func _draw_hover(font: Font) -> void:
    var hr: Rect2 = _tile_rect(hover.x, hover.y)
    if tool_id == "":
        draw_rect(hr, Style.INK_SOFT, false, 1.5)
        return
    var ok: bool = state.check_placement(tool_id, hover.x, hover.y) == ""
    var tint: Color = Style.GOOD if ok else Style.BAD
    draw_rect(hr, Color(tint, 0.22))
    var tex: Texture2D = ArtLibrary.building(tool_id)
    if tex != null:
        draw_texture_rect(tex, hr.grow(-2), false, Color(1, 1, 1, 0.78))
    else:
        draw_string(font, Vector2(hr.position.x, hr.position.y + hr.size.y * 0.66), str(state.data["buildings"][tool_id].get("symbol", "?")), HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, maxi(11, int(tile * 0.4)), Style.INK)
    draw_rect(hr, tint, false, 3.0)


static func _status_color(status: String) -> Color:
    match status:
        "running":
            return Style.GOOD
        "paused_missing_input":
            return Style.WARN
        "depleted":
            return Style.INK_SOFT
    return Style.PAPER_DEEP
