extends PanelContainer
## Shows what is on the selected tile, or whether the chosen building fits there.

const Style = preload("res://ui/style.gd")
const ArtLibrary = preload("res://game/art_library.gd")
const Survey = preload("res://sim/survey.gd")
const Production = preload("res://sim/production.gd")
const Crisis = preload("res://sim/crisis.gd")
const People = preload("res://sim/people.gd")

signal stop_toggled(uid: int)
signal repair_requested(uid: int)
signal demolish_confirmed(uid: int)

var state
var tool_id: String = ""
var survey_level: int = 0
var selected: Vector2i = Vector2i(-1, -1)
var icon_holder: HBoxContainer
var icon: TextureRect
var title_label: Label
var detail_label: Label
var bar: ProgressBar
var actions: VBoxContainer
var confirming_uid: int = -1


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
    actions = VBoxContainer.new()
    actions.add_theme_constant_override("separation", 4)
    actions.custom_minimum_size = Vector2(112, 0)
    icon_holder.add_child(actions)
    refresh()


func refresh() -> void:
    bar.visible = false
    icon.texture = null
    icon.visible = false
    for c in actions.get_children():
        actions.remove_child(c)
        c.queue_free()
    detail_label.add_theme_color_override("font_color", Style.INK_SOFT)
    if selected.x < 0:
        title_label.text = "Nothing selected"
        detail_label.text = "Click a tile to inspect it. Pick a building below to place one."
        if survey_level > 0:
            detail_label.text = _survey_hint(-1, -1)
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
        var res_names: Callable = func(ids: Array) -> String: return Style.names_text(ids, res)
        var damaged: bool = Crisis.is_damaged(state, b)
        if damaged and not Crisis.holds_post(str(def["kind"])):
            lines.append("Damaged: it does nothing until repaired (%d of %d health)." % [int(b["health"]), Crisis.max_health(state, b)])
            detail_label.add_theme_color_override("font_color", Style.BAD)
        if def["kind"] == "defense":
            match status:
                "firing":
                    lines.append("Firing.")
                "no_ammo":
                    lines.append("Creatures in reach, but no %s to fire!" % Style.names_text(def.get("ammo", {}).keys(), res))
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "stopped":
                    lines.append("Stopped by you. It does not fire.")
                    detail_label.add_theme_color_override("font_color", Style.SELECT)
                "no_crew":
                    lines.append("Nobody to man it! It does not fire.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                _:
                    lines.append("Ready. Nothing in reach.")
            var aim: float = Crisis.aim(state, x, y)
            var hit: int = maxi(1, int(round(float(def["damage"]) * People.crew_ratio(state, b) * aim)))
            lines.append("Reach %d tiles, %d damage a day%s, uses %s on each day it fires. Health %d of %d%s." % [int(def["range"]), hit, (" (%d%% in the dark)" % int(round(aim * 100.0))) if aim < 0.995 else (" (lit)" if Crisis.light_at(state, x, y) > 0.0 and Crisis.darkness(state) > 0.0 else ""), Style.items_text(def.get("ammo", {}), res), int(b["health"]), Crisis.max_health(state, b), " (keeps firing while damaged)" if damaged else ""])
        elif def["kind"] == "shelter":
            var pt: Dictionary = People.totals(state)
            match status:
                "unsafe":
                    lines.append("No supplied defense reaches it: refugees will not stay here.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "stopped":
                    lines.append("Stopped by you. Nobody is housed.")
                    detail_label.add_theme_color_override("font_color", Style.SELECT)
                "housing":
                    lines.append("Open. Your people: %d in %d places, food for %s." % [state.people, int(pt["housing"]), ("%d days" % People.food_days(state)) if People.food_days(state) >= 0 else "everyone"])
                _:
                    lines.append("Ready. Refugees come once the creatures land.")
            lines.append("Houses %d. Needs a supplied defense in reach and food in your granaries. Health %d of %d." % [int(def["housing"]), int(b["health"]), Crisis.max_health(state, b)])
        elif def["kind"] == "light":
            match status:
                "lit":
                    lines.append("Lit.")
                "no_supplies":
                    lines.append("Out of %s! It is dark." % Style.names_text(def.get("supplies", {}).keys(), res))
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "stopped":
                    lines.append("Stopped by you. It is dark.")
                    detail_label.add_theme_color_override("font_color", Style.SELECT)
                _:
                    lines.append("Ready. It lights up when night falls." if Crisis.darkness(state) <= 0.0 else "Dark: nobody to run it.")
            lines.append("Lights defenses within %d tiles, burns %s a night. Darkness now %d%%. Health %d of %d." % [int(def["range"]), Style.items_text(def.get("supplies", {}), res), int(round(Crisis.darkness(state) * 100.0)), int(b["health"]), Crisis.max_health(state, b)])
        elif def["kind"] == "granary":
            lines.append("Keeps %d food. In store: %d of %d food, spoiling %s%% a day." % [int(def["food_capacity"]), state.food_stored(), state.food_capacity(), str(float(state.data["balance"]["people"]["spoil_per_day"]) * 100.0)])
        elif damaged:
            pass
        elif def["kind"] == "storage":
            lines.append("Adds room for %d units. In store: %d of %d, yard and warehouses together." % [int(def["capacity"]), state.stored_units(), state.capacity()])
        elif def["kind"] == "factory":
            match status:
                "paused_missing_input":
                    lines.append("Paused: missing %s" % res_names.call(b["missing"]))
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "paused_storage_full":
                    lines.append("Stopped: nowhere to put what it makes. Storage is full.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "stopped":
                    lines.append("Stopped by you. It makes and uses nothing.")
                    detail_label.add_theme_color_override("font_color", Style.SELECT)
                "no_crew":
                    lines.append("Nobody to work it.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "running":
                    lines.append("Running %d of %d batches" % [int(b["batches"]), int(def.get("batches_per_day", 1))])
                _:
                    lines.append("Starts on the next day")
            lines.append("Each batch: %s into %s" % [Style.items_text(def["inputs"], res), Style.items_text(def["outputs"], res)])
        else:
            match status:
                "depleted":
                    lines.append("Deposit exhausted. Demolish it to stop paying upkeep.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "paused_storage_full":
                    lines.append("Stopped digging: storage is full.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                "stopped":
                    lines.append("Stopped by you. Nothing is dug.")
                    detail_label.add_theme_color_override("font_color", Style.SELECT)
                "no_crew":
                    lines.append("Nobody to work it. Nothing is dug.")
                    detail_label.add_theme_color_override("font_color", Style.WARN)
                _:
                    lines.append("Produces %s a day, times richness" % Style.items_text(def["outputs"], res))
        if Crisis.announced(state) and not Crisis.holds_post(str(def["kind"])):
            var cover: int = Crisis.covered_by(state, x, y).size()
            lines.append("Covered by %d defense%s." % [cover, "" if cover == 1 else "s"] if cover > 0 else "Not covered by any defense.")
        if damaged:
            bar.visible = true
            bar.max_value = float(Crisis.max_health(state, b))
            bar.value = float(b["health"])
        var idle: float = float(state.data["balance"]["idle_upkeep_factor"])
        var upkeep_now: int = Production.upkeep_of(def, status, idle, People.upkeep_mult(state, b))
        var crew: int = People.crew_of(def)
        var head: String = ""
        if crew > 0:
            var have: int = int(b.get("crew_yours", 0)) + int(b.get("crew_hired", 0))
            head = "Crew %d/%d (%d yours, %d hired)%s. " % [have, crew, int(b.get("crew_yours", 0)), int(b.get("crew_hired", 0)), (", working at %d%%" % int(round(People.crew_ratio(state, b) * 100.0))) if have < crew else ""]
            if have < crew:
                detail_label.add_theme_color_override("font_color", Style.WARN)
        var tail: String = ""
        if Crisis.landed(state) and crew > 0:
            var li: Dictionary = Crisis.labour_info(state, x, y)
            tail = " Hired workers: %s%s." % ["plenty (protected)" if float(li["safety"]) >= 0.99 else ("some (partly protected)" if float(li["safety"]) > 0.0 else "few (exposed)"), (", %d%% cheaper" % int(round(float(li["discount"]) * 100.0))) if float(li["discount"]) > 0.005 else ""]
        lines.append("%sUpkeep %s/day%s.%s" % [head, Style.money(upkeep_now), " (idle rate)" if Production.IDLE_STATUSES.has(status) else "", tail])
        _build_actions(b, def)
    elif dep_id != "":
        var info: Dictionary = state.data["map"]["deposits"][dep_id]
        icon.texture = ArtLibrary.deposit(str(info["resource"]))
        title_label.text = "%s deposit at (%d, %d)" % [str(res[info["resource"]]["name"]), x, y]
        var remaining: int = int(state.deposits[dep_id]["remaining"])
        lines.append("Richness x%.1f. %s of %s left. Land %s" % [float(info["richness"]), Style.num(remaining), Style.num(int(info["amount"])), Style.money0(int(info["land_cost"]))])
        if int(info.get("depth", 0)) > 0:
            lines.append("A deep deposit, found by a level %d survey." % int(info["depth"]))
        bar.visible = true
        bar.max_value = float(info["amount"])
        bar.value = float(remaining)
    else:
        title_label.text = "Free ground at (%d, %d)" % [x, y]
        lines.append("Room for a factory.")
    for a in Crisis.aliens_near(state, x, y, 0):
        var ad: Dictionary = Crisis.alien_def(state, str(a["type"]))
        if b.is_empty() and dep_id == "":
            title_label.text = "%s at (%d, %d)" % [str(ad.get("name", a["type"])), x, y]
            icon.texture = ArtLibrary.alien(str(a["type"]))
            lines.clear()
        lines.append("%s: %d of %d health, hits a building next to it for %d a day, moves %d tile%s a day. %s" % [str(ad.get("name", a["type"])), int(a["hp"]), int(a["max_hp"]), int(a["attack"]), int(a["speed"]), "" if int(a["speed"]) == 1 else "s", str(ad.get("text", ""))])
        detail_label.add_theme_color_override("font_color", Style.BAD)

    if tool_id != "" and b.is_empty():
        var def2: Dictionary = state.data["buildings"][tool_id]
        var why: String = state.check_placement(tool_id, x, y)
        if why == "":
            var cost: int = state.build_cost(tool_id, dep_id, x, y)
            lines.append("Click to place %s for %s%s" % [str(def2["name"]), Style.money(cost), "" if cost <= state.money_cents else " (not enough cash)"])
        else:
            lines.append("%s cannot go here: %s" % [str(def2["name"]), reason_text(why)])
    if survey_level > 0:
        lines.append(_survey_hint(x, y))
    icon.visible = icon.texture != null
    detail_label.text = "\n".join(lines)


## What the chosen survey would do on this tile (x < 0: just describe the tool).
func _survey_hint(x: int, y: int) -> String:
    var side: int = int(state.data["map"]["survey"]["radius"]) * 2 + 1
    var name_text: String = Survey.level_name(state, survey_level)
    var price: int = Survey.cost(state, survey_level)
    var reach: String = "ore just under the surface" if survey_level == 1 else "ore at every depth"
    var text: String = "%s: %s. Click the map to survey a %d by %d area for %s; it reveals %s. You pay whatever is found." % [name_text, "ready", side, side, Style.money0(price), reach]
    if x >= 0:
        var why: String = Survey.check(state, x, y, survey_level)
        if why != "":
            text = "%s here: %s" % [name_text, Survey.reason_text(why)]
        else:
            text = "Click to run a %s here for %s%s. %d of the %d tiles around here are new to you." % [name_text.to_lower(), Style.money(price), "" if price <= state.money_cents else " (not enough cash)", Survey.new_tiles(state, x, y, survey_level), Survey.area(state, x, y).size.x * Survey.area(state, x, y).size.y]
    return text


func _build_actions(b: Dictionary, def: Dictionary) -> void:
    var uid: int = int(b["uid"])
    if confirming_uid != uid:
        confirming_uid = -1
    var fix: int = state.repair_cost(uid)
    if fix > 0:
        var rb := Button.new()
        rb.text = "Repair %s" % Style.money0(fix)
        rb.tooltip_text = "Bring it back to full health. Costs %d%% of its build price for full damage, less for a little." % int(round(float(state.data["crisis"].get("damage", {}).get("repair_rate", 0.5)) * 100.0))
        rb.disabled = fix > state.money_cents
        rb.pressed.connect(func() -> void: repair_requested.emit(uid))
        actions.add_child(rb)
    if def["kind"] != "storage":
        var stopped: bool = bool(b.get("stopped", false))
        var stop_button := Button.new()
        stop_button.text = "Restart" if stopped else "Stop"
        stop_button.tooltip_text = "Start it again. It begins on the next day. (P)" if stopped else "Stop it for now. It makes and uses nothing and pays a quarter of its upkeep. (P)"
        stop_button.pressed.connect(on_stop_pressed)
        actions.add_child(stop_button)
    var refund: int = state.demolish_refund(uid)
    if confirming_uid == uid:
        var q := Label.new()
        q.text = "Demolish for +%s?" % Style.money0(refund)
        q.add_theme_font_size_override("font_size", 12)
        q.add_theme_color_override("font_color", Style.WARN)
        actions.add_child(q)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 4)
        var yes := Button.new()
        yes.text = "Yes"
        yes.pressed.connect(func() -> void: on_confirm(true))
        row.add_child(yes)
        var no := Button.new()
        no.text = "No"
        no.pressed.connect(func() -> void: on_confirm(false))
        row.add_child(no)
        actions.add_child(row)
    else:
        var demolish := Button.new()
        demolish.text = "Demolish"
        demolish.tooltip_text = "Pull it down and get %s back (30%% of what you paid, land included)." % Style.money(refund)
        demolish.pressed.connect(on_demolish_pressed)
        actions.add_child(demolish)


func selected_uid() -> int:
    if selected.x < 0:
        return -1
    var b: Dictionary = state.building_at(selected.x, selected.y)
    return -1 if b.is_empty() else int(b["uid"])


func on_stop_pressed() -> void:
    var uid: int = selected_uid()
    if uid >= 0:
        stop_toggled.emit(uid)


func on_demolish_pressed() -> void:
    var uid: int = selected_uid()
    if uid >= 0:
        confirming_uid = uid
        refresh()


func on_confirm(yes: bool) -> void:
    var uid: int = confirming_uid
    confirming_uid = -1
    if yes and uid >= 0:
        demolish_confirmed.emit(uid)
    refresh()


static func reason_text(reason: String) -> String:
    match reason:
        "no_deposit": return "it needs a deposit."
        "wrong_deposit": return "that is the wrong kind of deposit."
        "deposit_tile_reserved": return "deposits are kept for mines."
        "tile_occupied": return "there is a building here already."
        "out_of_bounds": return "outside the map."
        "not_available_yet": return "not available yet."
        "storage_full": return "there is no room in storage."
        "storage_in_use": return "your stock would no longer fit without it."
        "insufficient_funds": return "not enough cash."
        "alien_here": return "a creature is standing there."
    return reason
