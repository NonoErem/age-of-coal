extends RefCounted
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
        "play", "production", "contracts", "menu":
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
