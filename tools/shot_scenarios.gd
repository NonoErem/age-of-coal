extends RefCounted

const Crisis = preload("res://sim/crisis.gd")
## Sets the game up in a few interesting situations so the screens can be photographed.

func _find(state, resource: String, richness: float) -> Vector2i:
    for id in state.data["map"]["deposits"]:
        var d: Dictionary = state.data["map"]["deposits"][id]
        if d["resource"] == resource and is_equal_approx(float(d["richness"]), richness):
            return Vector2i(int(d["x"]), int(d["y"]))
    return Vector2i(-1, -1)


func run(scene: Control, name: String) -> void:
    var s = scene.state
    match name:
        "build":
            scene.set_tool("coal_mine")
            var p: Vector2i = _find(s, "coal", 1.0)
            scene.map_view.hover = p
            scene.select_tile(p.x, p.y)
        "build_bad":
            scene.set_tool("iron_mine")
            var p2: Vector2i = _find(s, "coal", 1.0)
            scene.map_view.hover = p2
            scene.select_tile(p2.x, p2.y)
        "storage":
            s.money_cents = 6000000
            var sc: Vector2i = _find(s, "coal", 1.0)
            var si: Vector2i = _find(s, "iron_ore", 1.0)
            scene.set_tool("coal_mine")
            scene.map_clicked(sc.x, sc.y)
            scene.set_tool("iron_mine")
            scene.map_clicked(si.x, si.y)
            scene.set_tool("coke_oven")
            scene.map_clicked(9, 7)
            scene.set_tool("warehouse")
            scene.map_clicked(12, 8)
            scene.clear_tool()
            s.demolish(int(s.buildings[3]["uid"]))  # no warehouse yet: the yard is the only storage
            s.inventory = {"coal": 110, "iron_ore": 60, "steel": 70}
            s.set_building_stopped(int(s.buildings[1]["uid"]), true)
            for d in 4:
                s.advance_day()
                scene._log_day()
            scene.select_tile(sc.x, sc.y)
            scene.tabs.current_tab = 1
            scene.refresh_all()
        "bottleneck":
            s.money_cents = 6000000
            var c1: Vector2i = _find(s, "coal", 1.0)
            scene.set_tool("coal_mine")
            scene.map_clicked(c1.x, c1.y)
            scene.set_tool("coke_oven")
            scene.map_clicked(9, 7)
            scene.set_tool("blast_furnace")
            scene.map_clicked(11, 7)
            scene.clear_tool()
            s.inventory["iron_ore"] = 0
            for d in 5:
                s.advance_day()
                scene._log_day()
            scene.select_tile(11, 7)
            scene.tabs.current_tab = 1
            scene.refresh_all()
        "telegram":
            s.data["events"]["chance_per_day"] = 0.0
            for d in 329:
                s.advance_day()
            scene._log_day()
            scene.refresh_all()
        "invasion", "invasion_late":
            s.data["events"]["chance_per_day"] = 0.0
            s.money_cents = 50000000
            for spot in [["coke_oven", 9, 7], ["blast_furnace", 11, 7], ["steelworks", 13, 8], ["warehouse", 10, 9], ["munitions_works", 12, 10], ["mg_nest", 7, 5], ["mg_nest", 15, 6], ["mg_nest", 8, 11], ["field_battery", 12, 5]]:
                s.build(spot[0], spot[1], spot[2])
            for id in s.revealed_deposit_ids():
                var d: Dictionary = s.data["map"]["deposits"][id]
                if abs(int(d["x"]) - 11) <= 6 and abs(int(d["y"]) - 8) <= 5:
                    s.build({"coal": "coal_mine", "iron_ore": "iron_mine", "limestone": "limestone_quarry", "copper_ore": "copper_mine"}[d["resource"]], int(d["x"]), int(d["y"]))
            s.money_cents = 4200000
            for d in 455:
                if s.stock("munitions") < 20:
                    s.inventory["munitions"] = s.stock("munitions") + 20
                for b in s.buildings:
                    if Crisis.is_damaged(s, b):
                        s.money_cents += s.repair_cost(int(b["uid"]))
                        s.repair(int(b["uid"]))
                s.advance_day()
            s.money_cents = 3850000
            for d in 18:
                s.advance_day()
                scene._log_day()
            scene.telegram.close()
            var hit: Dictionary = {}
            for b in s.buildings:
                if int(b["health"]) < Crisis.max_health(s, b) and str(s.data["buildings"][b["type"]]["kind"]) != "defense":
                    hit = b
            if hit.is_empty():
                hit = s.buildings[2]
                hit["health"] = 70
                hit["status"] = "damaged"
            scene.map_view.cover_button.button_pressed = true
            scene.select_tile(int(hit["x"]), int(hit["y"]))
            scene.market_panel.select_resource("munitions")
            if name == "invasion_late":
                s.day += 420
                Crisis.apply_market(s)
            scene.refresh_all()
            scene.night.color = Crisis.night_tint(s)
        "refuge", "night_lights":
            s.data["events"]["chance_per_day"] = 0.0
            s.money_cents = 90000000
            for spot in [["coke_oven", 9, 7], ["blast_furnace", 11, 7], ["steelworks", 13, 8], ["warehouse", 10, 9], ["munitions_works", 12, 10], ["mg_nest", 8, 5], ["mg_nest", 14, 6], ["field_battery", 11, 5], ["shelter", 12, 6], ["shelter", 10, 8], ["granary", 8, 9], ["searchlight", 9, 5], ["coke_oven", 28, 16], ["mg_nest", 7, 8]]:
                var placed: bool = false
                for rr in 4:
                    for dy in range(-rr, rr + 1):
                        for dx in range(-rr, rr + 1):
                            if not placed and s.check_placement(spot[0], spot[1] + dx, spot[2] + dy) == "":
                                s.build(spot[0], spot[1] + dx, spot[2] + dy)
                                placed = true
            var days: int = 420 if name == "refuge" else 600
            for d in days:
                s.inventory["munitions"] = maxi(s.stock("munitions"), 40)
                s.inventory["coal"] = maxi(s.stock("coal"), 60)
                s.inventory["food"] = maxi(s.stock("food"), mini(s.food_capacity(), 150))
                s.money_cents = maxi(s.money_cents, 5000000)
                for b in s.buildings:
                    if Crisis.is_damaged(s, b):
                        s.repair(int(b["uid"]))
                s.advance_day()
            scene.telegram.close()
            scene.select_tile(9, 7)
            scene.refresh_all()
            scene.night.color = Crisis.night_tint(s)
        "bright":
            s.data["events"]["chance_per_day"] = 0.0
            s.money_cents = 9000000
            for spot in [["coke_oven", 9, 7], ["blast_furnace", 11, 7], ["warehouse", 10, 9]]:
                s.build(spot[0], spot[1], spot[2])
            for d in 12:
                s.advance_day()
            scene.select_tile(9, 7)
            scene.refresh_all()
        "dusk":
            s.data["events"]["chance_per_day"] = 0.0
            for d in 372:
                s.advance_day()
            scene.refresh_all()
            scene.night.color = Crisis.night_tint(s)
        "survey":
            s.money_cents = 3000000
            s.data["events"]["chance_per_day"] = 0.0
            scene.set_survey(1)
            scene.map_clicked(22, 12)
            scene.set_survey(2)
            scene.map_clicked(22, 14)
            scene.map_clicked(24, 18)
            scene.set_survey(2)
            scene.map_view.hover = Vector2i(14, 5)
            scene.select_tile(22, 13)
            scene.refresh_all()
            scene.map_view.queue_redraw()
        "rules":
            s.money_cents = 3000000
            s.data["events"]["chance_per_day"] = 0.0
            s.add_rule("coal", "keep", 100)
            s.add_rule("steel", "sell_above", 20, 9000)
            s.add_rule("iron_ore", "keep", 40, 1200, 15, 500000)
            for d in 8:
                s.advance_day()
                scene._log_day()
            scene.tabs.current_tab = 3
            scene.automation_panel.show_rules()
            scene.rules_panel.kind_pick.select(1)
            scene.rules_panel.res_pick.select(scene.rules_panel.resource_ids.find("copper_ore"))
            scene.refresh_all()
        "play", "production", "contracts", "menu", "news", "newsmarket", "orders", "companies", "rivalmarket":
            s.money_cents = 6000000
            var coal: Vector2i = _find(s, "coal", 1.0)
            var iron: Vector2i = _find(s, "iron_ore", 1.0)
            var lime: Vector2i = _find(s, "limestone", 1.0)
            scene.set_tool("coal_mine")
            scene.map_clicked(coal.x, coal.y)
            scene.set_tool("iron_mine")
            scene.map_clicked(iron.x, iron.y)
            scene.set_tool("limestone_quarry")
            scene.map_clicked(lime.x, lime.y)
            scene.set_tool("coke_oven")
            scene.map_clicked(9, 7)
            scene.set_tool("blast_furnace")
            scene.map_clicked(11, 7)
            scene.set_tool("steelworks")
            scene.map_clicked(13, 8)
            scene.clear_tool()
            var coal2: Vector2i = _find(s, "coal", 0.6)
            scene.set_tool("coal_mine")
            scene.map_clicked(coal2.x, coal2.y)
            scene.clear_tool()
            for d in 34:
                if d == 10:
                    s.sell("coal", 25)
                if d == 20:
                    s.sell("coal", 25)
                s.advance_day()
                scene._log_day()
            scene.accept_offer_for_test()
            scene.select_tile(9, 7)
            scene.market_panel.select_resource("coal")
            scene.refresh_all()
            if name == "production":
                scene.tabs.current_tab = 1
            if name == "contracts":
                scene.tabs.current_tab = 2
            if name == "orders":
                s.data["events"]["chance_per_day"] = 0.0
                s.start_standing_order("coal", "sell", 20, 30)
                s.start_standing_order("iron_ore", "buy", 10, 12, 1500)
                s.start_standing_order("steel", "sell", 15, 20, 9500)
                for d in 5:
                    s.advance_day()
                    scene._log_day()
                scene.tabs.current_tab = 3
                scene.orders_panel.side_pick.select(0)
                scene.orders_panel.res_pick.select(scene.orders_panel.resource_ids.find("coal"))
                scene.refresh_all()
            if name == "news" or name == "newsmarket":
                var ME = load("res://sim/market_events.gd")
                s.data["events"]["chance_per_day"] = 0.0
                var strike: Dictionary = ME.announce(s, "miners_strike")
                strike["start_day"] = s.day + 1
                strike["end_day"] = s.day + 20
                s.advance_day()
                ME.announce(s, "shipbuilding")
                scene._log_day()
                scene.market_panel.select_resource("coal")
                scene.tabs.current_tab = 5 if name == "news" else 0
                scene.refresh_all()
            if name == "companies" or name == "rivalmarket":
                s.data["events"]["chance_per_day"] = 0.0
                s.money_cents = 6000000
                s.rivals["northern"]["cash"] = -1000000000
                s.rivals["albion"]["strength"] = 0.62
                s.rivals["albion"]["status"] = "weakened"
                s.rivals["albion"]["cash"] = 60000
                s.buy_company("midland")
                for d in 12:
                    s.advance_day()
                    scene._log_day()
                scene.tabs.current_tab = 4 if name == "companies" else 0
                scene.market_panel.select_resource("rails")
                scene.refresh_all()
            if name == "menu":
                var SaveManager = load("res://game/save_manager.gd")
                scene.save_dir = "user://shots_saves"
                for slot in SaveManager.all_slots():
                    SaveManager.delete_save(slot, scene.save_dir)
                SaveManager.save(s, "slot_1", scene.save_dir)
                for d in 6:
                    s.advance_day()
                SaveManager.save(s, SaveManager.AUTOSAVE, scene.save_dir)
                var f: FileAccess = FileAccess.open(SaveManager.path("slot_3", scene.save_dir), FileAccess.WRITE)
                f.store_string("{ broken")
                f.close()
                scene.open_menu()
                scene.menu.on_save_pressed("slot_1")
