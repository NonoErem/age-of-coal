# Iron and Coal (working title) - Godot skeleton

Godot 4.3+. Open this folder in the Godot project manager and press F5 for the debug screen.

## Run the tests (no editor needed)

    godot --headless --path . -s tests/market_test.gd     # market and exploit checks
    godot --headless --path . -s tests/sim_test.gd        # map, mines, factories, upkeep, saving
    godot --headless --path . -s tests/contracts_test.gd  # contract board, delivery, penalties, fairness
    godot --headless --path . -s tests/save_test.gd       # save files: slots, damaged and old saves, continuing a loaded game
    godot --headless --path . -s tests/economy_test.gd    # every building must pay for itself (reads the data files)
    godot --headless --path . -s tests/ui_smoke_test.gd   # drives the real screen like a player
    godot --headless --path . -s tests/sam_contract_probe.gd  # informational: buy-to-deliver profit per resource

Exit code 0 means every check passed.

## Layout

- `data/`   balance.json, resources.json, buildings.json, map.json, contracts.json. Tune numbers here, no code changes. Money is in integer cents.
- `sim/`    pure game logic (data loader, market, production, contracts, game state). It never touches UI or scenes.
- `game/`   main screen (coordinator), the tile map view and the save manager.
- `ui/`     Iris's interface: style, top bar, build bar, inspector, event log, Market / Production / Contracts panels, price chart.
- `tools/`  screenshot tool and scenarios (needs a display, e.g. xvfb), used to check layouts.
- `docs/`   screenshots of the interface.
- `tests/`  headless regression tests, including Sam's exploit checks.

## Rules

- The UI sends commands (`buy`, `sell`, `advance_day`) and reads state. It never edits state.
- One seeded RNG: the same seed plus the same commands gives the same game.
- Everything is referenced by string ID from the data files.
- Sim scripts use `preload` instead of `class_name`, so no editor import step is needed for tests.

## Data to confirm with Kenji

Buildings marked `"placeholder": true` in buildings.json (copper smelter, rolling mill, workshop, machine shop)
had no build cost or upkeep in the economy draft. The values there are guesses.
Depth for resources other than coal, steel and machinery defaults to 250 (`default_depth`).

## Rules of the game as built

- A mine or quarry must stand on a deposit of its resource. Everything else goes on free ground.
- Cost = building cost (+10% per building of that type already owned) + the deposit's land cost.
- Mines produce base output x richness per day, tapering off over the last 20% of the deposit. Fractions carry over.
- Factories run up to `batches_per_day` batches a day, as many as their stock allows. With no input at all they are paused (never removed) and restart by themselves.
- A paused factory or a depleted mine pays only 25% of its upkeep (`idle_upkeep_factor`).
- Buildings run in the order they were built. Upkeep is charged every day, and money may go negative (no bankruptcy yet).
- Stock is one shared pool (no warehouse capacity yet).

## The interface

- **Top bar:** day, cash (red when negative), daily upkeep, play/pause, 1x/2x/4x, next day.
  Keys: Space pause, 1/2/3 speed, N next day, Esc stop placing.
- **Map:** click a tile to inspect it. Pick a building in the build bar to enter build mode: legal tiles light up green,
  the tile under the cursor shows green or red, the inspector says why a tile is refused. Right-click or Esc leaves build mode.
  The small dot on a building is its status (green running, amber paused, grey exhausted). The ring on a deposit is what is left.
- **Market tab:** every price with a 120-day chart and 5-day change. Select a row for a big chart and trading.
  The preview shows the total cost, the average price and how far your trade moves the price before you commit.
- **Production tab:** what needs attention (with a Show button), flows per resource with how long the stock lasts, every building.
  The tab title shows a count when something is paused or exhausted.
- **Contracts tab:** offers (with how much they pay over market and what you already hold) and active contracts with progress and days left.
- **Menu (Esc or the Menu button):** three save slots and an autosave (every 10 days), each showing day, cash, buildings and when it was saved.
  Saving over a used slot, loading while you have progress, and starting a new game all ask first. Damaged or old saves are listed with the reason and never crash the game.
  The game is paused while the menu is open. Saves live in `user://saves` (Godot's user data folder for this project).
- **Log:** every build, trade, pause, delivery, failure and warnings before a deadline.

To regenerate the screenshots: `xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/screenshot.gd -- out.png res://tools/shot_scenarios.gd play`
(scenarios: build, build_bad, play, production, contracts, bottleneck).

## How much you move the market

Your trades move a price in proportion to how important you are in that market:

- Each resource has a `market_volume` (units per day everybody trades) in resources.json.
- Your **presence** is what you produce beyond your own factories' needs plus what you trade, averaged over about 10 days.
- `share = (presence + units traded today) / market_volume`. Impact strength runs from 5% (`min_factor`) at no share to 100% at a 25% share (`full_share`).
  Each unit moves the price by `strength / depth`. A single huge order counts toward its own share as it goes.
- So a new company barely dents prices, producing a lot makes you matter even if you never trade, and a company holding a quarter of a market moves it at full strength.
- The Market tab shows "You are x% of this market, so your trades move the price at y% strength", and the trade preview already includes it.
- Tune it in balance.json (`market_impact`) and per resource (`market_volume`, `depth`).

## Contracts (no reputation yet)

- The board holds up to 4 offers; up to 5 contracts can be active. A tutorial offer (40 coal, 30 days) is there on day 1.
- Offers pay 105-135% of the market reference price (so a producer beats selling on the market by at least 15%, but buying goods just to deliver them only pays on the best offers). That price ignores the player's own buying and selling, so it cannot be pumped.
- Offers are only made for what the player could plausibly deliver (stock + production + what money could buy).
- Each delivery is paid straight away. After the deadline, the undelivered part costs a penalty of 40% of its value.
- Contracts use their own random stream, so they never change market prices.

## Not built yet

Reputation, events, transport costs between regions, warehouses, upgrades, demolition, bankruptcy. `GameState.advance_day()`
has the planned order of steps marked in a comment.
