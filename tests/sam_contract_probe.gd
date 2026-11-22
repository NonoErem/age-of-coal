extends SceneTree
## Sam's probe (informational, always exits 0): can a player profit by BUYING goods on the market
## and delivering them to contracts? Prints the profit % at the lowest and highest premium,
## for the largest contract size of each resource.
##   godot --headless --path . -s tests/sam_contract_probe.gd

const DataLoader = preload("res://sim/data_loader.gd")
const GameState = preload("res://sim/game_state.gd")


func _init() -> void:
    var gd: Dictionary = DataLoader.load_game_data()
    var bal: Dictionary = gd["balance"].duplicate(true)
    bal["trend_volatility"] = 0.0
    bal["trend_reversion"] = 0.0
    gd = gd.duplicate()
    gd["balance"] = bal
    var cfg: Dictionary = gd["contracts"]
    var lo_p: float = float(cfg["premium"][0])
    var hi_p: float = float(cfg["premium"][1])
    print("%-13s %5s %12s %12s" % ["Resource", "Qty", "profit@%.2f" % lo_p, "profit@%.2f" % hi_p])
    for res in cfg["quantities"]:
        var gs = GameState.new(gd)
        var qty: int = int(cfg["quantities"][res][1])
        var cost: float = float(gs.market.quote_buy(res, qty))
        var ref: float = gs.market.reference_price(res)
        var lo: float = ref * lo_p * qty
        var hi: float = ref * hi_p * qty
        print("%-13s %5d %+11.1f%% %+11.1f%%" % [str(gd["resources"][res]["name"]), qty, 100.0 * (lo - cost) / cost, 100.0 * (hi - cost) / cost])
    quit(0)
