extends Control
## A telegram across the screen for the moments that change everything (the announcement, the first landing).
## The game pauses while it is shown.

const Style = preload("res://ui/style.gd")

signal closed()

var title_label: Label
var body_label: Label


func setup() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    visible = false
    var shade := ColorRect.new()
    shade.color = Color(0, 0, 0, 0.45)
    shade.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(shade)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(520, 0)
    panel.add_theme_stylebox_override("panel", Style.box(Color.html("#d9cdaa"), Style.INK, 2, 2, 18))
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    panel.add_child(box)
    var head := Label.new()
    head.text = "TELEGRAM"
    head.add_theme_font_size_override("font_size", 13)
    head.add_theme_color_override("font_color", Style.INK_SOFT)
    head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(head)
    title_label = Label.new()
    title_label.add_theme_font_size_override("font_size", 20)
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(title_label)
    box.add_child(HSeparator.new())
    body_label = Label.new()
    body_label.add_theme_font_size_override("font_size", 14)
    body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body_label.custom_minimum_size = Vector2(480, 0)
    box.add_child(body_label)
    var ok := Button.new()
    ok.text = "Carry on"
    ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    ok.custom_minimum_size = Vector2(140, 0)
    ok.pressed.connect(close)
    box.add_child(ok)


func show_telegram(title: String, body: String) -> void:
    title_label.text = title
    body_label.text = body
    visible = true


func close() -> void:
    visible = false
    closed.emit()
