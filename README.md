# Iron and Coal (working title) - Godot skeleton

Godot 4.3+. Open this folder in the Godot project manager and press F5 for the debug screen.

## Run the tests (no editor needed)

    godot --headless --path . -s tests/market_test.gd     # market and exploit checks
    godot --headless --path . -s tests/sim_test.gd        # map, mines, factories, upkeep, saving
    godot --headless --path . -s tests/contracts_test.gd  # contract board, delivery, penalties, fairness
    godot --headless --path . -s tests/save_test.gd       # save files: slots, damaged and old saves, continuing a loaded game
    godot --headless --path . -s tests/events_test.gd     # market events: timeline, stacking, exposure, offers, saving
    godot --headless --path . -s tests/art_test.gd        # every building, resource and deposit has well-formed art
    godot --headless --path . -s tests/economy_test.gd    # every building must pay for itself (reads the data files)
    godot --headless --path . -s tests/ui_smoke_test.gd   # drives the real screen like a player
    godot --headless --path . -s tests/sam_contract_probe.gd  # informational: buy-to-deliver profit per resource
    godot --headless --path . -s tests/sam_event_probe.gd     # informational: profit from speculating on an announced event

Exit code 0 means every check passed.

## Layout

- `data/`   balance.json, resources.json, buildings.json, map.json, contracts.json, events.json. Tune numbers here, no code changes. Money is in integer cents.
- `sim/`    pure game logic (data loader, market, market events, production, contracts, game state). It never touches UI or scenes.
- `game/`   main screen (coordinator), the tile map view and the save manager.
- `ui/`     Iris's interface: style, top bar, build bar, inspector, event log, Market / Production / Contracts panels, price chart.
- `art/`    the pictures, as SVG: buildings/, deposits/, resources/ (see Art below).
- `tools/`  screenshot tool and scenarios (needs a display, e.g. xvfb), the art contact sheet, and make_art.py (the art generator).
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
- **News tab:** events announced, running and recently over, with their effect on prices, how long they last and what you hold of the goods involved.
  In the Market tab an amber "!" marks resources an event is moving; hover a row or look under the chart for details.
- **Log:** every build, trade, pause, delivery, failure and warnings before a deadline.

To regenerate the screenshots: `xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/screenshot.gd -- out.png res://tools/shot_scenarios.gd play`
(scenarios: build, build_bad, play, production, contracts, bottleneck).

## Art

All pictures are SVG, 64 x 64 units, in `art/`:

- `art/buildings/<building id>.svg`: one per building in buildings.json (shown on the map, in the build bar, in the inspector and in the Production tab).
- `art/resources/<resource id>.svg`: one icon per resource (Market, Production flows and Contracts).
- `art/deposits/<resource id>.svg`: the ore patch for each resource that has a deposit on the map. Richer deposits are drawn bigger.

Style (Mara's direction): warm paper, ink outlines about 2 units thick, soot-grey roofs and brown walls, a little fire orange. Elevation views, ground line at y = 58.

- **Replacing a picture:** overwrite the file with the same name. No code changes. Keep it 64 x 64 and avoid text, filters and gradients (the loader renders plain shapes).
- **Adding a building or resource:** add its SVG under the same id. `tests/art_test.gd` fails if a picture is missing, malformed, empty, or left over from something removed.
- **If a picture is missing** the game still runs: the map falls back to a plain square and panels to a coloured chip.
- `tools/make_art.py` regenerates all the SVGs with a consistent palette. Once generated, the SVG files are the source of truth, edit them directly if you prefer.
- `tools/art_sheet.gd` renders a contact sheet of everything at game sizes: `xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/art_sheet.gd -- sheet.png`
- **Exporting the game:** include the art as non-resource files (Project > Export > Resources > "Filters to export non-resource files": `art/*`), because the SVGs are read as plain files.
- The map is drawn like a survey sheet: pencil hatching on empty ground (the same every time), a ruled grid, and coordinates along the top and left edges that match the (x, y) shown in the inspector.
  A ring around a mine shows how much of its deposit is left.

## How much you move the market

Your trades move a price in proportion to how important you are in that market:

- Each resource has a `market_volume` (units per day everybody trades) in resources.json.
- Your **presence** is what you produce beyond your own factories' needs plus what you trade, averaged over about 10 days.
- `share = (presence + units traded today) / market_volume`. Impact strength runs from 5% (`min_factor`) at no share to 100% at a 25% share (`full_share`).
  Each unit moves the price by `strength / depth`. A single huge order counts toward its own share as it goes.
- So a new company barely dents prices, producing a lot makes you matter even if you never trade, and a company holding a quarter of a market moves it at full strength.
- The Market tab shows "You are x% of this market, so your trades move the price at y% strength", and the trade preview already includes it.
- Tune it in balance.json (`market_impact`) and per resource (`market_volume`, `depth`).

## Market events

Defined in `data/events.json` (settings at the top, one entry per kind of event):

- Roughly one new event every 12 days (`chance_per_day` 0.08), at most 3 announced or running at once.
- Each is **announced 3-8 days ahead**. During the announcement prices already drift part of the way (`anticipation` 0.5), so
  buying ahead pays only if you act right away (Sam's probe: about +16% if you buy at the news, about +3% two days later, a loss if you buy a huge amount).
- Then the full effect applies for the event's duration. Events on the same resource **multiply**.
- Events that crash prices (`targets_exposed`: coal glut, steel dumping, recession) get up to 4x likelier (`exposure_boost`) the bigger your share of the affected market.
- Each kind has `min_day` (late-game events come late) and a `cooldown` before it can come back.
- **Contracts and events:** no offers are made for goods an event is distorting, and existing offers for them are withdrawn at the announcement.
  Without this, a fixed-price offer made during a boom could be filled with goods bought cheaply after it ended (Sam found about +50% risk-free).
- Events use their own random stream, and are saved with the game.

## Contracts (no reputation yet)

- The board holds up to 4 offers; up to 5 contracts can be active. A tutorial offer (40 coal, 30 days) is there on day 1.
- Offers pay 105-135% of the market reference price (so a producer beats selling on the market by at least 15%, but buying goods just to deliver them only pays on the best offers). That price ignores the player's own buying and selling, so it cannot be pumped.
- Offers are only made for what the player could plausibly deliver (stock + production + what money could buy).
- Each delivery is paid straight away. After the deadline, the undelivered part costs a penalty of 40% of its value.
- Contracts use their own random stream, so they never change market prices.

## Not built yet

Reputation, events, transport costs between regions, warehouses, upgrades, demolition, bankruptcy. `GameState.advance_day()`
has the planned order of steps marked in a comment.
