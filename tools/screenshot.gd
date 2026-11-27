extends SceneTree
## Dev tool: renders the main scene and saves a PNG. Needs a display (e.g. xvfb-run).
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1920x1080 -s tools/screenshot.gd -- out.png res://tools/shot_scenarios.gd play --keep-window [--ui-scale=1.25]
## --keep-window stops the game from resizing the window to its saved setting.

func _initialize() -> void:
    create_timer(60.0).timeout.connect(func() -> void: quit(2))
    var args: PackedStringArray = OS.get_cmdline_user_args()
    var out: String = args[0] if args.size() > 0 else "shot.png"
    var scene: Control = load("res://game/main.tscn").instantiate()
    root.add_child(scene)
    for _i in 5:
        await process_frame
    if args.size() > 1:
        var script: GDScript = load(args[1])
        script.new().run(scene, args[2] if args.size() > 2 else "")
        for _i in 5:
            await process_frame
    var img: Image = root.get_texture().get_image()
    img.save_png(out)
    print("saved ", out, " ", img.get_width(), "x", img.get_height())
    quit(0)
