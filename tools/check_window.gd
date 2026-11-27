extends SceneTree
## Dev tool: applies each window setting to a real window and prints what size it got. Needs a display (xvfb).
##   xvfb-run -a -s "-screen 0 2560x1440x24" godot --path . --rendering-driver opengl3 -s tools/check_window.gd
const DisplaySettings = preload("res://game/settings.gd")

func _initialize() -> void:
    create_timer(30.0).timeout.connect(func() -> void: quit(2))
    print("screen usable area: ", DisplayServer.screen_get_usable_rect(0))
    for key in DisplaySettings.WINDOW_ORDER:
        var s = DisplaySettings.new()
        s.window = key
        s.ui_scale = 1.25 if key == "1920x1080" else 1.0
        var r: Dictionary = s.apply(root, true)
        for _i in 6:
            await process_frame
        print("%-11s -> window %s, asked %s, shrunk=%s, content scale %.2f, mode %d" % [key, str(DisplayServer.window_get_size()), str(DisplaySettings.WINDOWS[key]), str(r["shrunk"]), root.content_scale_factor, DisplayServer.window_get_mode()])
    quit(0)
