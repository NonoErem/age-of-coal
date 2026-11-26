extends RefCounted
## Display settings: window size and interface size. Saved in user://settings.json and applied at start.
## The game draws in real pixels (no automatic stretching): a bigger window gives a bigger map and more room,
## and "UI size" scales the text and panels if you want them larger.

const PATH := "user://settings.json"
const WINDOWS := {
    "1280x720": Vector2i(1280, 720),
    "1600x900": Vector2i(1600, 900),
    "1920x1080": Vector2i(1920, 1080),
    "fullscreen": Vector2i.ZERO,
}
const WINDOW_ORDER := ["1280x720", "1600x900", "1920x1080", "fullscreen"]
const SCALES := [1.0, 1.25, 1.5]
const MIN_WINDOW := Vector2i(1000, 640)
const DECORATIONS := Vector2i(16, 48)  # room kept for the title bar and window borders

var window: String = "1280x720"
var ui_scale: float = 1.0


static func label(key: String) -> String:
    return "Fullscreen" if key == "fullscreen" else key.replace("x", " x ")


static func load_from(path: String = PATH) -> RefCounted:
    var s = (load("res://game/settings.gd") as GDScript).new()
    if not FileAccess.file_exists(path):
        return s
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return s
    if WINDOWS.has(str(parsed.get("window", ""))):
        s.window = str(parsed["window"])
    var sc: float = float(parsed.get("ui_scale", 1.0))
    for allowed in SCALES:
        if is_equal_approx(sc, float(allowed)):
            s.ui_scale = float(allowed)
    return s


## Returns OK or an Error code.
func save_to(path: String = PATH) -> int:
    var dir_err: int = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    if dir_err != OK:
        return dir_err
    var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(JSON.stringify({"window": window, "ui_scale": ui_scale}))
    f.close()
    return OK


## The size to use on a screen with this much usable room. Shrinks to fit, keeping the shape.
static func fit_to_screen(want: Vector2i, usable: Vector2i) -> Vector2i:
    var room: Vector2i = usable - DECORATIONS
    if want.x <= room.x and want.y <= room.y:
        return want
    var k: float = minf(float(room.x) / float(want.x), float(room.y) / float(want.y))
    return Vector2i(maxi(MIN_WINDOW.x, floori(want.x * k)), maxi(MIN_WINDOW.y, floori(want.y * k)))


## Applies the interface size always, and the window size when change_window is true.
## Returns {"size": Vector2i, "shrunk": bool}. Does nothing to the window when there is no display.
func apply(win: Window, change_window: bool = true) -> Dictionary:
    win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    win.content_scale_factor = ui_scale
    var result: Dictionary = {"size": win.size, "shrunk": false}
    if not change_window or DisplayServer.get_name() == "headless":
        return result
    if window == "fullscreen":
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        return result
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    var usable: Rect2i = DisplayServer.screen_get_usable_rect(win.current_screen)
    var want: Vector2i = WINDOWS[window]
    var size: Vector2i = fit_to_screen(want, usable.size)
    win.size = size
    win.position = usable.position + Vector2i(maxi(0, (usable.size.x - size.x) / 2), maxi(0, (usable.size.y - size.y - DECORATIONS.y / 2) / 2))
    result["size"] = size
    result["shrunk"] = size != want
    return result
