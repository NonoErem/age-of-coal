extends RefCounted
## Look and feel, following Mara's direction: warm paper, ink outlines, soot-grey buildings.
## Also the small formatting helpers every screen shares.

const DESK := Color("b8ab8e")
const PAPER := Color("efe6d2")
const PAPER_LIGHT := Color("faf5e8")
const PAPER_DARK := Color("e2d6ba")
const PAPER_DEEP := Color("cfc1a1")
const INK := Color("2a2622")
const INK_SOFT := Color("6e655a")
const SOOT := Color("3c3c3f")
const FACTORY := Color("5b4636")
const GOOD := Color("3d7a4b")
const WARN := Color("bf7f14")
const BAD := Color("a43a2c")
const SELECT := Color("2c4e7d")


# ---------- formatting ----------

static func num(n: int) -> String:
    var neg: bool = n < 0
    var s: String = str(absi(n))
    var out: String = ""
    while s.length() > 3:
        out = "," + s.substr(s.length() - 3) + out
        s = s.substr(0, s.length() - 3)
    return ("-" if neg else "") + s + out


static func money(cents: int) -> String:
    var neg: bool = cents < 0
    var c: int = absi(cents)
    return "%s$%s.%02d" % ["-" if neg else "", num(floori(c / 100.0)), c % 100]


## No cents, for big totals.
static func money0(cents: int) -> String:
    var neg: bool = cents < 0
    return "%s$%s" % ["-" if neg else "", num(floori(absi(cents) / 100.0))]


static func items_text(items: Dictionary, resources: Dictionary) -> String:
    if items.is_empty():
        return "nothing"
    var parts: Array = []
    for id in items:
        parts.append("%d %s" % [int(items[id]), str(resources[id]["name"]).to_lower()])
    return ", ".join(parts)


## ["iron_ore", "limestone"] -> "iron ore, limestone"
static func names_text(ids: Array, resources: Dictionary) -> String:
    var parts: Array = []
    for id in ids:
        parts.append(str(resources[id]["name"]).to_lower())
    return ", ".join(parts)


static func hex(c: Color) -> String:
    return c.to_html(false)


# ---------- styling ----------

static func box(bg: Color, border: Color = INK, border_w: int = 1, radius: int = 3, pad: int = 6) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(border_w)
    sb.set_corner_radius_all(radius)
    sb.set_content_margin_all(pad)
    return sb


static func mono() -> SystemFont:
    var f := SystemFont.new()
    f.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
    return f


static func make_theme() -> Theme:
    var t := Theme.new()
    t.default_font_size = 14

    t.set_color("font_color", "Label", INK)
    t.set_stylebox("normal", "Label", StyleBoxEmpty.new())

    for type_name in ["Button", "OptionButton"]:
        t.set_stylebox("normal", type_name, box(PAPER_DARK, INK, 1, 3, 6))
        t.set_stylebox("hover", type_name, box(PAPER_LIGHT, INK, 1, 3, 6))
        t.set_stylebox("pressed", type_name, box(PAPER_DEEP, SELECT, 2, 3, 6))
        t.set_stylebox("hover_pressed", type_name, box(PAPER_DEEP, SELECT, 2, 3, 6))
        t.set_stylebox("disabled", type_name, box(PAPER_DARK, PAPER_DEEP, 1, 3, 6))
        t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
            t.set_color(c, type_name, INK)
        t.set_color("font_disabled_color", type_name, INK_SOFT)

    t.set_stylebox("panel", "PanelContainer", box(PAPER, INK, 1, 3, 8))

    var tab_sel: StyleBoxFlat = box(PAPER, INK, 1, 3, 6)
    tab_sel.content_margin_left = 12
    tab_sel.content_margin_right = 12
    tab_sel.corner_radius_bottom_left = 0
    tab_sel.corner_radius_bottom_right = 0
    var tab_un: StyleBoxFlat = box(PAPER_DEEP, INK, 1, 3, 6)
    tab_un.content_margin_left = 12
    tab_un.content_margin_right = 12
    tab_un.corner_radius_bottom_left = 0
    tab_un.corner_radius_bottom_right = 0
    var tab_hover: StyleBoxFlat = tab_un.duplicate()
    tab_hover.bg_color = PAPER_DARK
    t.set_stylebox("tab_selected", "TabContainer", tab_sel)
    t.set_stylebox("tab_unselected", "TabContainer", tab_un)
    t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
    t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
    t.set_stylebox("panel", "TabContainer", box(PAPER, INK, 1, 3, 8))
    t.set_color("font_selected_color", "TabContainer", INK)
    t.set_color("font_unselected_color", "TabContainer", INK_SOFT)
    t.set_color("font_hovered_color", "TabContainer", INK)

    var field: StyleBoxFlat = box(PAPER_LIGHT, INK, 1, 2, 4)
    var field_focus: StyleBoxFlat = box(PAPER_LIGHT, SELECT, 2, 2, 4)
    t.set_stylebox("normal", "LineEdit", field)
    t.set_stylebox("focus", "LineEdit", field_focus)
    t.set_stylebox("read_only", "LineEdit", field)
    t.set_color("font_color", "LineEdit", INK)
    t.set_color("caret_color", "LineEdit", INK)
    t.set_color("selection_color", "LineEdit", Color(SELECT, 0.35))

    t.set_stylebox("background", "ProgressBar", box(PAPER_DEEP, INK, 1, 2, 0))
    t.set_stylebox("fill", "ProgressBar", box(GOOD, GOOD, 0, 2, 0))
    t.set_color("font_color", "ProgressBar", INK)

    t.set_stylebox("panel", "PopupMenu", box(PAPER, INK, 1, 2, 4))
    t.set_stylebox("hover", "PopupMenu", box(PAPER_DEEP, PAPER_DEEP, 0, 2, 2))
    t.set_color("font_color", "PopupMenu", INK)
    t.set_color("font_hover_color", "PopupMenu", INK)

    t.set_stylebox("panel", "TooltipPanel", box(PAPER_LIGHT, INK, 1, 2, 6))
    t.set_color("font_color", "TooltipLabel", INK)

    t.set_color("default_color", "RichTextLabel", INK)
    t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

    t.set_stylebox("scroll", "VScrollBar", box(PAPER_DARK, PAPER_DARK, 0, 2, 0))
    t.set_stylebox("grabber", "VScrollBar", box(PAPER_DEEP, INK_SOFT, 1, 2, 0))
    t.set_stylebox("grabber_highlight", "VScrollBar", box(INK_SOFT, INK, 1, 2, 0))
    t.set_stylebox("grabber_pressed", "VScrollBar", box(INK_SOFT, INK, 1, 2, 0))

    var line := StyleBoxLine.new()
    line.color = INK_SOFT
    line.thickness = 1
    t.set_stylebox("separator", "HSeparator", line)
    return t
