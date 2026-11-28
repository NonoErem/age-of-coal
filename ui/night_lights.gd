extends Control
## Lights in the night: drawn above the night layer, so your works stay visible while the land around them goes dark.
## Running buildings glow warm with lit windows; idle, damaged or unmanned ones stay dark, which says something too.
## Lit searchlights throw a pale circle over the ground they cover. Never takes the mouse.

const Crisis = preload("res://sim/crisis.gd")

const LIT := ["running", "firing", "ready", "lit", "housing", "built"]

var state
var map_view


func setup(p_state, p_map_view) -> void:
    state = p_state
    map_view = p_map_view
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    material = mat
    map_view.draw.connect(queue_redraw)


func refresh() -> void:
    queue_redraw()


## Is this building showing its lights tonight?
static func is_lit(state_ref, b: Dictionary) -> bool:
    if bool(b.get("stopped", false)) or not LIT.has(str(b.get("status", ""))):
        return false
    var kind: String = str(state_ref.data["buildings"][b["type"]]["kind"])
    if Crisis.is_damaged(state_ref, b) and not Crisis.holds_post(kind):
        return false
    var crew: int = int(state_ref.data["buildings"][b["type"]].get("crew", 0))
    if crew > 0 and int(b.get("crew_yours", 0)) + int(b.get("crew_hired", crew)) <= 0:
        return false
    return true


func _draw() -> void:
    if state == null or map_view == null or not map_view.is_visible_in_tree():
        return
    var dark: float = Crisis.darkness(state)
    if dark <= 0.0:
        return
    var to_me: Transform2D = get_global_transform().affine_inverse() * map_view.get_global_transform()
    var view := Rect2(Vector2.ZERO, map_view.size)
    var mini: Rect2 = map_view.minimap_rect()
    var tile: float = float(map_view.tile)
    for b in state.buildings:
        if not is_lit(state, b):
            continue
        var r: Rect2 = map_view._tile_rect(int(b["x"]), int(b["y"]))
        if not view.encloses(r) or mini.intersects(r):
            continue
        var c: Vector2 = to_me * r.get_center()
        var def: Dictionary = state.data["buildings"][b["type"]]
        if str(def["kind"]) == "light" and str(b["status"]) == "lit":
            var reach: float = (float(def["range"]) + 0.5) * tile
            var box := Rect2(r.get_center() - Vector2(reach, reach), Vector2(reach, reach) * 2.0).intersection(view)
            draw_rect(Rect2(to_me * box.position, box.size), Color(0.20, 0.20, 0.14, 0.55 * dark))
        # A soft warm glow around the building, then its windows.
        for k in [1.0, 0.72, 0.48]:
            draw_circle(c, tile * 0.62 * k, Color(0.42, 0.28, 0.10, 0.42 * dark))
        var w: float = maxf(2.0, tile * 0.09)
        for off in [Vector2(-0.18, 0.12), Vector2(0.14, 0.12), Vector2(-0.02, -0.06)]:
            draw_rect(Rect2(c + off * tile - Vector2(w, w) * 0.5, Vector2(w, w)), Color(1.0, 0.78, 0.35, 1.0 * dark))
