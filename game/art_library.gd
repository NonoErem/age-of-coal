extends RefCounted
## Loads the SVG art in res://art and turns it into textures. Textures are cached.
## SVGs are read as plain files (no editor import step), so tests and the game see the same thing.
## When exporting the game, include the art: Project > Export > Resources > "Filters to export non-resource files": art/*
## The SVG files are 64 x 64 units. A missing file gives null, and callers draw a simple placeholder.

const ROOT := "res://art"
const UNITS := 64.0

static var _cache: Dictionary = {}


## Building picture for the map: drawn large with mipmaps so it stays clean at any tile size.
static func building(id: String) -> Texture2D:
    return _load("buildings", id, 128, true)


static func deposit(resource_id: String) -> Texture2D:
    return _load("deposits", resource_id, 128, true)


## Small crisp icons for panels. px is the size on screen.
## Creature picture for the map (crawler, strider, colossus).
static func alien(type_id: String, px: int = 128) -> Texture2D:
    return _load("aliens", type_id, px, px >= 64)


static func building_icon(id: String, px: int = 28) -> Texture2D:
    return _load("buildings", id, px, false)


static func resource_icon(resource_id: String, px: int = 18) -> Texture2D:
    return _load("resources", resource_id, px, false)


static func path_for(kind: String, id: String) -> String:
    return "%s/%s/%s.svg" % [ROOT, kind, id]


static func _load(kind: String, id: String, px: int, mipmaps: bool) -> Texture2D:
    var key: String = "%s/%s@%d" % [kind, id, px]
    if _cache.has(key):
        return _cache[key]
    var tex: Texture2D = null
    var p: String = path_for(kind, id)
    if FileAccess.file_exists(p):
        var img := Image.new()
        if img.load_svg_from_string(FileAccess.get_file_as_string(p), float(px) / UNITS) == OK and img.get_width() > 0:
            if mipmaps:
                img.generate_mipmaps()
            tex = ImageTexture.create_from_image(img)
    _cache[key] = tex
    return tex
