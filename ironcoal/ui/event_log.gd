extends PanelContainer
## A running log of what happened. Newest at the bottom.

const Style = preload("res://ui/style.gd")

var text: RichTextLabel


func setup() -> void:
    custom_minimum_size = Vector2(0, 60)
    text = RichTextLabel.new()
    text.bbcode_enabled = true
    text.scroll_following = true
    text.selection_enabled = false
    text.add_theme_font_size_override("normal_font_size", 13)
    add_child(text)


func add(message: String, kind: String = "info", day: int = 0) -> void:
    var color: Color = Style.INK
    match kind:
        "good": color = Style.GOOD
        "warn": color = Style.WARN
        "bad": color = Style.BAD
        "info": color = Style.INK_SOFT
    var prefix: String = ("[color=#%s]Day %d[/color]  " % [Style.hex(Style.INK_SOFT), day]) if day > 0 else ""
    text.append_text("%s[color=#%s]%s[/color]\n" % [prefix, Style.hex(color), message])
