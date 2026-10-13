# Gravikon - Gravitational Meeting Planner

## Repository Purpose

Gravikon is an interactive web application for planning meetings between celestial bodies in planetary systems, accounting for relativistic effects such as time dilation and signal delay due to the finite speed of light. Built as an educational tool for general relativity and astrophysics.

**Current State:** Multi-system galaxy. Multiple solar systems orbit a central supermassive black hole; meetings can be intra-system or inter-system. The legacy single-system feature (`/systems`, `SystemsController`, `data/system_data.json`, `lib/generator.rb`) was removed in July 2026 — the galaxy views are the only UI.

Council stage: legacy

## Tech Stack

**Backend:** Ruby 3.3 (rvm), Rails 8.0.2, SQLite3, Puma, Solid Cache/Queue/Cable defaults
**Frontend:** Server-rendered ERB, vanilla JavaScript (NO Turbo/Stimulus — deliberately), SVG visualizations, Propshaft
**Deployment:** plain Puma+systemd behind Caddy on the personal server "talos" (see
Production below). The stock Rails 8 Dockerfile/Kamal config exist but are unused.
**Dev tools:** Rubocop (Rails Omakase, kept at 0 offenses), Brakeman (0 warnings; 2 reviewed ignores in config/brakeman.ignore), mocha for tests

## Build & Run

```bash
bundle install
rails db:create db:migrate
rails galaxy:rebuild        # regenerate any missing galaxy/system data files from the DB
rails server                # http://localhost:3000
```

## Commands

```yaml
test_cmd: rails test              # 266 runs, 0 failures — safe: tests write only to tmp/test_gravikon/
lint_cmd: rubocop
security_scan_cmd: brakeman -q -i config/brakeman.ignore
server_cmd: rails server
rebuild_data_cmd: rails galaxy:rebuild   # self-heals galaxy_data.json, system JSONs and SVGs from DB
demo_reset_cmd: rails demo:reset         # wipe everything, seed the predefined demo galaxy
```

Other rake tasks: `cache:stats`, `cache:warm`, `cache:clear_all`, `job:benchmark`, `assets:verify_js`, `assets:verify_css`.

**Nightly demo reset:** `rails demo:reset` (lib/tasks/demo.rake) wipes all systems,
meetings and generated files, then seeds 4 predefined systems (Alfa Centauri,
Kepler-442, Trappist, Proxima — fixed names/positions, randomly generated bodies)
plus 3 intra-system and 1 inter-system meeting. Intended cron:
`0 3 * * * cd /path/to/gravikon && RAILS_ENV=production bin/rails demo:reset >> log/demo_reset.log 2>&1`

## Architecture — key decisions

**File-path authority: `GalaxyService`.** ALL generated-file locations come from
`GalaxyService.galaxy_data_path`, `.system_data_path(file_id)`, `.galaxy_svg_path`,
`.system_svg_path(file_id)`, `.systems_data_dir`, `.systems_svg_dir`.
Roots are configurable via `config.x.gravikon.data_root` / `.svg_root`
(`config/application.rb`); the **test environment points them at
`tmp/test_gravikon/<worker>/`** (per parallel worker, see `test/test_helper.rb`) so
the suite can never destroy real data. Never hardcode `Rails.root.join("data", ...)`
for generated files.

**System identity.** A `System` row has two ids: the database `id` (integer) and the
**file id** (`System#system_id`, the UUID/slug inside `json_file_path`). All file
names AND `galaxy_data.json` entries are keyed by the file id. Jobs take the DB id
(`RegenerateSystemJob`) or the file id (`GenerateSystemJob` — controller generates
the UUID before enqueueing). Mixing them up caused the historical "regeneration
writes files the app never reads" and "system collides with itself" bugs.

**Physics: `lib/physics_constants.rb`** is the single source for scaled constants
(`C = 1e7`, `UNIT_METERS = 1e6` → light crosses 1 canvas unit in 0.1 s;
`GRAVITATIONAL_CONSTANT = 1e-4` for body surface dilation;
`BLACK_HOLE_GRAVITATIONAL_CONSTANT = 1.1e-16` so BH dilation is ~0.80 at 50 units,
~0.98 at canvas edge) and the shared dilation formulas. Bodies store **local-only**
dilation; `RelativisticCalculator` combines it with black-hole dilation at the
system's *current* position — moving a system never stales its data.
`Meeting#local_avg_duration` = scheduled minutes (from HH:MM with midnight wrap)
× average participant dilation. `avg_delay` = mean pairwise signal delay in seconds.

**Self-healing:** `GalaxyService.rebuild_galaxy_data!` rebuilds `galaxy_data.json`
from the DB; `galaxy#index` and `GenerateGalaxyVisualizationJob` invoke it when the
file is missing; `rails galaxy:rebuild` regenerates everything. Destroying a System
removes its files AND its galaxy_data entry (model callbacks — no ghost entries).

**No Hotwire.** turbo-rails is not in the bundle; controllers use plain
redirects/renders, destructive actions use vanilla `onsubmit="return confirm(...)"`.
Do not add `format.turbo_stream` or `data-turbo-*` — they crash/no-op here.

**Meetings controller flow:** `build_meeting_attributes` validates + computes stats
and returns `{attrs:}` or `{error:}`; create/update share it. Update is a real
in-place `update!`. Failed submits re-render (422) with user input preserved from
params. `participant_systems` params must be converted with `.to_h`
(ActionController::Parameters is not a Hash — this bug silently blocked all
inter-system meetings historically).

**Models:**
- `System` — validations (name 3-50 chars, coords 0-800, orbit position excluding
  its own galaxy entry, path-safety on json_file_path); `system_id`,
  `data_file_path`, `load_system_data`; destroy cleans files + galaxy entry + caches.
- `Meeting` — HH:MM string times, JSON `participants` array,
  `participant_systems` JSON hash (name → system DB id, values normalized to int
  by `participant_systems_hash`), `duration_minutes`, `formatted_duration/-delay`.

**Views/JS:** `application.css` is the single CSS manifest (@imports gravikon →
galaxy → systems → meetings). Layout loads logger.js, keyboard_shortcuts.js,
galaxy.js globally; system detail pages load system_map.js (tooltips) +
orbital_animation.js (the ONLY animation engine); meeting forms load
meeting_form.js; the inter-system participant picker lives in
`meetings/_inter_system_participants.html.erb` (shared by new + edit, pairs each
checkbox to its hidden `participant_systems` field by element id). Chart.js is
vendored at `app/assets/javascripts/vendor/chart.umd.min.js`. Flash messages are
rendered by the layout (`.flash-notice` / `.flash-alert` in gravikon.css).

**Real-time orbits.** ALL orbital animation (galaxy map systems around the black
hole, bodies inside a system) is a pure function of wall-clock time:
`angle = initialAngle + 2π·(Date.now()/1000)/orbitalPeriod`. A refresh therefore
continues the motion instead of resetting, and every client shows the same
positions. There is deliberately NO speed control and NO reset — only
play/pause on the system page (resume recomputes from the clock, i.e. catches
up). Galaxy markers are `<g class="system-marker">` groups positioned via
`transform` (GalaxyVisualizer emits orbit-radius/initial-angle/orbital-period
data attributes); galaxy.js animates them. The galaxy map is the landing-page
hero; system detail pages animate `.celestial-body` circles via
orbital_animation.js. Displayed positions intentionally diverge from the stored
x/y (physics/collisions use the stored values).

**Body colors** are deterministic per name (hash-seeded HSL in
`PlanetarySystem::Body#color_for_body`): stars white-yellow, planets blue-green
spectrum, moons gray shades.

**Xentorský čas (space clock).** Top-right of the galaxy map: four teal rune
digits (Elder Futhark, base-12), one per solar system — each digit is that
system's orbital phase around the black hole quantized into 12 sectors (zero
at galactic north, clockwise). Outermost system = leftmost digit; rightmost
ticks fastest. Pure JS in galaxy.js (initSpaceClock) reading the markers'
orbit data attributes — no server state, wall-clock-derived like the orbits,
so it is identical for all visitors. Fewer than 4 systems → "–" digits.

**Landing (2026-10-13).** One headline above the map ("Čím blíž černé díře,
tím pomaleji plyne čas.") + the "Co je Gravikon?" link. Per-system clocks
under the stars were tried and REMOVED by David's call, don't bring them
back. The hover tooltip shows "Za vaši 1 hodinu uběhne zde": dilations are
computed SERVER-side (`GalaxyController#index` → `@system_dilations`, keyed by
FILE id, via `RelativisticCalculator#calculate_black_hole_dilation`), passed as
`data-system-dilations` on `.galaxy-hero`; galaxy.js `initSystemDilations`
only copies them onto the markers. Marker halos pulse ("click me") until the
first hover adds `.explored`. Headings use **Oxanium** (Orbitron had no
ů ř ě č š ž).

**Live markers vs. the position picker.** The new-system form embeds the same
galaxy SVG. galaxy.js `liveMarkers()` excludes markers inside
`#position-preview`, so in the picker systems stay at their STORED x/y (what
validation uses), don't navigate away and show no tooltips. The picker draws
its keep-out zones as an overlay SVG (`.position-zones`: 50-unit black-hole
ring, 40-unit ring per system) and `validatePosition` checks BOTH rules
client-side (the edit page's own inline map tags its other systems with
`.system-marker` + `data-x/y` for the same check).

**Units.** Visitors see km, never canvas units ("j."/"jednotek"): 1 unit =
`PhysicsConstants::UNIT_METERS` = 1 000 km. Ruby: `ApplicationHelper#format_distance_km`;
JS: `Math.round(units * 1000).toLocaleString('cs-CZ') + ' km'`. Canvas X/Y
coordinates in forms stay raw.

**System colours.** `System::COLORS` (aliased as `ApplicationHelper::SYSTEM_COLORS`)
is a 7-slot categorical palette validated for the dark surface (#1a1e3a);
`System.color_map` / `system_color(id)` assign it in System id order (8th+ →
`OTHER_COLOR`). `System.tint(hex, amount)` / `system_tint(id)` mix toward white
for the light "solar system theme". Used by the galaxy map (markers, labels,
orbit rings, tooltip dot), landing system cards (top border + name; listed by
id = colour order), system page title, dashboard (pills, profile accent,
chart) and meetings (row stripe, dots, bars): a system has ONE colour
everywhere. Direction from David (2026-10-13): the app is about the 4 demo
systems; adding/editing systems stays but is visually quiet (the "+ Přidat
soustavu" card is neutral grey, not gold).

**Map markers = miniature systems (2026-10-13).** `GalaxyVisualizer` draws each
marker as a star (light tint of the system colour) with about HALF of the
real planets circling it (`planets.size / 2`, at least 1, spread inner→outer,
starting at their real angle) on faint rings in the system colour. Planets
spin via CSS `.mini-orbit` (nested `<g>` rotate, stops under reduced motion);
the outer `<g>` transform still belongs to galaxy.js (orbit around the black
hole). Hover highlight is CSS in the SVG's own style block (the old JS stroke
on `.system-core` is gone). The visualizer takes `colors:` (file id → hex),
defaulting to `System.color_map`, so the galaxy SVG must be regenerated when
systems change (it already is).

**Binary stars (Alfa Centauri, 2026-10-13).** `SystemGenerator.new(binary: true)`
makes two stars at `BINARY_STAR_OFFSET` (36 units) on opposite sides of the
system centre; planets orbit the centre (>= 90 units out). Wired through
`GenerateSystemJob(binary:)`, `demo:reset` (`DEMO_SYSTEMS` Alfa Centauri has
`binary: true`) and `RegenerateSystemJob` (keeps `system.binary?`). No form
option on purpose (David: Alfa Centauri only). `PlanetarySystem` parents both
stars and the planets to an undrawn barycentre (empty `data-parent`, fixed
`data-parent-x/y`); orbital_animation.js treats "no parent name + radius" as
an orbit around a fixed point. Binary stars draw at most 26 px and circle in
24 s. Physics: unchanged model. A body's clock = its OWN surface gravity ×
black hole; star gravity never affected planets, so the second star is just
another body (meeting participant, dashboard inhabitant, intro "Dvojhvězda X
a Y…"). Views read `stars` (plural) everywhere: dashboard profile `stars:`,
landing card, show/edit pages.

**Meetings index.** Body class `meetings-page`; one `.meetings-board` surface
(filter bar + table), quiet column heads (overrides the global gold `th`
band), a left stripe per row in the system colour; inter-system rows get ONE
shared rainbow stripe (`--inter-rainbow`, a `::before`, same for all such rows).
Topic + participants share one column; the whole row toggles the
relativistic detail row (relativistic_viz.js; the chevron button in
`_meeting` is the keyboard equivalent); edit/delete are quiet `.icon-btn`s.
"Prožitá délka" = one hairline per participant in that participant's system
colour (track = scheduled length, bar = dilation share). Per-participant data:
`MeetingsHelper#meeting_participants_info` (memoized, shared by `_meeting`
and `_relativistic_info`). Under 760px each row stacks into a card. Row CSS
is the last block of meetings.css; the older `.meeting-topic`/`.meeting-actions`
rules there belong to an unused card layout, hence the `meeting-row-*` names.

**Dashboard (Přehled) = the star systems, not meeting stats.** A pill
switcher shows ONE system profile at a time (all panels server-rendered,
inline JS toggles them and keeps `#soustava-<id>` in the URL hash). Profile =
generated intro (`DashboardHelper#system_intro`, built from live data because
the nightly demo reset regenerates bodies), facts (distance in km, minutes per
your hour, planet/moon counts with `cs_count` Czech plurals), "Kdo tu žije"
(star, planets with their moons, nearest-planet rule like
`PlanetarySystem#assign_parents!`, bar = minutes per your hour), "Vztahy s
ostatními" (signal delay, "hodina tady = X min tam", shared meetings) and a
small list of the system's meetings (no "Všechny schůzky" link). "Kdo tu žije"
opens with a STORY about the inhabitants (`DashboardHelper#system_story`:
hand-written `SYSTEM_STORIES` for the 4 core systems, playing on their real
place in the galaxy; other systems get a stable pick from `SYSTEM_STORY_POOL`).
Moon bars are as thick as planet bars. No coloured top stripe on profile
panels or landing cards (David: no top stripes anywhere). Data: `DashboardHelper#galaxy_system_profiles`;
the controller calls `helpers.` because the data helpers use view helpers.
Below: the "Čas napříč galaxií" chart (`galaxy_time_chart_data`, colours from
`system_color`, HTML-escaped `data-chart` attribute; the "Zobrazit jako
tabulku" table was removed on request). Numbers on this page
use a Czech decimal comma. The old meeting-stat strip, recent-meetings
timeline, highlights, their helpers and the `dashboard_stats_*` cache (and
`Meeting#clear_dashboard_cache`) were removed. The cache/job performance
pages still exist at their URLs but are not linked.

**About page copy.** Section icons are default-emoji-presentation glyphs
(📖 🧮 🔧 🧭 🧩 ⌨️) so they all render as colour emoji (🛠/🜛 rendered
monochrome); nav icon is 🔭. No long dashes in the copy (colons/commas), no
"rescaled constants" note, no closing call-to-action box, no "shortcuts don't
work in form fields" note.

**Core systems (2026-10-13).** `systems.core` (boolean, default false;
migration backfills the 4 demo names, `demo:reset` creates them with
`core: true`). `GalaxyController#protect_core_system` refuses edit, update,
regenerate and delete for them (redirect + alert); the show page and landing
cards hide those controls. Meetings in them work normally. demo:reset itself
still destroys and recreates them (no model-level guard on purpose).

**Black hole dominates (2026-10-13).** `BLACK_HOLE_GRAVITATIONAL_CONSTANT` =
2.7e-16 (horizon ~44 units, dilation ~0.34 at 50, ~0.75 at 100, ~0.93 at
350) and `GRAVITATIONAL_CONSTANT` = 0.00004 (a body's own factor ~0.82-0.99),
plus demo positions Alfa Centauri ~100 and Kepler-442 ~160 from the hole.
Result: the 4 systems run ~45 / 51 / 55 / 56 min per hour and a body's own
gravity pulls it at most ~10 min below that. Stored body dilations come from
generation, so data made under the old constants needs a regenerate
(`demo:reset`).

**System page.** Planets/moons are painted with light tints of the system
colour via CSS variables on `.system-svg` (`--tone-0..2`, `--tone-moon`;
`PlanetarySystem::Body#tone` emits `data-tone`); orbit rings in the system
colour. The pause button and its note were removed (animation just runs).

**Mobile nav.** The nav bleeds to the edges with a negative margin that must
match the body padding; the ≤768px block keeps them in step (otherwise every
page scrolled sideways by 16px).

**System lookup:** galaxy map markers navigate with the FILE id (UUID) while
view links use the DB id — `GalaxyController#find_system_record` accepts both.
Keep it that way for any new system routes.

**About page:** `/o-aplikaci` (`PagesController#about`) webifies the original
assignment (Gravikon.pdf — served copy at `public/Gravikon.pdf`, source in the
repo root is git-ignored): the Xentor story, the physics formulas (CSS-rendered,
no MathJax) and the extension checklist. Linked from the nav (🔭 O aplikaci, shortcut O) and from the galaxy landing
map intro link. The keyboard-shortcut table lives on this page (the Nápověda
nav tab + modal were removed). Favicon: black-hole icon (public/icon.svg,
rasterized icon.png/favicon.ico).

**Jobs:** `GenerateSystemJob`, `RegenerateSystemJob`, `GenerateGalaxyVisualizationJob`
— fail loudly (no retry_on/discard_on swallowing), clear the *versioned* cache keys
via GalaxyService, update SVG timestamps, record metrics to
`job_performance_history` cache (dashboard /dashboard/job_performance).

## Data

`systems` table: name, x, y (galaxy coords 0-800), `json_file_path`
("data/systems/<file_id>.json" — logical identity, resolved through configured roots).
`meetings` table: start_time/end_time (HH:MM strings), topic, participants (JSON array),
participant_systems (JSON hash, inter-system only), system_id (intra-system only),
is_inter_system, local_avg_duration (minutes), avg_delay (seconds).
Note: a dead `solar_systems` table + `meetings.solar_system_id` FK still exist in the
schema (pre-multi-system remnant, no model references it).

Generated files (git-ignored): `data/galaxy_data.json`, `data/systems/<file_id>.json`,
`public/galaxy.svg`, `public/systems/<file_id>.svg`. Black hole fixed at (400,400),
min 50 units from BH, min 40 units between systems, planet orbits ≤ 370 units from
the star (planet spacing shrinks with planet count so 1-10 planets all work).

## Testing

- `rails test`: 266 runs / 0 failures / 0 errors / 9 documented skips. Parallelized;
  each worker gets isolated data roots (test_helper `parallelize_setup`).
- Helpers in test_helper: `write_system_data(system_or_id, bodies)`,
  `default_test_bodies(names)`.
- `test/system/*` are Selenium tests, NOT run by `rails test`; they also use
  GalaxyService paths now.
- NEVER write tests that touch `Rails.root/data` or `Rails.root/public` directly —
  that pattern destroyed dev data historically. Always go through GalaxyService paths.

## Security

- Strong params everywhere; participants/participant_systems size+structure limits
  (50 entries / 10KB); custom body ranges (mass 1e20-1e40, radius 1e5-1e9,
  density 500-2e4); numeric params num_planets 1-10, max_moons 0-5.
- Path traversal: every file id passes `GalaxyService.sanitize_system_id`
  (UUID or `[a-z0-9_]+` slug only) — the two weak Brakeman FileAccess findings are
  reviewed + ignored on this basis (config/brakeman.ignore).
- Rack::Attack rate limits (system creation 5/h, regeneration 10/h, meetings 20/h
  per IP); note its MemoryStore counters are per-process.
- No authentication (single-user educational tool).

## Production (talos)

- Server: `talos` = 46.224.219.9 (Hetzner, Ubuntu 24.04; also runs Quasar). SSH
  aliases `talos` (david) / `talos-root` (root) from ~/.ssh/config.
- URL: https://gravikon.duckdns.org — Caddy vhost (auto Let's Encrypt) reverse-proxies
  to Puma on localhost:3002; vhost block in `/etc/caddy/Caddyfile`.
- App: `/var/www/gravikon` (git clone of GitHub main), rbenv Ruby 3.4.5,
  `bundle config deployment true`, systemd unit `gravikon-web.service`
  (EnvironmentFile `/var/www/gravikon/.env.production`: RAILS_MASTER_KEY, PORT=3002,
  SOLID_QUEUE_IN_PUMA=true). Solid Queue runs inside Puma.
- Deploy update: push to GitHub → on server `git pull`, `bundle install`,
  `bin/rails db:prepare assets:precompile`, `systemctl restart gravikon-web`.
- Nightly demo reset: david's crontab runs `demo:reset` at 3:00 (logs to
  `log/demo_reset.log`) — production data is wiped nightly by design.

## Conventions

- `Rails.cache`: production uses Solid Cache, which does NOT support
  `delete_matched` — it raises NotImplementedError (a ScriptError, so `rescue => e`
  won't catch it) and only blows up in production. Always delete exact cache keys
  (see `GalaxyService.clear_*` / `Meeting#clear_dashboard_cache`).
- Czech for user-facing strings/flash/comments in views; English for code and commits.
- Frozen string literals; Rubocop Rails Omakase — keep `rubocop` at 0 offenses.
- Times as HH:MM strings; JSON in text columns (see Meeting model helpers).
- JavaScript in `app/assets/javascripts/` (Propshaft, no bundler); vanilla JS only.
- Generated data is never committed — rebuild with `rails galaxy:rebuild`.

## History note (July 2026 overhaul)

The codebase was originally assembled by an automated "code factory" pipeline and
accumulated: 500s on every create action (Rack::Attack subscriber bug + missing
turbo-rails), a destructive test suite that wiped real data, a broken
regeneration pipeline (DB-id/file-id mismatch, self-collision), inert physics
(sqrt DomainError rescued to 1.0, dilation factor displayed as minutes), duplicate
animation engines, and a legacy single-system feature whose regenerate button
deleted all meetings. All of the above was fixed/removed in the
2026-07 commits — see `git log` for the detailed inventory before extending old patterns.
