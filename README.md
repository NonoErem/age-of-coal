# Iron and Coal (working title) - Godot skeleton

Godot 4.3+. Open this folder in the Godot project manager and press F5 for the debug screen.

## Run the tests (no editor needed)

    godot --headless --path . -s tests/market_test.gd     # market and exploit checks
    godot --headless --path . -s tests/sim_test.gd        # map, mines, factories, upkeep, saving
    godot --headless --path . -s tests/contracts_test.gd  # contract board, delivery, penalties, fairness
    godot --headless --path . -s tests/save_test.gd       # save files: slots, damaged and old saves, continuing a loaded game
    godot --headless --path . -s tests/events_test.gd     # market events: timeline, stacking, exposure, offers, saving
    godot --headless --path . -s tests/settings_test.gd   # display settings file, fitting the window to the screen
    godot --headless --path . -s tests/map_view_test.gd   # map layout, zoom, panning, overview map, mouse
    godot --headless --path . -s tests/orders_test.gd     # standing orders: selling, buying, limits, lost days, saving
    godot --headless --path . -s tests/storage_test.gd    # storage, stopping and demolishing buildings
    godot --headless --path . -s tests/art_test.gd        # every building, resource and deposit has well-formed art
    godot --headless --path . -s tests/economy_test.gd    # every building must pay for itself (reads the data files)
    godot --headless --path . -s tests/companies_test.gd  # rival companies: market effects, bankruptcy, buying, offers, flips, saving
    godot --headless --path . -s tests/survey_test.gd     # surveys: areas, depth levels, hidden deposits, costs, saving
    godot --headless --path . -s tests/rules_test.gd      # automation rules: keep/sell, limits, caps, conflicts, churn guard, saving
    godot --headless --path . -s tests/ui_smoke_test.gd   # drives the real screen like a player
    godot --headless --path . -s tests/sam_contract_probe.gd  # informational: buy-to-deliver profit per resource
    godot --headless --path . -s tests/sam_event_probe.gd     # informational: profit from speculating on an announced event
    godot --headless --path . -s tests/sam_offer_probe.gd     # informational: how the contract board behaves over 600 days
    godot --headless --path . -s tests/rival_probe.gd         # informational: 6 seeds x 1500 days, how often rivals weaken or fail on their own
    godot --headless --path . -s tests/rival_tuning.gd        # tuning tool: compares rival settings (natural busts, does one failure spread?)

Exit code 0 means every check passed.

## Layout

- `data/`   balance.json, resources.json, buildings.json, map.json, contracts.json, events.json, companies.json. Tune numbers here, no code changes. Money is in integer cents.
- `sim/`    pure game logic (data loader, market, market events, rival companies, production, contracts, game state). It never touches UI or scenes.
- `game/`   main screen (coordinator), the tile map view and the save manager.
- `ui/`     Iris's interface: style, top bar, build bar, inspector, event log, Market / Production / Contracts / Orders / Rivals / News panels, price chart.
- `art/`    the pictures, as SVG: buildings/, deposits/, resources/ (see Art below).
- `tools/`  screenshot tool and scenarios, the art contact sheet, a window-size check (these need a display, e.g. xvfb), and make_art.py (the art generator).
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
- Stock is one shared pool with limited room (see Storage and buildings below).

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
- **Contracts tab:** offers (with how much they pay over market, what you already hold and how long they stay open, soonest-ending first) and active contracts with progress and days left.
- **Orders tab:** start a standing order (sell or buy the same amount every day for a number of days, with an optional price limit) and see the ones running, with progress and a note when a day was lost.
- **Menu (Esc or the Menu button):** three save slots and an autosave (every 10 days), each showing day, cash, buildings and when it was saved.
  Saving over a used slot, loading while you have progress, and starting a new game all ask first. Damaged or old saves are listed with the reason and never crash the game.
  The game is paused while the menu is open. Saves live in `user://saves` (Godot's user data folder for this project).
- **Rivals tab:** the eight rival companies with status, strength bar, what they make and use, cash and last day's result, what their trouble does to prices, and a Buy / Sell button (two clicks, to avoid accidents). Owned companies come first, then those in trouble. The tab title counts rivals in trouble that you do not own. The Market tab adds a line when rival trouble moves the selected price.
- **News tab:** events announced, running and recently over, with their effect on prices, how long they last and what you hold of the goods involved.
  In the Market tab an amber "!" marks resources an event is moving; hover a row or look under the chart for details.
- **Log:** every build, trade, pause, delivery, failure and warnings before a deadline.

To regenerate the screenshots: `xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/screenshot.gd -- out.png res://tools/shot_scenarios.gd play`
(scenarios: build, build_bad, play, production, contracts, bottleneck).

## Display and the map

- **Window size and text size** are in the game menu (Esc), under Display: 1280 x 720, 1600 x 900, 1920 x 1080 or Fullscreen, and text at 100%, 125% or 150%.
  They apply at once and are remembered in `user://settings.json` (Godot's user data folder for this project). A damaged or unknown setting falls back to 1280 x 720 at 100%.
- The game draws in **real pixels**: a bigger window gives a bigger map and more room, not just a bigger picture. Text size is separate, for readability.
  On a big window the panels on the right get a little wider too.
- A window too big for the screen is **shrunk to fit** (leaving room for the title bar and taskbar), keeping its shape and never below 1000 x 640.
  For example 1920 x 1080 on a 1080p monitor opens at about 1834 x 1032. Fullscreen always fits.
- **The map** is 40 x 24 tiles with 26 deposits (it was 24 x 14 with 10; the original deposits did not move). Old saves load on it, and the new deposits start full.
  It is defined in `data/map.json` (`width`, `height`, `start_view`, `deposits`): to make it bigger or add deposits, edit that file.
  Mines can only go on deposits, so more deposits means more places to build.
- **Moving around the map:**
  - Mouse wheel zooms (the tile under the mouse stays put). Or use the + and - buttons in the corner, or the + and - keys. Fit (or the 0 key) goes back to the automatic zoom.
  - Drag with the right or middle mouse button to move. A plain right click still cancels building. The arrow keys move the map too.
  - When the whole map does not fit, a small **overview map** appears in the corner. It shows deposits, buildings and your view; click or drag on it to jump.
  - "Show" buttons in the Production tab scroll the map to the building.
  - Tiles never get smaller than a comfortable size on their own: in a small window you pan, in a big one the whole map fits.
- `tools/check_window.gd` applies each window size to a real window and prints the result (use it with xvfb to test big and small screens).
- The screenshot tool takes `--keep-window` (do not resize the window) and `--ui-scale=1.25`.

## Storage and buildings

- **Room:** the open yard holds 250 units (`base_storage`). Each warehouse adds 500 (`capacity` in buildings.json), costs +10% for every one you already own,
  and goes on free ground. Everything counts the same: one unit of coal takes as much room as one unit of machinery.
- **When it is full:** a mine or factory that cannot put its output anywhere stops with the status "storage full" (nothing is dug, the deposit is not used up,
  nothing piles up in secret) and restarts by itself when there is room. You cannot buy more than the free room. A recipe that makes more units than it uses
  also needs room for the difference. The top bar turns amber at 90% and red when full, and the log warns once.
- **Stopping a building (Stop / Restart button in the inspector, or P):** a stopped mine or factory makes and uses nothing, keeps its stock,
  and pays only a quarter of its upkeep (`idle_upkeep_factor`, same as a paused or blocked one). Warehouses cannot be stopped.
- **Demolishing (button in the inspector, asks first):** pulls the building down and refunds 30% of what you paid, land included (`demolish_refund`).
  Building and demolishing in a loop only loses money. A warehouse cannot be demolished while your stock would no longer fit without it.
  A mine that has run dry can be demolished, so it stops costing upkeep. The deposit stays on the map with what is left in it.
- Contract offers never ask for more than you could store and buy.

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

## Standing orders

A macro you can start at any time, in the Orders tab (not a contract: nobody offers it, you ask for it):

- Pick sell or buy, a resource, an amount per day, and a number of days (up to 120; at most 6 orders at once; up to 500 units a day).
- Optionally set a price limit: a sell only happens if the average price is at least the limit, a buy only if it is at most the limit.
- Every day, after production, it trades at the market price with the usual spread, fee and price impact. It counts towards your presence in the market like any other trade.
- A sell trades what you have, up to the amount. A buy trades what fits in storage and what you can pay for, and never puts you into debt.
- A day when nothing can be traded is lost, and the order still ends on schedule. The log tells you once when that starts, once when it recovers, and when the order finishes with the totals.
- Orders are saved with the game and can be cancelled at any time. Settings: `standing` in contracts.json.

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

- An offer stays on the board for a time that depends on how well it pays: the better the premium, the sooner someone else takes it.
  About 2 days at +35%, 3 days at +30%, 7 days at +22%, about 2 weeks at +5% (`offer_lifetime` in contracts.json: min_days, max_days, curve).
  The log says how long a new offer will last, and the offer card shows how many days are left. The tutorial offer stays open 60 days.
- The board holds up to 4 offers; up to 5 contracts can be active. A tutorial offer (40 coal, 30 days) is there on day 1.
- Offers pay 105-135% of the market reference price (so a producer beats selling on the market by at least 15%, but buying goods just to deliver them only pays on the best offers). That price ignores the player's own buying and selling, so it cannot be pumped.
- Offers are only made for what the player could plausibly deliver (stock + production + what money could buy).
- Each delivery is paid straight away. After the deadline, the undelivered part costs a penalty of 40% of its value.
- Contracts use their own random stream, so they never change market prices.

## Rival companies (companies.json, sim/companies.gd, the Rivals tab)

Eight specialists that are not on the map: Blackwater Colliery (coal), Cornish Ore & Stone (iron ore, limestone, copper ore),
Tees Coke & Gas (coke), Harlow Ironworks (pig iron), Tyne Steel (steel), Albion Copper Works (copper ingots),
Northern Rail & Engineering (rails, machinery) and Midland Tool & Die (tools). Each has outputs, inputs, an overhead, cash and a strength from 0 to 1.

- **Healthy is normal.** A healthy rival is already part of the market. What changes prices is *deviation*:
  - a weakened or bankrupt rival supplies less, so its products get dearer, and buys fewer inputs, so the basic goods it uses get cheaper
    (`price_sensitivity`, capped by `mult_min`/`mult_max`; the shift moves smoothly and also moves the price contracts are based on);
  - every healthy specialist makes its products' market deeper (`depth_bonus`: +30% for coal up to +50% for machinery), which thins out again when it fails.
    That is why a big order moves a market less while the rivals are well.
- **Their day.** At today's prices (spread and fee softened by `friction`) a rival earns outputs minus inputs, scaled by its strength, minus overhead.
  It idles when that margin is negative or an input costs more than `max_input_mult` times its base price, and then pays only `idle_overhead` of its overhead.
  Cash below zero shrinks its strength each day; with cash above the comfort level and a profit it grows back; past the debt limit it goes bankrupt.
  A bankrupt rival makes nothing for `revival_days`, then investors restart it weakened (`revival_strength`).
- **You can cause it.** Rivals trade at the real prices, including your own market pressure: keep a product cheap or its inputs dear for weeks and its maker fails.
  Dumping costs you money too, and with a small company the effect is slight (see "How much you move the market").
- **Why chains do not collapse.** Rivals feel only `rival_feel` (30%) of the price shift caused by other rivals' trouble. At 100% one failure toppled its customers and
  suppliers in turn and the sector stayed in depression for hundreds of days (Sam's finding, see `tests/rival_tuning.gd`).
- **Contracts.** A rival takes offers only for goods it makes. The better an offer pays the likelier (0.5%/day at +5% up to 15%/day at +35%, times its strength),
  never on the offer's first day, never when it is bankrupt, never when you own it. Switch off with `take_contracts: false`.
  Rivals use their own random stream, so the market and the contract board are not disturbed.
- **Buying one** (up to `max_owned` = 3): price = base value x (15% + 85% x strength), so a bankrupt one is a bargain and buying it restarts it. You get half of its daily profit
  as dividends and it stops taking your offers; it still trades as before, so buying it does not change the market. If it goes bankrupt while you own it, the stake is lost.
  Selling is possible after 30 days and returns 35% of the purchase price at that moment, so a quick flip is impossible and holding a healthy company is a slow loss
  unless the dividends pay for it. Sam's check: nursing a bankrupt Tyne Steel for about 40 days nets roughly a third of its full value, bought at 15%.
- `"enabled": false` in companies.json removes the rivals completely (prices and depth go back to the base values).
- **Growth.** Each company has a size (`scale`, 1.0 at the start, shown as "size x1.4" on its card). A healthy company that makes a profit and has comfortable cash
  reinvests `growth_reinvest` (30%) of what it keeps after dividends: `scale += spend / base_value x (1 - scale / growth_max_scale)`, so growth slows as it nears the
  cap (3.0). Size multiplies its margin, overhead, cash buffers, its pull on market depth and supply, its chance to take offers, and its **price**:
  a very successful company becomes steadily dearer instead of being worth its maximum from day one. In debt it shrinks 1% a day, and a bankruptcy restarts it at
  size 1.0 or less. A company you own grows too, but slower, because you take half its profit. Typical result after 300 days: average size x1.6 to x2.1 and about
  three busts per 1000 days across all eight, with no cascade. Sam's check: a healthy Blackwater held 300 days returns about 88% of its price (payback around 240 days),
  so buying a leader is a slow bet, not a free ride. Tunables: `growth_reinvest`, `growth_max_scale`, `min_scale`, `scale_decay`, `restart_scale`, `take_scale_cap`.
- Saves: version 9 (older saves are refused, as before). Tests that count exact money turn rivals' offer-taking off.

## Surveys (map.json "survey", sim/survey.gd, Survey buttons in the build bar)

The 26 deposits of earlier versions are still visible from day one. Another 14 are hidden under the ground (9 at depth 1, 5 at depth 2, every ore). Deeper ones are bigger,
richer and dearer to buy. Pick **Shallow survey** ($1,200) or **Deep survey** ($3,500) in the build bar and click the map: it surveys a 7 x 7 area around the tile.

- A level 1 survey reveals depth-1 deposits in the area; a level 2 survey reveals depth 1 and depth 2. You pay whatever is found, so a poor guess costs money.
- Surveyed ground is tinted (lighter for shallow, darker for deep). A survey that would add nothing new at that level (every tile already surveyed that deep) is refused and free.
- Surveys are deterministic: the hidden deposits are fixed in map.json, there is no luck, only the question of where to look. Deep deposits wear a small D1 / D2 tag.
- A revealed deposit is used like any other (land price, mine, richness). Until then the tile looks like empty ground, so a factory may stand on it; the deposit shows once surveyed,
  and a mine there means demolishing the factory first. Loading a game keeps what was revealed, and a deposit under one of your mines is always shown.
- Tunables in map.json: `survey.radius`, `survey.levels.N.cost` and `name`; each hidden deposit carries `"depth": 1|2`.

## Automation rules (sim/rules.gd, the Rules view of the Orders tab)

Standing orders are a fixed amount for a number of days. Rules react to what you hold and run until deleted:

- **Keep at least N**: each day, buy what is missing to reach N.
- **Sell what is over N**: each day, sell the stock above N (N = 0 sells everything as it arrives).
- Options: a price limit (a keep rule pays at most, a sell rule accepts at least), a per-day cap (default and maximum 500), and for keep rules a cash floor.
  Pause and resume without losing the rule's history.
- Rules trade through the normal market (spread, fee, price impact), so they save clicks, not money. They never take you into debt and never overfill storage.
- When one cannot do its job (price outside the limit, no cash, no room) the log says so once, and again when it works normally again.
- **Churn guard (Sam):** a keep level above the sell level for the same good would buy and sell the same units every day and lose the spread each time, so it is refused
  (paused rules do not count; resuming one is checked). One rule of each kind per good, at most 12 rules.
- Order of the day: production, upkeep, standing orders, rules, rivals, market. Tunables in balance.json "rules": `max_rules`, `max_level`, `max_per_day`.

## Not built yet

Reputation, transport costs between regions, building upgrades. `GameState.advance_day()`
has the planned order of steps marked in a comment.
