# Gravikon - Gravitational Meeting Planner

## Repository Purpose

Gravikon is an interactive web application for planning meetings between celestial bodies in planetary systems, accounting for relativistic effects such as time dilation and signal delay due to the finite speed of light. Built as an educational tool for general relativity and astrophysics.

**Current State:** Multi-system galaxy support with interactive visualization. Multiple solar systems orbit a central supermassive black hole, enabling both intra-system and inter-system meetings with enhanced relativistic calculations.

## Tech Stack

**Backend:**
- Ruby 3.4.5
- Rails 8.0.2
- SQLite3 (development/test), multi-database production setup
- Puma web server
- Solid Cache, Solid Queue, Solid Cable (Rails 8 defaults)

**Frontend:**
- Server-rendered ERB templates
- Vanilla JavaScript (no framework)
- SVG-based interactive visualizations
- Propshaft asset pipeline

**Asset Processing:**
- Terser (JS minification)
- CSSO (CSS minification)

**Deployment:**
- Docker & Kamal support
- Thruster for production serving

**Development Tools:**
- Rubocop (Rails Omakase style)
- Brakeman (security scanner)
- Debug gem

## Build & Run

**Initial Setup:**
```bash
# Install dependencies
gem install bundler
bundle install

# Setup database
rails db:create db:migrate

# Run data migration (if upgrading from single-system)
rake data:migrate_to_multi_system

# Generate galaxy visualization
rails runner "GalaxyVisualizer.generate"
```

**Development:**
```bash
rails server
# Visit http://localhost:3000
```

**Production (Docker):**
```bash
docker build -t gravikon .
docker run -d -p 80:80 -e RAILS_MASTER_KEY=<key> --name gravikon gravikon
```

**Kamal Deployment:**
```bash
kamal setup
kamal deploy
```

## Commands

```yaml
test_cmd: rails test
lint_cmd: rubocop
security_scan_cmd: brakeman -q
db_setup_cmd: rails db:create db:migrate
server_cmd: rails server
generate_system_cmd: ruby lib/generator.rb <num_planets> <max_moons>
visualize_cmd: ruby lib/visualizer.rb
precompile_assets_cmd: rails assets:precompile
```

**Custom Rake Tasks:**
- `rails assets:verify_js` - Verify JavaScript syntax
- `rails assets:verify_css` - Verify CSS syntax
- `rails data:migrate_to_multi_system` - Migrate single-system data to multi-system structure
- `rails data:rollback_multi_system` - Rollback multi-system migration
- `rails data:cleanup_legacy_files` - Clean up legacy single-system files
- `rails cache:stats` - View cache statistics
- `rails cache:warm` - Warm up production caches
- `rails cache:clear_all` - Clear all caches
- `rails job:benchmark` - Benchmark background jobs

## Security

**Current Measures:**
- Strong parameter whitelisting in controllers (GalaxyController, MeetingsController)
- JSON validation for participant data and participant_systems
- Input validation:
  - System names: 3-50 alphanumeric characters, spaces, hyphens
  - Numeric parameters: num_planets (1-10), max_moons (0-5)
  - Custom bodies: mass (1e20-1e40), radius (1e5-1e9), density (500-20000)
  - Coordinates: galaxy (0-800), minimum distances enforced
- File path sanitization: prevents path traversal attacks, validates UUID/slug formats
- Rate limiting via Rack::Attack:
  - System creation: 5/hour per IP
  - System regeneration: 10/hour per IP
  - Meeting creation: 20/hour per IP
- Orbit validation: ensures systems don't collide or exit canvas
- Non-root Docker user (uid 1000)
- Content Security Policy configured
- Filter parameter logging enabled
- Brakeman static analysis
- Security event logging with IP and User-Agent tracking

**Security Constraints:**
- No authentication system (single-user educational tool)
- SQLite not recommended for multi-user production
- Credentials encrypted via Rails credentials

## Performance

**Caching Strategy:**
- Galaxy data cached with versioned keys: `galaxy_data_v2`
- Individual system data cached: `system_data_<id>_v2`
- Used celestial names cached: `used_celestial_names` (30 min expiry)
- Meeting statistics per system: `system_<id>_meeting_stats_v2` (30 min expiry)
- Dashboard statistics cached with version keys
- SVG timestamps for cache busting: `galaxy_svg_timestamp`, `system_<id>_svg_timestamp`
- Cache warming on production startup for first 10 systems
- Solid Cache for production (SQLite-backed)

**Background Jobs:**
- `GenerateSystemJob` - Async system generation to prevent timeouts
- `RegenerateSystemJob` - Async system regeneration
- `GenerateGalaxyVisualizationJob` - Async galaxy SVG generation
- Solid Queue for job processing

**Optimizations:**
- Bootsnap for faster boot times
- Propshaft for static asset serving
- Test parallelization enabled
- Asset minification in production
- Lazy-load system details on click
- Separate caching for galaxy metadata and individual systems
- Efficient relativistic calculations for inter-system distances

## Data

**Database Schema:**

`systems` table:
- `id` (integer, primary key)
- `name` (string) - System name, 3-50 characters
- `x`, `y` (float) - Galaxy coordinates (0-800)
- `json_file_path` (string) - Path to system data JSON file
- `created_at`, `updated_at` (datetime)
- Validations: name format, uniqueness, coordinates range, orbit position

`meetings` table:
- `id` (integer, primary key)
- `start_time`, `end_time` (string, HH:MM format)
- `topic` (string)
- `participants` (text, JSON array) - Body names
- `participant_systems` (text, JSON hash) - Maps participant names to system IDs (for inter-system meetings)
- `system_id` (integer, foreign key) - Single system for intra-system meetings
- `is_inter_system` (boolean) - Flag for inter-system meetings
- `local_avg_duration`, `avg_delay` (float) - Calculated relativistic effects
- `created_at`, `updated_at` (datetime)

**File-Based Data:**

`data/galaxy_data.json` - Galaxy configuration:
```json
{
  "black_hole": {
    "name": "Sagittarius Omega",
    "mass": 8.2e36,
    "x": 400,
    "y": 400,
    "schwarzschild_radius": <calculated>,
    "dilation": 0.0,
    "type": "black_hole"
  },
  "systems": [
    { "id": "<system_id>", "x": <float>, "y": <float> }
  ]
}
```

`data/systems/<system_id>.json` - Individual system data:
```json
{
  "bodies": [
    {
      "name": "Stelaris",
      "type": "star",
      "x": 400,
      "y": 400,
      "radius": <meters>,
      "density": <kg/m³>,
      "mass": <kg>,
      "dilation": <float>
    },
    { "...": "planets and moons..." }
  ]
}
```

`public/galaxy.svg` - Galaxy map visualization
`public/systems/<system_id>.svg` - Individual system visualizations

**Data Generation:**
- `lib/system_generator.rb` - Creates random solar systems with physics calculations
- `lib/generator.rb` - Legacy generator (backwards compatibility)
- `lib/galaxy_visualizer.rb` - Generates galaxy map SVG
- `lib/visualizer.rb` - Generates system SVG (supports both legacy and multi-system)
- Validates: planet count (1-10), moon count (0-5 per planet), custom body parameters
- Calculates: mass from radius/density, gravitational time dilation
- Ensures unique celestial names across all systems in galaxy

## Testing Strategy

**Test Suite:**
- Minitest (Rails default)
- Parallel test execution enabled
- Fixtures for test data

**Test Coverage:**
- Model tests:
  - Meeting validations, time parsing, JSON handling, system associations
  - System validations (name, coordinates, orbit position, file path security)
- Controller tests:
  - MeetingsController (intra-system and inter-system meetings)
  - GalaxyController (CRUD operations, validations, security)
  - DashboardController
- Service tests:
  - GalaxyService (caching, system loading, position validation)
  - RelativisticCalculator (inter-system coordinate transformation)
- Validator tests:
  - OrbitValidator (system and body position validation)
- Job tests:
  - GenerateSystemJob, RegenerateSystemJob, GenerateGalaxyVisualizationJob
- Helper tests: Dashboard statistics, meeting statistics per system

**Test Execution:**
```bash
rails test                    # All tests
rails test:models             # Model tests only
rails test:controllers        # Controller tests only
rails test test/models/meeting_test.rb  # Single file
```

**Multi-System Test Coverage:**
- ✅ Galaxy map rendering with multiple systems
- ✅ Inter-system meeting calculations with coordinate transformation
- ✅ System CRUD operations (create, edit, delete, regenerate)
- ✅ Orbital validation (systems don't overlap or exit canvas)
- ✅ Name uniqueness across galaxy (cached validation)
- ✅ System switching UI and navigation
- ✅ Migration from single-system to multi-system structure
- ✅ Cache invalidation and warming
- ✅ Security validations (rate limiting, input validation, path traversal prevention)

## Conventions

**Code Style:**
- Rubocop Rails Omakase configuration
- Frozen string literals (`# frozen_string_literal: true`)
- Czech language for user-facing strings and comments
- English for code, variable names, and git commits

**Naming Conventions:**
- Celestial body names from predefined lists (planet_names, moon_names, star_names in generator.rb)
- Controllers: PascalCase files (e.g., SystemsController.rb), not snake_case
- Models: snake_case files following Rails conventions
- JavaScript: camelCase for functions/variables

**Database Conventions:**
- Time stored as HH:MM strings (not datetime)
- Participants stored as JSON arrays
- Callbacks: `before_validation`, `after_commit` for cache clearing

**File Organization:**
- Data generators in `lib/`
- Custom rake tasks in `lib/tasks/`
- JavaScript in `app/assets/javascripts/` (not app/javascript)
- System data in `data/` directory

**Git Workflow:**
- Feature branches with descriptive names
- Czech commit messages acceptable for user-facing changes
- Migrations should be reversible

**Multi-System Conventions:**
- Galaxy data in `data/galaxy_data.json`
- Individual system data in `data/systems/<system_id>.json`
- Consistent coordinate system: (400, 400) = galaxy center
- System IDs: UUIDs or slugified names (validated, no path traversal)
- SVG viewBox: 800x800 for both galaxy and system views
- Galaxy coordinates: (0, 0) top-left, (800, 800) bottom-right
- Minimum distances: 50 units from black hole, 40 units between systems
- Black hole position: fixed at (400, 400)

## Architecture

**Models:**
- `System` - Database persistence for solar systems
  - Associations: `has_many :meetings`
  - Validations: name format, uniqueness, coordinates, orbit position, file path security
  - Methods: `load_system_data`, `data_file_exists?`, `slug`

- `Meeting` - Scheduled meetings between celestial bodies
  - Associations: `belongs_to :system` (optional for inter-system meetings)
  - Types: Intra-system (single system) or Inter-system (multiple systems)
  - JSON fields: `participants`, `participant_systems`

**Controllers:**
- `GalaxyController` - Galaxy map and system management
  - Actions: index, show_system, new, create, edit_system, update_system, destroy_system, regenerate_system
  - Security: Strong parameters, numeric validation, custom body validation, orbit validation
  - Logging: System creation, deletion, failed validations

- `MeetingsController` - Meeting scheduling (both types)
  - Actions: index, new, new_inter_system, create, edit, update, destroy
  - Handles coordinate transformation for inter-system meetings
  - JSON validation for participants and participant_systems

**Services:**
- `GalaxyService` - Galaxy-level operations with caching
  - Methods: `load_galaxy_data`, `load_system_data`, `add_system`, `remove_system`
  - Validation: `validate_system_position`, `sanitize_system_id`
  - Cache management: galaxy, systems, used names, meeting stats, SVG timestamps
  - Security: Path sanitization, collision detection

- `RelativisticCalculator` - Physics calculations
  - Coordinate transformation (local → galaxy)
  - Time dilation calculations
  - Signal delay calculations

**Validators:**
- `OrbitValidator` - Validates orbital positions
  - System-level: canvas bounds, distance from black hole, collision detection
  - Body-level: canvas bounds, collision detection within system

**Generators:**
- `SystemGenerator` - Creates solar systems with realistic physics
  - Random planet/moon generation with configurable parameters
  - Custom body support with validation
  - Unique name generation (checks against all systems)
  - Mass and time dilation calculations

**Visualizers:**
- `GalaxyVisualizer` - Generates galaxy map SVG
  - Renders black hole, orbital paths, system markers
  - Interactive markers with data attributes

- `PlanetarySystem` (visualizer.rb) - Generates system SVG
  - Supports both legacy and multi-system modes
  - Renders star, planets, moons with orbits

**Background Jobs:**
- `GenerateSystemJob` - Async system generation
- `RegenerateSystemJob` - Async system regeneration
- `GenerateGalaxyVisualizationJob` - Async galaxy SVG generation

**Initializers:**
- `cache_warming.rb` - Warms caches on production startup
- `rack_attack.rb` - Rate limiting configuration
