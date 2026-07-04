# Gravikon - Gravitational Meeting Planner

## Repository Purpose

Gravikon is an interactive web application for planning meetings between celestial bodies in planetary systems, accounting for relativistic effects such as time dilation and signal delay due to the finite speed of light. Built as an educational tool for general relativity and astrophysics.

**Current State:** Multi-system galaxy. Multiple solar systems orbit a central supermassive black hole; meetings can be intra-system or inter-system. The legacy single-system feature (`/systems`, `SystemsController`, `data/system_data.json`, `lib/generator.rb`) was removed in July 2026 — the galaxy views are the only UI.

Council stage: legacy

## Tech Stack

**Backend:** Ruby 3.3 (rvm), Rails 8.0.2, SQLite3, Puma, Solid Cache/Queue/Cable defaults
**Frontend:** Server-rendered ERB, vanilla JavaScript (NO Turbo/Stimulus — deliberately), SVG visualizations, Propshaft
**Deployment:** Docker & Kamal, Thruster
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
test_cmd: rails test              # 281 runs, 0 failures — safe: tests write only to tmp/test_gravikon/
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

**System lookup:** galaxy map markers navigate with the FILE id (UUID) while
view links use the DB id — `GalaxyController#find_system_record` accepts both.
Keep it that way for any new system routes.

**About page:** `/o-aplikaci` (`PagesController#about`) webifies the original
assignment (Gravikon.pdf — served copy at `public/Gravikon.pdf`, source in the
repo root is git-ignored): the Xentor story, the physics formulas (CSS-rendered,
no MathJax) and the extension checklist. Linked from the nav (🚀 O aplikaci, shortcut O) and from the galaxy landing
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

- `rails test`: 281 runs / 0 failures / 0 errors / 9 documented skips. Parallelized;
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

## Conventions

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
