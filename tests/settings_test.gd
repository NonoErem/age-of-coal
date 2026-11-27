extends SceneTree
## Headless tests for the display settings file and the fit-to-screen rule.
##   godot --headless --path . -s tests/settings_test.gd

const Settings = preload("res://game/settings.gd")

const FILE := "user://test_settings/settings.json"

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func write_raw(text: String) -> void:
    DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
    var f: FileAccess = FileAccess.open(FILE, FileAccess.WRITE)
    f.store_string(text)
    f.close()


func _init() -> void:
    DirAccess.remove_absolute(FILE)

    print("The settings file")
    var s = Settings.load_from(FILE)
    check(s.window == "1280x720" and is_equal_approx(s.ui_scale, 1.0), "with no file the defaults are 1280 x 720 at 100%")
    s.window = "1920x1080"
    s.ui_scale = 1.25
    check(s.save_to(FILE) == OK, "settings save")
    var back = Settings.load_from(FILE)
    check(back.window == "1920x1080" and is_equal_approx(back.ui_scale, 1.25), "and come back as they were")
    for key in Settings.WINDOW_ORDER:
        s.window = key
        s.save_to(FILE)
        check(Settings.load_from(FILE).window == key, "'%s' round-trips" % key)
    write_raw("{ not json")
    check(Settings.load_from(FILE).window == "1280x720", "a damaged file gives the defaults instead of a crash")
    write_raw(JSON.stringify({"window": "5000x5000", "ui_scale": 7.0}))
    var odd = Settings.load_from(FILE)
    check(odd.window == "1280x720" and is_equal_approx(odd.ui_scale, 1.0), "unknown values are ignored")
    write_raw(JSON.stringify({"window": "1600x900"}))
    check(Settings.load_from(FILE).window == "1600x900" and is_equal_approx(Settings.load_from(FILE).ui_scale, 1.0), "a missing value falls back on its default")
    write_raw("[1, 2, 3]")
    check(Settings.load_from(FILE).window == "1280x720", "a file of the wrong shape gives the defaults")

    print("Fitting the window to the screen")
    check(Settings.fit_to_screen(Vector2i(1920, 1080), Vector2i(3840, 2120)) == Vector2i(1920, 1080), "on a big screen 1920 x 1080 is left alone")
    var tight: Vector2i = Settings.fit_to_screen(Vector2i(1920, 1080), Vector2i(1920, 1040))
    check(tight.x <= 1920 - 16 and tight.y <= 1040 - 48, "on a 1080p monitor it shrinks to leave room for the title bar and taskbar (%s)" % str(tight))
    check(absf(float(tight.x) / float(tight.y) - 16.0 / 9.0) < 0.02, "and keeps its shape")
    check(Settings.fit_to_screen(Vector2i(1280, 720), Vector2i(1366, 728)).x >= 1000, "it never goes below the smallest playable window")

    print("Labels")
    check(Settings.label("1920x1080") == "1920 x 1080" and Settings.label("fullscreen") == "Fullscreen", "window sizes have readable names")

    DirAccess.remove_absolute(FILE)
    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
