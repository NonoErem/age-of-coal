extends PanelContainer
## Shows what is on the selected tile, or whether the chosen building fits there.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")

var state
var tool_id: String = ""
var selected: Vector2i = Vector2i(-1, -1)
var icon_holder: HBoxContainer
var icon: TextureRect
var title_label: Label
var detail_label: Label
var bar: ProgressBar


func setup(p_state) -> void:
    state = p_state
    custom_minimum_size = Vector2(0, 76)
    icon_holder = HBoxContainer.new()
    icon_holder.add_theme_constant_override("separation", 10)
    add_child(icon_holder)
    icon = TextureRect.new()
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.custom_minimum_size = Vector2(52, 52)
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    icon_holder.add_child(icon)
    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 2)
    icon_holder.add_child(box)
    title_label = Label.new()
    title_label.add_theme_font_size_override("font_size", 15)
    box.add_child(title_label)
    detail_label = Label.new()
    detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail_label.add_theme_font_size_override("font_size", 13)
    detail_label.add_theme_color_override("font_color", Style.INK_SOFT)
    box.add_child(detail_label)
    bar = ProgressBar.new()
    bar.show_percentage = false
    bar.custom_minimum_size = Vector2(0, 8)
    bar.visible = false
    box.add_child(bar)
    refresh()


func refresh() -> void:
    bar.visible = false
    icon.texture = null
    icon.visible = false
    detail_label.add_theme_color_override("font_color", Style.INK_SOFT)
    if selected.x < 0:
        title_label.text = "Nothing selected"
        detail_label.text = "Click a tile to inspect it. Pick a building below to place one."
        return
    var x: int = selected.x
    var y: int = selected.y
    var res: Dictionary = state.data["resources"]
    var dep_id: String = state.deposit_id_at(x, y)
    var b: Dictionary = state.building_at(x, y)
    var lines: Array = []

    if not b.is_empty():
        var def: Dictionary = state.data["buildings"][b["type"]]
        icon.texture = ArtLibrary.building(str(b["type"]))
        title_label.text = "%s at (%d, %d)" % [str(def["name"]), x, y]
        var status: String = str(b["status"])
        if def["kind"] == "factory":
            if status == "paused_missing_input":
                lines.append("Paused: missing %s" % Style.names_text(b["missing"], res))
                detail_label.add_theme_color_override("font_color", Style.WARN)
            elif status == "running":
                lines.append("Running %d of %d batches" % [int(b["batches"]), int(def.get("batches_per_day", 1))])
            else:
                lines.append("Starts on the next day")
            lines.append("Each batch: %s into %s" % [Style.items_text(def["inputs"], res), Style.items_text(def["outputs"], res)])
        else:
            if status == "depleted":
                lines.append("Deposit exhausted")
                detail_label.add_theme_color_override("font_color", Style.WARN)
            else:
                lines.append("Produces %s a day, times richness" % Style.items_text(def["outputs"], res))
        lines.append("Upkeep %s/day" % Style.money(int(def["upkeep_per_day"])))
    elif dep_id != "":
        var info: Dictionary = state.data["map"]["deposits"][dep_id]
        icon.texture = ArtLibrary.deposit(str(info["resource"]))
        title_label.text = "%s deposit at (%d, %d)" % [str(res[info["resource"]]["name"]), x, y]
        var remaining: int = int(state.deposits[dep_id]["remaining"])
        lines.append("Richness x%.1f. %s of %s left. Land %s" % [float(info["richness"]), Style.num(remaining), Style.num(int(info["amount"])), Style.money0(int(info["land_cost"]))])
        bar.visible = true
        bar.max_value = float(info["amount"])
        bar.value = float(remaining)
    else:
        title_label.text = "Free ground at (%d, %d)" % [x, y]
        lines.append("Room for a factory.")

    if tool_id != "" and b.is_empty():
        var def2: Dictionary = state.data["buildings"][tool_id]
        var why: String = state.check_placement(tool_id, x, y)
        if why == "":
            var cost: int = state.build_cost(tool_id, dep_id)
            lines.append("Click to place %s for %s%s" % [str(def2["name"]), Style.money(cost), "" if cost <= state.money_cents else " (not enough cash)"])
        else:
            lines.append("%s cannot go here: %s" % [str(def2["name"]), reason_text(why)])
    icon.visible = icon.texture != null
    detail_label.text = "\n".join(lines)


static func reason_text(reason: String) -> String:
    match reason:
        "no_deposit": return "it needs a deposit."
        "wrong_deposit": return "that is the wrong kind of deposit."
        "deposit_tile_reserved": return "deposits are kept for mines."
        "tile_occupied": return "there is a building here already."
        "out_of_bounds": return "outside the map."
        "not_available_yet": return "not available yet."
        "insufficient_funds": return "not enough cash."
    return reason
