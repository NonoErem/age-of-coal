extends Control
## The game menu: save, load, new game, quit. Opens over the game and pauses it.
## Anything that throws away progress asks first, right where you clicked.

const Style = preload("res://ui/style.gd")
const SaveManager = preload("res://game/save_manager.gd")

signal resume_requested()
signal save_requested(slot: String)
signal load_requested(slot: String)
signal new_game_requested()
signal quit_requested()

var save_dir: String = SaveManager.DEFAULT_DIR
var has_progress: bool = false
var rows_box: VBoxContainer
var bottom_box: HBoxContainer
var message_label: Label
var confirming: Dictionary = {}  # {"kind": "save" | "load" | "new", "slot": String}


func setup() -> void:
    visible = false
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.color = Color(0.10, 0.08, 0.05, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(560, 0)
    panel.add_theme_stylebox_override("panel", Style.box(Style.PAPER, Style.INK, 2, 4, 16))
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    panel.add_child(box)

    var title := Label.new()
    title.text = "Game menu"
    title.add_theme_font_size_override("font_size", 22)
    box.add_child(title)
    var hint := Label.new()
    hint.text = "The game is paused while this is open."
    hint.add_theme_color_override("font_color", Style.INK_SOFT)
    hint.add_theme_font_size_override("font_size", 12)
    box.add_child(hint)
    box.add_child(HSeparator.new())

    rows_box = VBoxContainer.new()
    rows_box.add_theme_constant_override("separation", 6)
    box.add_child(rows_box)

    message_label = Label.new()
    message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    message_label.add_theme_font_size_override("font_size", 13)
    box.add_child(message_label)
    box.add_child(HSeparator.new())
    bottom_box = HBoxContainer.new()
    bottom_box.add_theme_constant_override("separation", 8)
    box.add_child(bottom_box)


func open(p_has_progress: bool) -> void:
    has_progress = p_has_progress
    confirming = {}
    message_label.text = ""
    visible = true
    rebuild()


func close() -> void:
    visible = false
    confirming = {}


func show_message(text: String, good: bool = true) -> void:
    message_label.text = text
    message_label.add_theme_color_override("font_color", Style.GOOD if good else Style.BAD)
    rebuild()


func _button(text: String, handler: Callable, width: int = 0) -> Button:
    var b := Button.new()
    b.text = text
    if width > 0:
        b.custom_minimum_size = Vector2(width, 0)
    b.pressed.connect(handler)
    return b


func rebuild() -> void:
    for c in rows_box.get_children():
        rows_box.remove_child(c)
        c.queue_free()
    for c in bottom_box.get_children():
        bottom_box.remove_child(c)
        c.queue_free()

    for slot in SaveManager.all_slots():
        rows_box.add_child(_slot_row(slot))

    if confirming.get("kind", "") == "new":
        var q := Label.new()
        q.text = "Throw away this game and start a new one?"
        q.add_theme_color_override("font_color", Style.WARN)
        bottom_box.add_child(q)
        bottom_box.add_child(_button("Yes, start over", func() -> void: on_confirm(true)))
        bottom_box.add_child(_button("No", func() -> void: on_confirm(false), 60))
    else:
        bottom_box.add_child(_button("Resume", func() -> void: resume_requested.emit(), 100))
        bottom_box.add_child(_button("New game", on_new_pressed, 100))
        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        bottom_box.add_child(spacer)
        bottom_box.add_child(_button("Quit", func() -> void: quit_requested.emit(), 80))


func _slot_row(slot: String) -> Control:
    var info: Dictionary = SaveManager.describe(slot, save_dir)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)

    var name_l := Label.new()
    name_l.text = SaveManager.label(slot)
    name_l.custom_minimum_size = Vector2(72, 0)
    name_l.add_theme_font_size_override("font_size", 15)
    row.add_child(name_l)

    var detail := Label.new()
    detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    detail.add_theme_font_size_override("font_size", 13)
    if info["valid"]:
        detail.text = "Day %d, %s, %d buildings\n%s" % [int(info["day"]), Style.money0(int(info["money_cents"])), int(info["buildings"]), SaveManager.time_text(int(info["saved_at"]))]
    elif info["exists"]:
        detail.text = "Cannot be read: %s" % SaveManager.reason_text(str(info.get("reason", "")))
        detail.add_theme_color_override("font_color", Style.BAD)
    else:
        detail.text = "Empty"
        detail.add_theme_color_override("font_color", Style.INK_SOFT)
    row.add_child(detail)

    var asking: bool = confirming.get("slot", "") == slot
    if asking:
        var kind: String = str(confirming["kind"])
        detail.text = "Replace this save with the current game?" if kind == "save" else "Throw away the current game and load this one?"
        detail.add_theme_color_override("font_color", Style.WARN)
        row.add_child(_button("Yes", func() -> void: on_confirm(true), 56))
        row.add_child(_button("No", func() -> void: on_confirm(false), 56))
        return row

    if slot != SaveManager.AUTOSAVE:
        row.add_child(_button("Save", func() -> void: on_save_pressed(slot), 64))
    var load_button: Button = _button("Load", func() -> void: on_load_pressed(slot), 64)
    load_button.disabled = not info["valid"]
    row.add_child(load_button)
    return row


func on_save_pressed(slot: String) -> void:
    message_label.text = ""
    if SaveManager.describe(slot, save_dir)["exists"]:
        confirming = {"kind": "save", "slot": slot}
        rebuild()
    else:
        save_requested.emit(slot)


func on_load_pressed(slot: String) -> void:
    message_label.text = ""
    if has_progress:
        confirming = {"kind": "load", "slot": slot}
        rebuild()
    else:
        load_requested.emit(slot)


func on_new_pressed() -> void:
    message_label.text = ""
    if has_progress:
        confirming = {"kind": "new", "slot": ""}
        rebuild()
    else:
        new_game_requested.emit()


func on_confirm(yes: bool) -> void:
    var pending: Dictionary = confirming
    confirming = {}
    if not yes:
        rebuild()
        return
    match str(pending.get("kind", "")):
        "save":
            save_requested.emit(str(pending["slot"]))
        "load":
            load_requested.emit(str(pending["slot"]))
        "new":
            new_game_requested.emit()
