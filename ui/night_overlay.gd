extends ColorRect
## Night falls with the crisis: a full-screen layer that multiplies everything under it by a dusky blue.
## It sits above the game screen but below the menu and the telegrams, which stay bright, and never takes the mouse.
## How dark: Crisis.night() (crisis.json "night"), capped so the text stays readable.

const Crisis = preload("res://sim/crisis.gd")

var state
var _tween: Tween


func setup(p_state) -> void:
    state = p_state
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
    material = mat
    color = Crisis.night_tint(state)
    visible = color != Color.WHITE


## Called every day: glide to the new darkness rather than jump.
func refresh() -> void:
    var target: Color = Crisis.night_tint(state)
    visible = target != Color.WHITE or color != Color.WHITE
    if target.is_equal_approx(color):
        return
    if _tween != null:
        _tween.kill()
    if not is_inside_tree():
        color = target
        return
    _tween = create_tween()
    _tween.tween_property(self, "color", target, 0.8)
