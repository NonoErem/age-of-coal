extends SceneTree
## Dev tool: draws every piece of art on a sheet, big and at game sizes, and saves a PNG.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/art_sheet.gd -- out.png

const ArtLibrary = preload("res://game/art_library.gd")
const Style = preload("res://ui/style.gd")
const DataLoader = preload("res://sim/data_loader.gd")


func _initialize() -> void:
    create_timer(60.0).timeout.connect(func() -> void: quit(2))
    var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "sheet.png"
    var data: Dictionary = DataLoader.load_game_data()
    var bg := ColorRect.new()
    bg.color = Style.PAPER_LIGHT
    bg.size = Vector2(1280, 720)
    root.add_child(bg)

    var y: float = 8.0
    var x: float = 8.0
    for id in data["buildings"]:
        _show(bg, ArtLibrary.building(id), Vector2(x, y), 96)
        _show(bg, ArtLibrary.building_icon(id, 28), Vector2(x + 100, y), 28)
        _show(bg, ArtLibrary.building(id), Vector2(x + 100, y + 36), 36, true)
        x += 170
        if x > 1100:
            x = 8.0
            y += 110.0
    y += 120.0 if x > 8.0 else 10.0
    x = 8.0
    for id in ["coal", "iron_ore", "limestone", "copper_ore"]:
        _show(bg, ArtLibrary.deposit(id), Vector2(x, y), 96)
        _show(bg, ArtLibrary.deposit(id), Vector2(x + 100, y), 36, true)
        x += 150
    y += 110.0
    x = 8.0
    for id in data["resources"]:
        _show(bg, ArtLibrary.resource_icon(id, 64), Vector2(x, y), 64)
        _show(bg, ArtLibrary.resource_icon(id, 20), Vector2(x + 68, y), 20)
        _show(bg, ArtLibrary.resource_icon(id, 16), Vector2(x + 68, y + 28), 16)
        x += 100
    for _i in 4:
        await process_frame
    var img: Image = root.get_texture().get_image()
    img.save_png(out)
    print("saved ", out)
    quit(0)


func _show(parent: Control, tex: Texture2D, pos: Vector2, px: int, mip: bool = false) -> void:
    if tex == null:
        var miss := ColorRect.new()
        miss.color = Color.MAGENTA
        miss.position = pos
        miss.size = Vector2(px, px)
        parent.add_child(miss)
        return
    var r := TextureRect.new()
    r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    r.stretch_mode = TextureRect.STRETCH_SCALE
    r.custom_minimum_size = Vector2(px, px)
    r.texture = tex
    r.position = pos
    r.size = Vector2(px, px)
    r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if mip else CanvasItem.TEXTURE_FILTER_LINEAR
    parent.add_child(r)
