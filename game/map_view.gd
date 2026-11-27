extends Control
## The map: ground, deposits, buildings, selection, and build mode. Drawn like a survey sheet:
## paper ground with hatching, a ruled grid and coordinates along the edges.
## With a tool chosen, every legal tile is tinted green and the hovered tile shows the building ghosted in,
## green if it fits and red if not. The tile size follows the window size.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")
const Survey = preload("res://sim/survey.gd")

signal tile_clicked(x: int, y: int)
signal cancel_requested()

const LABEL := 16  # room for the coordinates along the top and left edges
const MIN_TILE := 12
const MAX_TILE := 64
const COMFORT_TILE := 26  # the automatic zoom never goes below this: past it you pan instead
const MINIMAP_WIDTH := 160
const DRAG_START := 6.0   # how far the mouse must move with the right button down before it counts as a drag

var state
var selected: Vector2i = Vector2i(-1, -1)
var hover: Vector2i = Vector2i(-1, -1)
var tool_id: String = ""
var survey_level: int = 0                 # 0 = not surveying
var tile: int = 32
var origin: Vector2 = Vector2.ZERO
var manual_tile: int = 0                  # 0 = automatic zoom
var pan: Vector2 = Vector2.ZERO           # where the map's top-left corner sits inside the view area
var centered_once: bool = false
var _pan_button: int = 0                  # which mouse button is panning, 0 for none
var _pan_start: Vector2 = Vector2.ZERO
var _panning: bool = false
var _mini_drag: bool = false
var _zoom_row: HBoxContainer


func setup(p_state) -> void:
    state = p_state
    custom_minimum_size = Vector2(360, 240)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    clip_contents = true
    _add_zoom_buttons()
    queue_redraw()


func _add_zoom_buttons() -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    for spec in [["+", "Zoom in (mouse wheel, or the + key)"], ["-", "Zoom out (mouse wheel, or the - key)"], ["Fit", "Back to the automatic zoom (0)"]]:
        var b := Button.new()
        b.text = str(spec[0])
        b.tooltip_text = str(spec[1])
        b.focus_mode = Control.FOCUS_NONE
        b.custom_minimum_size = Vector2(38 if str(spec[0]) == "Fit" else 30, 26)
        b.add_theme_font_size_override("font_size", 13)
        match str(spec[0]):
            "+":
                b.pressed.connect(func() -> void: zoom_by(1.25, size / 2.0))
            "-":
                b.pressed.connect(func() -> void: zoom_by(0.8, size / 2.0))
            _:
                b.pressed.connect(fit_view)
        row.add_child(b)
    add_child(row)
    _zoom_row = row
    _place_zoom_buttons()


## Top-right corner, just under the coordinate margin.
func _place_zoom_buttons() -> void:
    if _zoom_row == null:
        return
    _zoom_row.size = _zoom_row.get_combined_minimum_size()
    _zoom_row.position = Vector2(size.x - _zoom_row.size.x - 8.0, LABEL + 6.0)


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _place_zoom_buttons()
        queue_redraw()
    elif what == NOTIFICATION_MOUSE_EXIT:
        hover = Vector2i(-1, -1)
        queue_redraw()


func map_size_tiles() -> Vector2i:
    var m: Dictionary = state.data["map"]
    return Vector2i(int(m["width"]), int(m["height"]))


func view_size() -> Vector2:
    return size - Vector2(LABEL, LABEL)


## Works out the tile size and where the map sits. Also keeps the map from being dragged out of view.
func _layout() -> void:
    var cells: Vector2i = map_size_tiles()
    var view: Vector2 = view_size()
    if manual_tile > 0:
        tile = clampi(manual_tile, MIN_TILE, MAX_TILE)
    else:
        var fit: int = floori(minf(view.x / cells.x, view.y / cells.y))
        tile = clampi(maxi(fit, COMFORT_TILE), MIN_TILE, MAX_TILE)
    if not centered_once and view.x > 60.0 and view.y > 60.0:
        centered_once = true
        _center_pan_on(_start_tile())
    var map_px := Vector2(cells.x * tile, cells.y * tile)
    var base := Vector2.ZERO
    for axis in 2:
        if map_px[axis] <= view[axis]:
            base[axis] = floorf((view[axis] - map_px[axis]) / 2.0)
        else:
            pan[axis] = clampf(pan[axis], view[axis] - map_px[axis], 0.0)
            base[axis] = floorf(pan[axis])
    origin = Vector2(LABEL, LABEL) + base


func _start_tile() -> Vector2:
    var sv: Array = state.data["map"].get("start_view", [0, 0])
    return Vector2(float(sv[0]) + 0.5, float(sv[1]) + 0.5)


func _center_pan_on(tile_pos: Vector2) -> void:
    pan = view_size() / 2.0 - tile_pos * float(tile)


## Zoom in (factor above 1) or out, keeping the point under the anchor (in control coordinates) where it is.
func zoom_by(factor: float, anchor: Vector2) -> void:
    _layout()
    var old_tile: int = tile
    var new_tile: int = clampi(roundi(old_tile * factor), MIN_TILE, MAX_TILE)
    if new_tile == old_tile:
        new_tile = clampi(old_tile + (1 if factor > 1.0 else -1), MIN_TILE, MAX_TILE)
    var under: Vector2 = (anchor - origin) / float(old_tile)  # which map position is under the anchor, in tiles
    manual_tile = new_tile
    tile = new_tile
    pan = (anchor - Vector2(LABEL, LABEL)) - under * float(new_tile)
    _layout()
    queue_redraw()


func fit_view() -> void:
    manual_tile = 0
    centered_once = false
    _layout()
    queue_redraw()


func pan_by(delta: Vector2) -> void:
    _layout()
    pan = (origin - Vector2(LABEL, LABEL)) + delta
    _layout()
    queue_redraw()


## Put the middle of the view on this tile.
func center_on(x: float, y: float) -> void:
    _layout()
    _center_pan_on(Vector2(x + 0.5, y + 0.5))
    _layout()
    queue_redraw()


## Scrolls the map if this tile is not on screen.
func ensure_visible(x: int, y: int) -> void:
    _layout()
    var r: Rect2 = _tile_rect(x, y)
    var view := Rect2(Vector2(LABEL, LABEL) + Vector2(tile, tile) * 0.5, view_size() - Vector2(tile, tile))
    if not view.encloses(r):
        center_on(x, y)


## The tiles that are at least partly on screen.
func visible_range() -> Rect2i:
    var cells: Vector2i = map_size_tiles()
    var x0: int = clampi(floori((float(LABEL) - origin.x) / tile), 0, cells.x - 1)
    var y0: int = clampi(floori((float(LABEL) - origin.y) / tile), 0, cells.y - 1)
    var x1: int = clampi(ceili((size.x - origin.x) / tile), 0, cells.x - 1)
    var y1: int = clampi(ceili((size.y - origin.y) / tile), 0, cells.y - 1)
    return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func map_fits() -> bool:
    var cells: Vector2i = map_size_tiles()
    var view: Vector2 = view_size()
    return cells.x * tile <= view.x and cells.y * tile <= view.y


## Where the overview map is drawn (empty when the whole map is on screen).
func minimap_rect() -> Rect2:
    _layout()
    if map_fits():
        return Rect2()
    var cells: Vector2i = map_size_tiles()
    var k: int = clampi(floori(float(MINIMAP_WIDTH) / cells.x), 2, 6)
    var sz := Vector2(cells.x * k, cells.y * k)
    return Rect2(size - sz - Vector2(10, 10), sz)


func tile_at(pos: Vector2) -> Vector2i:
    _layout()
    var cells: Vector2i = map_size_tiles()
    var x: int = floori((pos.x - origin.x) / tile)
    var y: int = floori((pos.y - origin.y) / tile)
    if x < 0 or y < 0 or x >= cells.x or y >= cells.y or pos.x < LABEL or pos.y < LABEL:
        return Vector2i(-1, -1)
    return Vector2i(x, y)


func _tile_rect(x: int, y: int) -> Rect2:
    _layout()
    return Rect2(origin + Vector2(x * tile, y * tile), Vector2(tile, tile))


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        if _mini_drag:
            _jump_from_minimap(event.position)
            return
        if _pan_button != 0:
            if not _panning and event.position.distance_to(_pan_start) > (0.0 if _pan_button == MOUSE_BUTTON_MIDDLE else DRAG_START):
                _panning = true
            if _panning:
                pan_by(event.relative)
                return
        var t: Vector2i = tile_at(event.position)
        if t != hover:
            hover = t
            queue_redraw()
    elif event is InputEventMouseButton:
        _on_mouse_button(event)


func _on_mouse_button(event: InputEventMouseButton) -> void:
    match event.button_index:
        MOUSE_BUTTON_WHEEL_UP:
            if event.pressed:
                zoom_by(1.15, event.position)
                accept_event()
        MOUSE_BUTTON_WHEEL_DOWN:
            if event.pressed:
                zoom_by(1.0 / 1.15, event.position)
                accept_event()
        MOUSE_BUTTON_LEFT:
            if event.pressed:
                if minimap_rect().has_point(event.position):
                    _mini_drag = true
                    _jump_from_minimap(event.position)
                    return
                var t: Vector2i = tile_at(event.position)
                if t.x >= 0:
                    tile_clicked.emit(t.x, t.y)
            else:
                _mini_drag = false
        MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
            if event.pressed:
                _pan_button = event.button_index
                _pan_start = event.position
                _panning = false
            elif _pan_button == event.button_index:
                # A right click that did not turn into a drag cancels building, as before.
                if event.button_index == MOUSE_BUTTON_RIGHT and not _panning:
                    cancel_requested.emit()
                _pan_button = 0
                _panning = false


func _jump_from_minimap(pos: Vector2) -> void:
    var r: Rect2 = minimap_rect()
    if r.size == Vector2.ZERO:
        return
    var k: float = r.size.x / float(map_size_tiles().x)
    var local: Vector2 = (pos - r.position) / k
    var cells: Vector2i = map_size_tiles()
    center_on(clampf(floorf(local.x), 0.0, cells.x - 1.0), clampf(floorf(local.y), 0.0, cells.y - 1.0))


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
        if int(info.get("depth", 0)) > 0:
            lines.append("Deep deposit, found by a level %d survey" % int(info["depth"]))
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
    var cells: Vector2i = map_size_tiles()
    var font: Font = get_theme_default_font()
    var map_rect := Rect2(origin, Vector2(cells.x * tile, cells.y * tile))
    var vis: Rect2i = visible_range()

    draw_rect(map_rect, Style.PAPER_LIGHT)
    _draw_ground(vis)
    for x in range(vis.position.x, vis.end.x + 1):
        draw_line(origin + Vector2(x * tile, 0), origin + Vector2(x * tile, cells.y * tile), Color(Style.PAPER_DEEP, 0.65), 1.0)
    for y in range(vis.position.y, vis.end.y + 1):
        draw_line(origin + Vector2(0, y * tile), origin + Vector2(cells.x * tile, y * tile), Color(Style.PAPER_DEEP, 0.65), 1.0)

    _draw_surveyed(vis)

    # Legal tiles for the chosen building.
    if tool_id != "":
        var strong: bool = state.data["buildings"][tool_id]["kind"] == "extractor"
        for y in range(vis.position.y, vis.end.y):
            for x in range(vis.position.x, vis.end.x):
                if state.check_placement(tool_id, x, y) == "":
                    var tr: Rect2 = _tile_rect(x, y).grow(-1)
                    draw_rect(tr, Color(Style.GOOD, 0.38 if strong else 0.12))
                    if strong:
                        draw_rect(tr, Color(Style.GOOD, 0.9), false, 2.0)

    var screen := Rect2(Vector2.ZERO, size).grow(float(tile))
    for id in state.revealed_deposit_ids():
        var d: Dictionary = state.data["map"]["deposits"][id]
        if screen.has_point(_tile_rect(int(d["x"]), int(d["y"])).get_center()):
            _draw_deposit(id, d)
    for b in state.buildings:
        if screen.has_point(_tile_rect(int(b["x"]), int(b["y"])).get_center()):
            _draw_building(b, font)

    # How much is left in each deposit that has been used: a ring that shrinks.
    for id in state.revealed_deposit_ids():
        var d2: Dictionary = state.data["map"]["deposits"][id]
        var frac: float = float(state.deposits[id]["remaining"]) / float(d2["amount"])
        if frac < 0.999 and frac > 0.0:
            var c: Vector2 = _tile_rect(int(d2["x"]), int(d2["y"])).get_center()
            if screen.has_point(c):
                draw_arc(c, tile * 0.47, -PI / 2.0, -PI / 2.0 + TAU * frac, 28, Style.INK_SOFT, 2.5, true)

    draw_rect(map_rect, Style.INK, false, 2.0)

    if selected.x >= 0:
        draw_rect(_tile_rect(selected.x, selected.y), Style.SELECT, false, 3.0)
    if hover.x >= 0:
        _draw_hover(font)

    # The margins with the coordinates sit on top, so a scrolled map never shows through them.
    draw_rect(Rect2(0, 0, size.x, LABEL), Style.PAPER_LIGHT)
    draw_rect(Rect2(0, 0, LABEL, size.y), Style.PAPER_LIGHT)
    var step: int = 1 if tile >= 20 else 2
    for x in range(vis.position.x, vis.end.x):
        if x % step == 0:
            draw_string(font, Vector2(origin.x + x * tile, LABEL - 4), str(x), HORIZONTAL_ALIGNMENT_CENTER, tile, 10, Style.INK_SOFT)
    for y in range(vis.position.y, vis.end.y):
        if y % step == 0:
            draw_string(font, Vector2(0, origin.y + y * tile + tile * 0.66), str(y), HORIZONTAL_ALIGNMENT_RIGHT, LABEL - 3, 10, Style.INK_SOFT)

    _draw_minimap()


## A small overview of the whole map, shown when the map does not fit on screen. Click or drag on it to move.
func _draw_minimap() -> void:
    var r: Rect2 = minimap_rect()
    if r.size == Vector2.ZERO:
        return
    var cells: Vector2i = map_size_tiles()
    var k: float = r.size.x / float(cells.x)
    draw_rect(r.grow(3), Color(Style.PAPER, 0.94))
    draw_rect(r.grow(3), Style.INK, false, 1.5)
    draw_rect(r, Style.PAPER_LIGHT)
    for id in state.revealed_deposit_ids():
        var d: Dictionary = state.data["map"]["deposits"][id]
        var col: Color = Color.html(str(state.data["resources"][d["resource"]]["color"]))
        if int(state.deposits[id]["remaining"]) <= 0:
            col.a = 0.3
        draw_rect(Rect2(r.position + Vector2(float(d["x"]), float(d["y"])) * k, Vector2(k, k)).grow(0.5), col)
    for b in state.buildings:
        draw_rect(Rect2(r.position + Vector2(float(b["x"]), float(b["y"])) * k, Vector2(k, k)).grow(1.0), Style.INK)
    var view_tiles_origin: Vector2 = (Vector2(LABEL, LABEL) - origin) / float(tile)
    var view_tiles: Vector2 = view_size() / float(tile)
    var vr := Rect2(r.position + view_tiles_origin * k, view_tiles * k)
    draw_rect(vr.intersection(r), Style.SELECT, false, 1.5)


## Light pencil hatching on empty ground, different on every tile but the same every time.
func _draw_ground(vis: Rect2i) -> void:
    for y in range(vis.position.y, vis.end.y):
        for x in range(vis.position.x, vis.end.x):
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


## Ground that has been surveyed is tinted blue: a little for a shallow survey, more for a deep one.
func _draw_surveyed(vis: Rect2i) -> void:
    if state.survey_tiles.is_empty():
        return
    for y in range(vis.position.y, vis.end.y):
        for x in range(vis.position.x, vis.end.x):
            var lv: int = int(state.survey_tiles.get(state.tile_key(x, y), 0))
            if lv > 0:
                draw_rect(_tile_rect(x, y), Color(Style.SELECT, 0.07 if lv == 1 else 0.14))


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
    # Deep deposits carry a small tag with the survey level that found them.
    if int(d.get("depth", 0)) > 0 and tile >= 18:
        var font: Font = get_theme_default_font()
        var tag := Rect2(r.position + Vector2(r.size.x * 0.52, r.size.y * 0.68), Vector2(r.size.x * 0.46, r.size.y * 0.3))
        draw_rect(tag, Style.INK)
        draw_string(font, tag.position + Vector2(0, tag.size.y * 0.78), "D%d" % int(d["depth"]), HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, maxi(8, int(tile * 0.24)), Style.PAPER_LIGHT)


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
    if survey_level > 0:
        var a: Rect2i = Survey.area(state, hover.x, hover.y)
        var top_left: Rect2 = _tile_rect(a.position.x, a.position.y)
        var area_rect := Rect2(top_left.position, Vector2(a.size.x * tile, a.size.y * tile))
        var useful: bool = Survey.check(state, hover.x, hover.y, survey_level) == ""
        var tint: Color = Style.SELECT if useful else Style.BAD
        draw_rect(area_rect, Color(tint, 0.14))
        draw_rect(area_rect, tint, false, 3.0)
        draw_rect(hr, tint, false, 2.0)
        return
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
        "paused_missing_input", "paused_storage_full":
            return Style.WARN
        "stopped":
            return Style.SELECT
        "depleted":
            return Style.INK_SOFT
    return Style.PAPER_DEEP
