extends SceneTree
## Headless tests for the map view: layout, zoom, panning, the overview map and the mouse.
## (Mechanics only. Drawing is checked by looking at screenshots.)
##   godot --headless --path . -s tests/map_view_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")
const MapView = preload("res://game/map_view.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func make_view(w: float, h: float):
    var gs = GameState.new(DataLoader.load_game_data(), 3)
    var mv = MapView.new()
    mv.setup(gs)
    mv.size = Vector2(w, h)
    return mv


func click(button: int, pos: Vector2, pressed: bool) -> InputEventMouseButton:
    var e := InputEventMouseButton.new()
    e.button_index = button
    e.position = pos
    e.pressed = pressed
    return e


func motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
    var e := InputEventMouseMotion.new()
    e.position = pos
    e.relative = rel
    return e


## The map must always cover the view when it is bigger than the view.
func covers_view(mv) -> bool:
    mv._layout()
    var cells: Vector2i = mv.map_size_tiles()
    var map_px := Vector2(cells.x * mv.tile, cells.y * mv.tile)
    var ok: bool = true
    for axis in 2:
        if map_px[axis] > mv.view_size()[axis]:
            ok = ok and mv.origin[axis] <= MapView.LABEL + 0.01 and mv.origin[axis] + map_px[axis] >= mv.size[axis] - 0.01
    return ok


func _init() -> void:
    print("Map size")
    var gd: Dictionary = DataLoader.load_game_data()
    check(int(gd["map"]["width"]) == 40 and int(gd["map"]["height"]) == 24 and gd["map"]["deposits"].size() == 40, "the map is 40 x 24 tiles with 40 deposits (26 visible, 14 hidden)")
    var inside: bool = true
    for id in gd["map"]["deposits"]:
        var d: Dictionary = gd["map"]["deposits"][id]
        if int(d["x"]) >= 40 or int(d["y"]) >= 24:
            inside = false
    check(inside, "every deposit is on the map")

    print("Layout")
    var mv = make_view(700, 340)
    mv._layout()
    check(mv.tile == MapView.COMFORT_TILE and not mv.map_fits() and mv.minimap_rect().size != Vector2.ZERO, "in a small window tiles stay a comfortable size (%d px) and an overview map appears" % mv.tile)
    var mini: Rect2 = mv.minimap_rect()
    check(Rect2(Vector2.ZERO, mv.size).encloses(mini), "the overview map is inside the view")
    check(mv.tile_at(mv._tile_rect(12, 7).get_center()) == Vector2i(12, 7) and Rect2(Vector2.ZERO, mv.size).has_point(mv._tile_rect(12, 7).get_center()), "the opening view shows the starting area (tile 12, 7)")
    var big = make_view(1900, 1000)
    big._layout()
    check(big.map_fits() and big.minimap_rect().size == Vector2.ZERO and big.tile > MapView.COMFORT_TILE, "in a big window the whole map fits, bigger tiles (%d px), no overview map" % big.tile)

    print("Clicks and tiles")
    var all_ok: bool = true
    for t in [Vector2i(12, 7), Vector2i(8, 9), Vector2i(20, 10), Vector2i(18, 4)]:
        if mv.tile_at(mv._tile_rect(t.x, t.y).get_center()) != t:
            all_ok = false
    check(all_ok, "the centre of each tile maps back to that tile")
    check(mv.tile_at(Vector2(4, 100)) == Vector2i(-1, -1) and mv.tile_at(Vector2(100, 4)) == Vector2i(-1, -1), "the coordinate margins are not part of the map")
    var clicked: Array = []
    mv.tile_clicked.connect(func(x: int, y: int) -> void: clicked.append(Vector2i(x, y)))
    mv._gui_input(click(MOUSE_BUTTON_LEFT, mv._tile_rect(12, 7).get_center(), true))
    check(clicked == [Vector2i(12, 7)], "a left click selects the tile under the mouse")

    print("Zoom")
    mv = make_view(700, 340)
    var anchor := Vector2(350, 170)
    var before: Vector2i = mv.tile_at(anchor)
    mv.zoom_by(1.5, anchor)
    check(mv.tile > MapView.COMFORT_TILE and mv.manual_tile == mv.tile, "zooming in makes tiles bigger (%d px)" % mv.tile)
    check(mv.tile_at(anchor) == before, "the tile under the mouse stays under the mouse while zooming")
    for _i in 30:
        mv.zoom_by(1.4, anchor)
    check(mv.tile == MapView.MAX_TILE and covers_view(mv), "zoom stops at %d px and the map still covers the view" % MapView.MAX_TILE)
    for _i in 60:
        mv.zoom_by(0.7, anchor)
    check(mv.tile == MapView.MIN_TILE, "zoom stops at %d px" % MapView.MIN_TILE)
    mv._layout()
    var cells: Vector2i = mv.map_size_tiles()
    var cw: float = float(cells.x * mv.tile)
    check(mv.map_fits() and absf((mv.origin.x - MapView.LABEL) - floorf((mv.view_size().x - cw) / 2.0)) < 1.01, "when the whole map fits it is centred")
    mv.fit_view()
    check(mv.manual_tile == 0 and mv.tile == MapView.COMFORT_TILE, "Fit goes back to the automatic zoom")
    mv._gui_input(click(MOUSE_BUTTON_WHEEL_UP, Vector2(300, 150), true))
    check(mv.tile > MapView.COMFORT_TILE, "the mouse wheel zooms in")
    mv._gui_input(click(MOUSE_BUTTON_WHEEL_DOWN, Vector2(300, 150), true))
    mv._gui_input(click(MOUSE_BUTTON_WHEEL_DOWN, Vector2(300, 150), true))
    check(mv.tile < MapView.COMFORT_TILE + 4, "and out again")

    print("Panning")
    mv = make_view(700, 340)
    mv._layout()
    var o0: Vector2 = mv.origin
    mv.pan_by(Vector2(-100, -40))
    check(mv.origin.x < o0.x and mv.origin.y < o0.y and covers_view(mv), "panning moves the map")
    mv.pan_by(Vector2(99999, 99999))
    check(covers_view(mv) and is_equal_approx(mv.origin.x, MapView.LABEL) and is_equal_approx(mv.origin.y, MapView.LABEL), "it stops at the top-left edge of the map")
    mv.pan_by(Vector2(-99999, -99999))
    check(covers_view(mv) and mv.tile_at(mv.size - Vector2(2, 2)) == Vector2i(39, 23), "and at the bottom-right edge: the last tile is reachable")
    mv.center_on(20, 12)
    var c: Vector2 = mv._tile_rect(20, 12).get_center()
    check(c.distance_to(Vector2(MapView.LABEL, MapView.LABEL) + mv.view_size() / 2.0) < 2.0, "centre_on puts a tile in the middle of the view")
    mv.fit_view()
    mv.ensure_visible(38, 22)
    check(Rect2(Vector2.ZERO, mv.size).has_point(mv._tile_rect(38, 22).get_center()) and covers_view(mv), "ensure_visible scrolls a far tile into view")
    var pan_before: Vector2 = mv.pan
    mv.ensure_visible(38, 22)
    check(mv.pan == pan_before, "and leaves the map alone when the tile is already visible")
    var vis: Rect2i = mv.visible_range()
    check(vis.size.x <= ceili(mv.size.x / mv.tile) + 2 and vis.position.x >= 0 and vis.end.x <= 40 and vis.end.y <= 24, "only the tiles on screen are drawn (%d x %d)" % [vis.size.x, vis.size.y])

    print("Mouse: dragging")
    mv = make_view(700, 340)
    mv._layout()
    var cancelled: Array = []
    mv.cancel_requested.connect(func() -> void: cancelled.append(1))
    mv._gui_input(click(MOUSE_BUTTON_RIGHT, Vector2(300, 200), true))
    mv._gui_input(click(MOUSE_BUTTON_RIGHT, Vector2(300, 200), false))
    check(cancelled.size() == 1, "a plain right click still cancels building")
    var origin_before: Vector2 = mv.origin
    mv._gui_input(click(MOUSE_BUTTON_RIGHT, Vector2(300, 200), true))
    mv._gui_input(motion(Vector2(280, 195), Vector2(-20, -5)))
    mv._gui_input(motion(Vector2(250, 190), Vector2(-30, -5)))
    mv._gui_input(click(MOUSE_BUTTON_RIGHT, Vector2(250, 190), false))
    check(mv.origin.x < origin_before.x and cancelled.size() == 1, "dragging with the right button pans and does not cancel")
    origin_before = mv.origin
    mv._gui_input(click(MOUSE_BUTTON_MIDDLE, Vector2(300, 200), true))
    mv._gui_input(motion(Vector2(310, 205), Vector2(10, 5)))
    mv._gui_input(click(MOUSE_BUTTON_MIDDLE, Vector2(310, 205), false))
    check(mv.origin.x > origin_before.x, "the middle button pans straight away")
    mv._gui_input(click(MOUSE_BUTTON_RIGHT, Vector2(300, 200), true))
    mv._gui_input(motion(Vector2(302, 201), Vector2(2, 1)))
    mv._gui_input(click(MOUSE_BUTTON_RIGHT, Vector2(302, 201), false))
    check(cancelled.size() == 2, "a small wobble during a right click does not count as a drag")

    print("Overview map")
    mv = make_view(700, 340)
    mv._layout()
    mini = mv.minimap_rect()
    var k: float = mini.size.x / 40.0
    clicked.clear()
    mv.tile_clicked.connect(func(x: int, y: int) -> void: clicked.append(Vector2i(x, y)))
    mv._gui_input(click(MOUSE_BUTTON_LEFT, mini.position + Vector2(20.5, 12.5) * k, true))
    mv._gui_input(click(MOUSE_BUTTON_LEFT, mini.position + Vector2(20.5, 12.5) * k, false))
    var mid: Vector2 = mv._tile_rect(20, 12).get_center()
    check(clicked.is_empty() and mid.distance_to(Vector2(MapView.LABEL, MapView.LABEL) + mv.view_size() / 2.0) < 2.0, "clicking the overview map moves the view and does not select a tile")
    mv._gui_input(click(MOUSE_BUTTON_LEFT, mini.position + Vector2(2.5, 2.5) * k, true))
    mv._gui_input(motion(mini.position + Vector2(36.5, 20.5) * k, Vector2.ZERO))
    mv._gui_input(click(MOUSE_BUTTON_LEFT, mini.position + Vector2(36.5, 20.5) * k, false))
    check(mv.tile_at(mv.size - Vector2(2, 2)) == Vector2i(39, 23) and covers_view(mv), "dragging on it keeps moving the view, and stops at the map edge")

    mv.free()
    big.free()
    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
