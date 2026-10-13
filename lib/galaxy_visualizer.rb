# frozen_string_literal: true

require "json"
require "nokogiri"
require "fileutils"

# Galaxy visualizer for generating SVG representation of the galaxy
# Shows central black hole and all solar systems orbiting around it
class GalaxyVisualizer
  attr_reader :black_hole, :systems, :background, :system_details

  # Map markers are miniature systems: a star (or binary pair) with about
  # half of the real planets circling it, at least one
  MARKER_FIRST_ORBIT = 15
  MARKER_ORBIT_STEP = 5
  MARKER_BINARY_OFFSET = 6

  # Initialize visualizer with galaxy data
  # @param galaxy_json_path [String] Path to galaxy_data.json
  # @param colors [Hash{String => String}, nil] system file id => "#rrggbb"
  #   (defaults to System.color_map, the same colours as dashboard/meetings)
  def initialize(galaxy_json_path = nil, colors: nil)
    galaxy_json_path ||= default_galaxy_path

    unless File.exist?(galaxy_json_path)
      raise "Galaxy data file not found: #{galaxy_json_path}"
    end

    data = JSON.parse(File.read(galaxy_json_path))
    @black_hole = data["black_hole"]
    @systems = data["systems"] || []
    @system_details = {}
    @colors = colors || default_colors

    load_system_details
    generate_background
  end

  # Load details for each system (body count, total mass, etc.)
  def load_system_details
    @systems.each do |system|
      system_id = system["id"]
      system_file = system_data_path(system_id)

      # Skip if system_id was invalid (sanitization returned nil)
      next unless system_file

      if File.exist?(system_file)
        begin
          system_data = JSON.parse(File.read(system_file))
          bodies = system_data["bodies"] || []

          star = bodies.find { |b| b["type"] == "star" }
          @system_details[system_id] = {
            name: system_data["system_name"] || "System #{system_id}",
            body_count: bodies.length,
            total_mass: bodies.sum { |b| b["mass"] || 0 },
            has_star: !star.nil?,
            star_name: star&.dig("name"),
            star_count: bodies.count { |b| b["type"] == "star" },
            # Planets from the innermost out, with their angle around the centre
            planets: bodies.select { |b| b["type"] == "planet" }.map { |planet|
              dx = planet["x"].to_f - PhysicsConstants::SYSTEM_LOCAL_CENTER
              dy = planet["y"].to_f - PhysicsConstants::SYSTEM_LOCAL_CENTER
              { distance: Math.hypot(dx, dy), angle: Math.atan2(dy, dx), radius: planet["radius"].to_f }
            }.sort_by { |planet| planet[:distance] }
          }
        rescue => e
          log_warn("Failed to load system #{system_id}: #{e.message}")
          @system_details[system_id] = {
            name: "System #{system_id}",
            body_count: 0,
            total_mass: 0,
            has_star: false
          }
        end
      else
        @system_details[system_id] = {
          name: "System #{system_id}",
          body_count: 0,
          total_mass: 0,
          has_star: false
        }
      end
    end
  end

  # Generate background stars for visual appeal
  def generate_background
    @background = Array.new(150) do
      {
        cx: rand(800),
        cy: rand(800),
        r: rand < 0.95 ? 0.5 : 1.0,
        color: rand < 0.95 ? "#ffffff" : "#aaccff",
        opacity: rand(0.3..0.8)
      }
    end
  end

  # Generate SVG visualization of the galaxy
  # @param output_path [String] Output path for SVG file
  # @return [String] Path to generated SVG
  def to_svg(output_path = nil)
    output_path ||= default_output_path

    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(output_path))

    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |svg|
      svg.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 800 800", width: "800", height: "800") do
        # Background
        svg.rect(x: 0, y: 0, width: 800, height: 800, fill: "#000814")

        # Add definitions for gradients
        svg.defs do
          # Black hole gradient
          svg.radialGradient(id: "blackHoleGradient") do
            svg.stop(offset: "0%", 'stop-color': "#000000", 'stop-opacity': "1")
            svg.stop(offset: "50%", 'stop-color': "#1a0033", 'stop-opacity': "1")
            svg.stop(offset: "80%", 'stop-color': "#330066", 'stop-opacity': "1")
            svg.stop(offset: "100%", 'stop-color': "#8b5cf6", 'stop-opacity': "0.8")
          end

          # Accretion disk gradient
          svg.radialGradient(id: "accretionDiskGradient") do
            svg.stop(offset: "0%", 'stop-color': "#ff6600", 'stop-opacity': "0.0")
            svg.stop(offset: "40%", 'stop-color': "#ff3300", 'stop-opacity': "0.3")
            svg.stop(offset: "70%", 'stop-color': "#cc0000", 'stop-opacity': "0.5")
            svg.stop(offset: "100%", 'stop-color': "#660000", 'stop-opacity': "0.2")
          end

          # System glow, one per system in its own colour
          @systems.each_with_index do |system, index|
            color = system_color(system["id"])
            svg.radialGradient(id: "systemGlow-#{index}") do
              svg.stop(offset: "0%", 'stop-color': System.tint(color, 0.6), 'stop-opacity': "1")
              svg.stop(offset: "50%", 'stop-color': color, 'stop-opacity': "0.5")
              svg.stop(offset: "100%", 'stop-color': color, 'stop-opacity': "0")
            end
          end
        end

        # Background stars
        svg.g(id: "background-stars") do
          @background.each do |star|
            svg.circle(
              cx: star[:cx],
              cy: star[:cy],
              r: star[:r],
              fill: star[:color],
              opacity: star[:opacity]
            )
          end
        end

        # Orbital paths (dashed circles for each system)
        svg.g(id: "orbital-paths") do
          @systems.each do |system|
            orbit_radius = calculate_orbit_radius(system)
            next if orbit_radius < 1

            svg.circle(
              cx: @black_hole["x"],
              cy: @black_hole["y"],
              r: orbit_radius.round(2),
              fill: "none",
              stroke: system_color(system["id"]),
              'stroke-width': "1",
              'stroke-dasharray': "4,3",
              opacity: "0.35",
              class: "orbit-path",
              'data-system-id': system["id"]
            )
          end
        end

        # Black hole visualization
        svg.g(id: "black-hole") do
          bh_x = @black_hole["x"]
          bh_y = @black_hole["y"]

          # Accretion disk (outer glow)
          svg.circle(
            cx: bh_x,
            cy: bh_y,
            r: 50,
            fill: "url(#accretionDiskGradient)",
            opacity: "0.6",
            class: "accretion-disk"
          )

          # Event horizon ring
          svg.circle(
            cx: bh_x,
            cy: bh_y,
            r: 35,
            fill: "none",
            stroke: "#a855f7",
            'stroke-width': "1.5",
            opacity: "0.5",
            class: "event-horizon-ring"
          )

          # Black hole core
          svg.circle(
            cx: bh_x,
            cy: bh_y,
            r: 30,
            fill: "url(#blackHoleGradient)",
            stroke: "#8b5cf6",
            'stroke-width': "2",
            class: "black-hole-core",
            'data-name': @black_hole["name"],
            'data-mass': @black_hole["mass"],
            'data-type': "black_hole"
          )

          # Black hole label
          svg.text_(
            @black_hole["name"],
            x: bh_x,
            y: bh_y - 55,
            'text-anchor': "middle",
            fill: "#a855f7",
            'font-size': "14",
            'font-weight': "bold",
            class: "black-hole-label"
          )
        end

        # Solar systems: each system is one <g> group (glow + miniature
        # system + label) positioned via transform, so the real-time orbit
        # animation in galaxy.js can move the whole system by updating a
        # single attribute. Inside, the star(s) and planets are drawn in light
        # tints of the system colour and circle the marker centre (CSS).
        svg.g(id: "solar-systems") do
          @systems.each_with_index do |system, index|
            system_id = system["id"]
            details = @system_details[system_id] || {}
            color = system_color(system_id)

            x = system["x"].to_f
            y = system["y"].to_f
            orbit_radius = calculate_orbit_radius(system)
            initial_angle = Math.atan2(y - @black_hole["y"].to_f, x - @black_hole["x"].to_f)
            # Kepler-like: farther systems orbit slower (seconds per revolution)
            orbital_period = orbit_radius > 1 ? ((orbit_radius / 50.0)**1.5 * 60).round(1) : 0

            body_count = details[:body_count] || 0
            planets = marker_planets(details[:planets] || [])
            binary = details[:star_count].to_i >= 2
            outer_radius = planets.any? ? MARKER_FIRST_ORBIT + (planets.size - 1) * MARKER_ORBIT_STEP : 9

            svg.g(
              class: "system-marker",
              transform: "translate(#{x.round(2)}, #{y.round(2)})",
              'data-system-id': system_id,
              'data-system-name': details[:name],
              'data-system-color': color,
              'data-binary': binary,
              'data-x': x.round(2),
              'data-y': y.round(2),
              'data-body-count': body_count,
              'data-total-mass': details[:total_mass],
              'data-orbit-radius': orbit_radius.round(2),
              'data-initial-angle': initial_angle.round(4),
              'data-orbital-period': orbital_period,
              style: "cursor: pointer;"
            ) do
              # Invisible hit area covering marker + label so hover is one
              # contiguous generous disc (no flicker in the gaps)
              svg.circle(cx: 0, cy: 0, r: outer_radius + 16, fill: "transparent", class: "system-hit-area")

              # System glow (outer halo)
              svg.circle(cx: 0, cy: 0, r: outer_radius + 6, fill: "url(#systemGlow-#{index})", opacity: "0.3", class: "system-glow")

              # Planet orbit rings
              planets.each_with_index do |_planet, i|
                svg.circle(
                  cx: 0, cy: 0, r: MARKER_FIRST_ORBIT + i * MARKER_ORBIT_STEP,
                  fill: "none", stroke: color, 'stroke-width': "0.7", 'stroke-opacity': "0.45",
                  class: "mini-ring"
                )
              end

              # Star, or a binary pair circling the centre
              star_fill = System.tint(color, 0.75)
              if binary
                svg.g(class: "mini-orbit mini-binary", style: "animation-duration: 8s;") do
                  svg.circle(cx: MARKER_BINARY_OFFSET, cy: 0, r: 4.8, fill: star_fill, class: "system-core",
                             'data-ring': MARKER_BINARY_OFFSET, 'data-angle': 0, 'data-period': 8)
                  svg.circle(cx: -MARKER_BINARY_OFFSET, cy: 0, r: 4, fill: System.tint(color, 0.6), class: "system-star",
                             'data-ring': MARKER_BINARY_OFFSET, 'data-angle': Math::PI.round(4), 'data-period': 8)
                end
              else
                svg.circle(cx: 0, cy: 0, r: 7, fill: star_fill, class: "system-core")
              end

              # Planets: start at their real angle, inner ones circle faster
              planets.each_with_index do |planet, i|
                ring = MARKER_FIRST_ORBIT + i * MARKER_ORBIT_STEP
                period = (14 * (ring / MARKER_FIRST_ORBIT)**1.5).round(1)
                # data-ring/-angle/-period let the landing map drive the
                # planet itself (tilted plane) instead of the CSS spin
                svg.g(class: "mini-spin", transform: "rotate(#{(planet[:angle] * 180 / Math::PI).round(1)})") do
                  svg.g(class: "mini-orbit", style: "animation-duration: #{period}s;") do
                    svg.circle(
                      cx: ring.round(2), cy: 0, r: planet_marker_radius(planet),
                      fill: System.tint(color, i.even? ? 0.35 : 0.5), class: "mini-planet",
                      'data-ring': ring.round(2), 'data-angle': planet[:angle].round(4), 'data-period': period
                    )
                  end
                end
              end

              # System label
              svg.text_(
                details[:name],
                x: 0,
                y: -outer_radius - 9,
                'text-anchor': "middle",
                fill: System.tint(color, 0.45),
                'font-size': "11",
                'font-weight': "600",
                class: "system-label"
              )
            end
          end
        end

        # Add CSS for hover effects
        svg.style do
          svg.text <<~CSS
            .mini-orbit {
              animation: mini-orbit linear infinite;
            }
            @keyframes mini-orbit {
              to { transform: rotate(360deg); }
            }
            @media (prefers-reduced-motion: reduce) {
              .mini-orbit { animation: none; }
            }
            .mini-ring {
              transition: stroke-opacity 0.2s ease;
            }
            .system-core, .system-star {
              filter: drop-shadow(0 0 3px rgba(255, 255, 255, 0.55));
            }
            .system-marker:hover .mini-ring {
              stroke-opacity: 0.9;
            }
            .system-marker:hover .mini-planet {
              filter: brightness(1.25);
            }
            .system-marker:hover .system-glow {
              opacity: 0.6;
            }
            .black-hole-core {
              filter: drop-shadow(0 0 10px #8b5cf6);
            }
          CSS
        end
      end
    end

    File.write(output_path, builder.to_xml)
    log_info("Galaxy SVG generated: #{output_path}")
    output_path
  end

  # Class method for convenience
  # @param galaxy_json_path [String] Path to galaxy data
  # @param output_path [String] Output path for SVG
  # @return [String] Path to generated SVG
  def self.generate(galaxy_json_path: nil, output_path: nil)
    visualizer = new(galaxy_json_path)
    visualizer.to_svg(output_path)
  end

  private

  # About half of the real planets (rounded down, at least one), spread
  # evenly from the innermost to the outermost
  # @param planets [Array<Hash>] planets sorted by distance from the star
  # @return [Array<Hash>]
  def marker_planets(planets)
    return [] if planets.empty?

    shown = [ planets.size / 2, 1 ].max
    Array.new(shown) { |i| planets[i * planets.size / shown] }
  end

  # Marker dot size from the planet's real radius (1 000-4 000 km generated)
  def planet_marker_radius(planet)
    (1.8 + (planet[:radius] / 4_000_000.0).clamp(0, 1) * 1.4).round(2)
  end

  # Colour of a system on the map (same palette as dashboard and meetings)
  def system_color(system_id)
    @colors[system_id] || System::OTHER_COLOR
  end

  # system file id => colour, via the System records (colour order = id order)
  def default_colors
    color_map = System.color_map
    System.all.to_h { |system| [ system.system_id, color_map[system.id] ] }
  end

  # Calculate orbital radius for a system around the black hole
  # @param system [Hash] System data with x, y coordinates
  # @return [Float] Distance from black hole center
  def calculate_orbit_radius(system)
    x = system["x"].to_f
    y = system["y"].to_f
    bh_x = @black_hole["x"].to_f
    bh_y = @black_hole["y"].to_f

    Math.sqrt((x - bh_x)**2 + (y - bh_y)**2)
  end

  # Get default path to galaxy data
  # @return [String] Path to galaxy_data.json
  def default_galaxy_path
    GalaxyService.galaxy_data_path.to_s
  end

  # Get path to system data file (sanitized by GalaxyService)
  # @param system_id [String] System ID
  # @return [String, nil] Path to system JSON file or nil if invalid
  def system_data_path(system_id)
    GalaxyService.system_data_path(system_id)&.to_s
  end

  # Get default output path
  # @return [String] Default path for output SVG
  def default_output_path
    GalaxyService.galaxy_svg_path.to_s
  end

  # Log info message
  # @param message [String] Message to log
  def log_info(message)
    Rails.logger.info(message)
  end

  # Log warning message
  # @param message [String] Message to log
  def log_warn(message)
    Rails.logger.warn(message)
  end
end
