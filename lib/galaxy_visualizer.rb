# frozen_string_literal: true

require 'json'
require 'nokogiri'
require 'fileutils'

# Galaxy visualizer for generating SVG representation of the galaxy
# Shows central black hole and all solar systems orbiting around it
class GalaxyVisualizer
  attr_reader :black_hole, :systems, :background, :system_details

  # Initialize visualizer with galaxy data
  # @param galaxy_json_path [String] Path to galaxy_data.json
  def initialize(galaxy_json_path = nil)
    galaxy_json_path ||= default_galaxy_path

    unless File.exist?(galaxy_json_path)
      raise "Galaxy data file not found: #{galaxy_json_path}"
    end

    data = JSON.parse(File.read(galaxy_json_path))
    @black_hole = data['black_hole']
    @systems = data['systems'] || []
    @system_details = {}

    load_system_details
    generate_background
  end

  # Load details for each system (body count, total mass, etc.)
  def load_system_details
    @systems.each do |system|
      system_id = system['id']
      system_file = system_data_path(system_id)

      # Skip if system_id was invalid (sanitization returned nil)
      next unless system_file

      if File.exist?(system_file)
        begin
          system_data = JSON.parse(File.read(system_file))
          bodies = system_data['bodies'] || []

          @system_details[system_id] = {
            name: system_data['system_name'] || "System #{system_id}",
            body_count: bodies.length,
            total_mass: bodies.sum { |b| b['mass'] || 0 },
            has_star: bodies.any? { |b| b['type'] == 'star' }
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

    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |svg|
      svg.svg(xmlns: 'http://www.w3.org/2000/svg', viewBox: '0 0 800 800', width: '800', height: '800') do
        # Background
        svg.rect(x: 0, y: 0, width: 800, height: 800, fill: '#000814')

        # Add definitions for gradients
        svg.defs do
          # Black hole gradient
          svg.radialGradient(id: 'blackHoleGradient') do
            svg.stop(offset: '0%', 'stop-color': '#000000', 'stop-opacity': '1')
            svg.stop(offset: '50%', 'stop-color': '#1a0033', 'stop-opacity': '1')
            svg.stop(offset: '80%', 'stop-color': '#330066', 'stop-opacity': '1')
            svg.stop(offset: '100%', 'stop-color': '#8b5cf6', 'stop-opacity': '0.8')
          end

          # Accretion disk gradient
          svg.radialGradient(id: 'accretionDiskGradient') do
            svg.stop(offset: '0%', 'stop-color': '#ff6600', 'stop-opacity': '0.0')
            svg.stop(offset: '40%', 'stop-color': '#ff3300', 'stop-opacity': '0.3')
            svg.stop(offset: '70%', 'stop-color': '#cc0000', 'stop-opacity': '0.5')
            svg.stop(offset: '100%', 'stop-color': '#660000', 'stop-opacity': '0.2')
          end

          # System glow effect
          svg.radialGradient(id: 'systemGlow') do
            svg.stop(offset: '0%', 'stop-color': '#fbbf24', 'stop-opacity': '1')
            svg.stop(offset: '50%', 'stop-color': '#f59e0b', 'stop-opacity': '0.6')
            svg.stop(offset: '100%', 'stop-color': '#d97706', 'stop-opacity': '0')
          end
        end

        # Background stars
        svg.g(id: 'background-stars') do
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
        svg.g(id: 'orbital-paths') do
          @systems.each do |system|
            orbit_radius = calculate_orbit_radius(system)
            next if orbit_radius < 1

            svg.circle(
              cx: @black_hole['x'],
              cy: @black_hole['y'],
              r: orbit_radius.round(2),
              fill: 'none',
              stroke: '#334155',
              'stroke-width': '1',
              'stroke-dasharray': '4,3',
              opacity: '0.4',
              class: 'orbit-path',
              'data-system-id': system['id']
            )
          end
        end

        # Black hole visualization
        svg.g(id: 'black-hole') do
          bh_x = @black_hole['x']
          bh_y = @black_hole['y']

          # Accretion disk (outer glow)
          svg.circle(
            cx: bh_x,
            cy: bh_y,
            r: 50,
            fill: 'url(#accretionDiskGradient)',
            opacity: '0.6',
            class: 'accretion-disk'
          )

          # Event horizon ring
          svg.circle(
            cx: bh_x,
            cy: bh_y,
            r: 35,
            fill: 'none',
            stroke: '#a855f7',
            'stroke-width': '1.5',
            opacity: '0.5',
            class: 'event-horizon-ring'
          )

          # Black hole core
          svg.circle(
            cx: bh_x,
            cy: bh_y,
            r: 30,
            fill: 'url(#blackHoleGradient)',
            stroke: '#8b5cf6',
            'stroke-width': '2',
            class: 'black-hole-core',
            'data-name': @black_hole['name'],
            'data-mass': @black_hole['mass'],
            'data-type': 'black_hole'
          )

          # Black hole label
          svg.text_(
            @black_hole['name'],
            x: bh_x,
            y: bh_y - 55,
            'text-anchor': 'middle',
            fill: '#a855f7',
            'font-size': '14',
            'font-weight': 'bold',
            class: 'black-hole-label'
          )
        end

        # Solar systems
        svg.g(id: 'solar-systems') do
          @systems.each do |system|
            system_id = system['id']
            details = @system_details[system_id] || {}

            x = system['x'].to_f
            y = system['y'].to_f

            # Calculate system size based on body count (larger systems = more bodies)
            body_count = details[:body_count] || 0
            base_radius = 12
            radius = [base_radius + (body_count * 0.8), 25].min # Cap at 25

            # System glow (outer halo)
            svg.circle(
              cx: x,
              cy: y,
              r: radius + 8,
              fill: 'url(#systemGlow)',
              opacity: '0.3',
              class: 'system-glow'
            )

            # System circle
            system_color = details[:has_star] ? '#fbbf24' : '#94a3b8'
            svg.circle(
              cx: x,
              cy: y,
              r: radius,
              fill: system_color,
              stroke: '#f59e0b',
              'stroke-width': '2',
              class: 'system-marker',
              'data-system-id': system_id,
              'data-system-name': details[:name],
              'data-x': x.round(2),
              'data-y': y.round(2),
              'data-body-count': body_count,
              'data-total-mass': details[:total_mass],
              style: 'cursor: pointer;'
            )

            # System label
            label_y = y - radius - 10
            svg.text_(
              details[:name],
              x: x,
              y: label_y,
              'text-anchor': 'middle',
              fill: '#fbbf24',
              'font-size': '11',
              'font-weight': '500',
              class: 'system-label',
              'data-system-id': system_id
            )

            # Body count indicator (small text below system name)
            if body_count > 0
              svg.text_(
                "#{body_count} #{body_count == 1 ? 'body' : 'bodies'}",
                x: x,
                y: label_y + 12,
                'text-anchor': 'middle',
                fill: '#94a3b8',
                'font-size': '9',
                class: 'body-count-label'
              )
            end
          end
        end

        # Add CSS for hover effects
        svg.style do
          svg.text <<~CSS
            .system-marker:hover {
              stroke: #facc15;
              stroke-width: 3;
              filter: brightness(1.2);
            }
            .system-marker.selected {
              stroke: #22c55e;
              stroke-width: 3;
              filter: brightness(1.3);
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

  # Calculate orbital radius for a system around the black hole
  # @param system [Hash] System data with x, y coordinates
  # @return [Float] Distance from black hole center
  def calculate_orbit_radius(system)
    x = system['x'].to_f
    y = system['y'].to_f
    bh_x = @black_hole['x'].to_f
    bh_y = @black_hole['y'].to_f

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
