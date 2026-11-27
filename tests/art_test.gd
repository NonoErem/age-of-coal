extends SceneTree
## Checks the art: every building, resource and deposit has a picture, the files are well formed,
## and nothing in art/ is left over from something that no longer exists.
##   godot --headless --path . -s tests/art_test.gd

const DataLoader = preload("res://sim/data_loader.gd")
const ArtLibrary = preload("res://game/art_library.gd")

var failures: int = 0
var checks: int = 0


func check(cond: bool, label: String) -> void:
    checks += 1
    if cond:
        print("  ok    ", label)
    else:
        failures += 1
        print("  FAIL  ", label)


func svg_names(kind: String) -> Array:
    var out: Array = []
    var da: DirAccess = DirAccess.open("%s/%s" % [ArtLibrary.ROOT, kind])
    if da == null:
        return out
    for f in da.get_files():
        if f.ends_with(".svg"):
            out.append(f.trim_suffix(".svg"))
    out.sort()
    return out


## Share of pixels that are not transparent, so an empty picture is caught.
func coverage(tex: Texture2D) -> float:
    var img: Image = tex.get_image()
    var solid: int = 0
    for y in img.get_height():
        for x in img.get_width():
            if img.get_pixel(x, y).a > 0.1:
                solid += 1
    return float(solid) / float(img.get_width() * img.get_height())


func well_formed(kind: String, id: String) -> bool:
    var parser := XMLParser.new()
    if parser.open(ArtLibrary.path_for(kind, id)) != OK:
        return false
    var saw_svg: bool = false
    while parser.read() == OK:
        if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "svg":
            saw_svg = parser.get_named_attribute_value_safe("width") == "64" and parser.get_named_attribute_value_safe("height") == "64"
    return saw_svg


func _init() -> void:
    var gd: Dictionary = DataLoader.load_game_data()
    var building_ids: Array = gd["buildings"].keys()
    var resource_ids: Array = gd["resources"].keys()
    var deposit_resources: Array = []
    for id in gd["map"]["deposits"]:
        var r: String = str(gd["map"]["deposits"][id]["resource"])
        if not deposit_resources.has(r):
            deposit_resources.append(r)
    building_ids.sort()
    resource_ids.sort()
    deposit_resources.sort()

    print("Coverage")
    check(svg_names("buildings") == building_ids, "every building has a picture and there are no extras (%d)" % building_ids.size())
    check(svg_names("resources") == resource_ids, "every resource has an icon and there are no extras (%d)" % resource_ids.size())
    var alien_ids: Array = []
    for t in gd["crisis"].get("aliens", {}).get("types", []):
        alien_ids.append(str(t["id"]))
    alien_ids.sort()
    check(svg_names("aliens") == alien_ids, "every kind of creature has a picture and there are no extras (%d)" % alien_ids.size())
    var deposit_files: Array = svg_names("deposits")
    var missing: Array = []
    for r in deposit_resources:
        if not deposit_files.has(r):
            missing.append(r)
    check(missing.is_empty(), "every resource that has a deposit on the map has deposit art %s" % str(missing))

    print("Files")
    var bad: Array = []
    for id in building_ids:
        if not well_formed("buildings", id):
            bad.append("buildings/" + id)
    for id in resource_ids:
        if not well_formed("resources", id):
            bad.append("resources/" + id)
    for id in alien_ids:
        if not well_formed("aliens", id):
            bad.append("aliens/" + id)
        elif ArtLibrary.alien(id) == null:
            bad.append("aliens/" + id + " (no texture)")
    for id in deposit_files:
        if not well_formed("deposits", id):
            bad.append("deposits/" + id)
    check(bad.is_empty(), "every SVG is a 64 x 64 drawing that parses %s" % str(bad))

    print("Loading")
    var empty: Array = []
    for id in building_ids:
        var t: Texture2D = ArtLibrary.building(id)
        if t == null or t.get_width() != 128 or coverage(t) < 0.15:
            empty.append(id)
    check(empty.is_empty(), "every building draws something at map size %s" % str(empty))
    empty = []
    for id in deposit_files:
        var t2: Texture2D = ArtLibrary.deposit(id)
        if t2 == null or coverage(t2) < 0.25:
            empty.append(id)
    check(empty.is_empty(), "every deposit draws something %s" % str(empty))
    empty = []
    for id in resource_ids:
        var t3: Texture2D = ArtLibrary.resource_icon(id, 18)
        if t3 == null or t3.get_width() != 18 or coverage(t3) < 0.2:
            empty.append(id)
    check(empty.is_empty(), "every resource icon draws something at 18 px %s" % str(empty))
    check(ArtLibrary.building_icon("coal_mine", 30).get_width() == 30, "panel icons come out at the size asked for")
    check(ArtLibrary.building("no_such_building") == null and ArtLibrary.resource_icon("no_such_thing") == null, "a missing picture gives null instead of a crash")
    check(ArtLibrary.building("coal_mine") == ArtLibrary.building("coal_mine"), "pictures are cached")

    print("")
    print("%d checks, %d failed" % [checks, failures])
    quit(1 if failures > 0 else 0)
