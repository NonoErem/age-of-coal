extends ScrollContainer
## What needs attention, what flows where, and every building at a glance.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")

signal locate(x: int, y: int)

var state
var box: VBoxContainer
var attention_count: int = 0


func setup(p_state) -> void:
    state = p_state
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 4)
    add_child(box)
    refresh()


func _label(text: String, size: int = 13, color: Color = Style.INK, width: int = 0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.horizontal_alignment = align
    if width > 0:
        l.custom_minimum_size = Vector2(width, 0)
        l.clip_text = true
    return l


func _heading(text: String) -> Label:
    return _label(text, 15)


func refresh() -> void:
    for c in box.get_children():
        c.queue_free()
    var defs: Dictionary = state.data["buildings"]
    var res: Dictionary = state.data["resources"]
    attention_count = 0

    # ----- needs attention -----
    box.add_child(_heading("Needs attention"))
    var any: bool = false
    for b in state.buildings:
        var def: Dictionary = defs[b["type"]]
        var status: String = str(b["status"])
        if status != "paused_missing_input" and status != "depleted" and status != "paused_storage_full":
            continue
        any = true
        attention_count += 1
        var text: String
        if status == "paused_missing_input":
            text = "%s (%d,%d): paused, missing %s" % [str(def["name"]), int(b["x"]), int(b["y"]), Style.names_text(b["missing"], res)]
        elif status == "paused_storage_full":
            text = "%s (%d,%d): stopped, storage is full" % [str(def["name"]), int(b["x"]), int(b["y"])]
        else:
            text = "%s (%d,%d): deposit exhausted" % [str(def["name"]), int(b["x"]), int(b["y"])]
        var row := HBoxContainer.new()
        row.add_child(Style.icon_rect(ArtLibrary.building_icon(str(b["type"]), 24), 24))
        var warn_l: Label = _label(text, 13, Style.WARN)
        warn_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        warn_l.custom_minimum_size = Vector2(320, 0)
        warn_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(warn_l)
        var bx: int = int(b["x"])
        var by: int = int(b["y"])
        var show := Button.new()
        show.text = "Show"
        show.add_theme_font_size_override("font_size", 12)
        show.pressed.connect(func() -> void: locate.emit(bx, by))
        row.add_child(show)
        box.add_child(row)
    if not any:
        box.add_child(_label("Everything is running." if not state.buildings.is_empty() else "No buildings yet.", 13, Style.INK_SOFT))

    # ----- storage -----
    box.add_child(HSeparator.new())
    box.add_child(_heading("Storage"))
    var stored: int = state.stored_units()
    var cap: int = state.capacity()
    var bar := ProgressBar.new()
    bar.show_percentage = false
    bar.max_value = float(cap)
    bar.value = float(stored)
    bar.custom_minimum_size = Vector2(0, 10)
    var ratio: float = float(stored) / float(maxi(1, cap))
    var fill: Color = Style.BAD if ratio >= 1.0 else (Style.WARN if ratio >= 0.9 else Style.GOOD)
    bar.add_theme_stylebox_override("fill", Style.box(fill, fill, 0, 2, 0))
    box.add_child(bar)
    var warehouses: int = state.count_owned("warehouse")
    var storage_note: Label = _label("%d of %d units. %d warehouse%s (+%d each). Full storage stops mines and blocks buying." % [stored, cap, warehouses, "" if warehouses == 1 else "s", int(state.data["buildings"]["warehouse"]["capacity"])], 12, Style.INK_SOFT)
    storage_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(storage_note)

    # ----- flows -----
    box.add_child(HSeparator.new())
    box.add_child(_heading("Flows, last day"))
    var made: Dictionary = state.last_report.get("produced", {})
    var used: Dictionary = state.last_report.get("consumed", {})
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 4)
    head.add_child(Style.icon_rect(null, 0))
    for h in [["Resource", 96, HORIZONTAL_ALIGNMENT_LEFT], ["Stock", 52, HORIZONTAL_ALIGNMENT_RIGHT], ["Made", 48, HORIZONTAL_ALIGNMENT_RIGHT], ["Used", 48, HORIZONTAL_ALIGNMENT_RIGHT], ["Net", 48, HORIZONTAL_ALIGNMENT_RIGHT], ["Lasts", 56, HORIZONTAL_ALIGNMENT_RIGHT]]:
        head.add_child(_label(str(h[0]), 11, Style.INK_SOFT, int(h[1]), int(h[2])))
    box.add_child(head)
    var shown: int = 0
    for id in res:
        var m: int = int(made.get(id, 0))
        var u: int = int(used.get(id, 0))
        var s: int = state.stock(id)
        if m == 0 and u == 0 and s == 0:
            continue
        shown += 1
        var net: int = m - u
        var lasts: String = ""
        var lasts_color: Color = Style.INK_SOFT
        if net < 0:
            if s <= 0:
                lasts = "out"
                lasts_color = Style.BAD
            else:
                var days: float = float(s) / float(-net)
                lasts = "%.0f days" % days
                lasts_color = Style.BAD if days < 3.0 else (Style.WARN if days < 7.0 else Style.INK_SOFT)
        var r := HBoxContainer.new()
        r.add_theme_constant_override("separation", 4)
        r.add_child(Style.icon_rect(ArtLibrary.resource_icon(id, 18), 18, Color.html(str(res[id]["color"]))))
        r.add_child(_label(str(res[id]["name"]), 13, Style.INK, 78))
        r.add_child(_label(str(s), 13, Style.INK, 52, HORIZONTAL_ALIGNMENT_RIGHT))
        r.add_child(_label(str(m), 13, Style.INK_SOFT, 48, HORIZONTAL_ALIGNMENT_RIGHT))
        r.add_child(_label(str(u), 13, Style.INK_SOFT, 48, HORIZONTAL_ALIGNMENT_RIGHT))
        r.add_child(_label("%+d" % net, 13, Style.GOOD if net > 0 else (Style.BAD if net < 0 else Style.INK_SOFT), 48, HORIZONTAL_ALIGNMENT_RIGHT))
        r.add_child(_label(lasts, 12, lasts_color, 56, HORIZONTAL_ALIGNMENT_RIGHT))
        box.add_child(r)
    if shown == 0:
        box.add_child(_label("Nothing produced or stored yet.", 13, Style.INK_SOFT))
    if state.last_report.is_empty():
        box.add_child(_label("Flows appear after the first day.", 12, Style.INK_SOFT))

    # ----- buildings -----
    box.add_child(HSeparator.new())
    box.add_child(_heading("Buildings (%d)" % state.buildings.size()))
    for b in state.buildings:
        var def2: Dictionary = defs[b["type"]]
        var status2: String = str(b["status"])
        var text2: String
        var color: Color = Style.GOOD
        match status2:
            "stopped":
                text2 = "stopped"
                color = Style.SELECT
            "paused_storage_full":
                text2 = "storage full"
                color = Style.WARN
            "running":
                if def2["kind"] == "storage":
                    text2 = "+%d room" % int(def2["capacity"])
                    color = Style.INK_SOFT
                elif def2["kind"] == "factory":
                    text2 = "%d/%d batches" % [int(b["batches"]), int(def2.get("batches_per_day", 1))]
                else:
                    text2 = "running"
            "paused_missing_input":
                text2 = "paused"
                color = Style.WARN
            "depleted":
                text2 = "exhausted"
                color = Style.INK_SOFT
            _:
                text2 = "new"
                color = Style.INK_SOFT
        var row2 := HBoxContainer.new()
        row2.add_theme_constant_override("separation", 6)
        row2.add_child(Style.icon_rect(ArtLibrary.building_icon(str(b["type"]), 24), 24))
        row2.add_child(_label(str(def2["name"]), 13, Style.INK, 118))
        row2.add_child(_label("(%d,%d)" % [int(b["x"]), int(b["y"])], 12, Style.INK_SOFT, 46))
        row2.add_child(_label(text2, 13, color, 96))
        var bx2: int = int(b["x"])
        var by2: int = int(b["y"])
        var go := Button.new()
        go.text = "Show"
        go.add_theme_font_size_override("font_size", 12)
        go.pressed.connect(func() -> void: locate.emit(bx2, by2))
        row2.add_child(go)
        box.add_child(row2)
    if state.buildings.is_empty():
        box.add_child(_label("Pick a building at the bottom left, then click the map.", 13, Style.INK_SOFT))
