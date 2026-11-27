extends VBoxContainer
## The "Orders" tab: standing orders and rules side by side, one shown at a time.

const Style = preload("res://ui/style.gd")
const OrdersPanel = preload("res://ui/orders_panel.gd")
const RulesPanel = preload("res://ui/rules_panel.gd")

signal changed()
signal message(text: String, kind: String)

var orders_panel
var rules_panel
var order_button: Button
var rule_button: Button


func setup(p_state) -> void:
    add_theme_constant_override("separation", 6)
    var bar := HBoxContainer.new()
    bar.add_theme_constant_override("separation", 4)
    add_child(bar)
    var group := ButtonGroup.new()
    order_button = _tab_button("Standing orders", group)
    rule_button = _tab_button("Rules", group)
    bar.add_child(order_button)
    bar.add_child(rule_button)
    orders_panel = OrdersPanel.new()
    orders_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    orders_panel.setup(p_state)
    orders_panel.changed.connect(func() -> void: changed.emit())
    orders_panel.message.connect(func(t: String, k: String) -> void: message.emit(t, k))
    add_child(orders_panel)
    rules_panel = RulesPanel.new()
    rules_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    rules_panel.setup(p_state)
    rules_panel.changed.connect(func() -> void: changed.emit())
    rules_panel.message.connect(func(t: String, k: String) -> void: message.emit(t, k))
    add_child(rules_panel)
    order_button.toggled.connect(func(_on: bool) -> void: _show())
    order_button.button_pressed = true
    _show()


func _tab_button(text: String, group: ButtonGroup) -> Button:
    var b := Button.new()
    b.text = text
    b.toggle_mode = true
    b.button_group = group
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return b


func _show() -> void:
    orders_panel.visible = order_button.button_pressed
    rules_panel.visible = not order_button.button_pressed


func show_rules() -> void:
    rule_button.button_pressed = true
    _show()


func refresh() -> void:
    orders_panel.refresh()
    rules_panel.refresh()
