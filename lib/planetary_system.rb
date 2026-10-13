# frozen_string_literal: true

require "json"
require "nokogiri"
require "fileutils"

# === Planetární systém ===
# Renders a single solar system's SVG visualization from its JSON data file.
class PlanetarySystem
  SYSTEM_CENTER = 400

  # === Třída tělesa ===
  class Body
    attr_reader :name, :x, :y, :radius, :color, :type, :dilation
    attr_accessor :parent

    def initialize(data)
      @name = data["name"]
      @x = data["x"]
      @y = data["y"]
      @radius = data["radius"]
      @type = data["type"]
      @dilation = data["dilation"]
      @color = color_for_body
      @parent = nil
    end

    def orbit_radius
      return nil unless parent
      Math.sqrt((x - parent.x)**2 + (y - parent.y)**2)
    end

    # Deterministic per-body color (seeded by name, stable across renders):
    # stars white-yellow, planets blue-green spectrum, moons shades of gray.
    # Shared with GalaxyVisualizer so a system's marker on the galaxy map
    # matches the color of its actual star.
    def self.color_for(name, type)
      seed = name.to_s.each_byte.reduce(0) { |acc, b| (acc * 31 + b) % 1_000_000 }

      case type
      when "star"   then "hsl(#{38 + seed % 22}, #{80 + seed % 20}%, #{58 + seed % 32}%)"
      when "planet" then "hsl(#{150 + seed % 75}, #{55 + seed % 25}%, #{48 + seed % 16}%)"
      when "moon"   then "hsl(0, 0%, #{52 + seed % 28}%)"
      else "#ffffff"
      end
    end

    def color_for_body
      self.class.color_for(@name, @type)
    end

    # 0-2, stable per name: which light tint of the system colour the system
    # page paints this body in (show_system sets the tints as CSS variables)
    def tone
      name.to_s.each_byte.reduce(0) { |acc, b| (acc * 31 + b) % 1_000_000 } % 3
    end
  end

  attr_reader :bodies, :background, :raw_bodies, :system_id, :system_name, :system_x, :system_y

  # Initialize planetary system
  # @param json_path [String] Path to system JSON file
  # @param system_id [String, nil] Optional system ID for multi-system support
  def initialize(json_path, system_id: nil)
    data = JSON.parse(File.read(json_path))
    @raw_bodies = data["bodies"]

    # Extract system metadata if available
    @system_id = system_id || data["system_id"] || File.basename(json_path.to_s, ".json")
    @system_name = data["system_name"] || "System #{@system_id}"
    @system_x = data["system_x"]
    @system_y = data["system_y"]

    @bodies = @raw_bodies.map { |b| Body.new(b) }
    assign_parents!
    generate_background
  end

  # Binary star: the two stars circle their common centre (the system's
  # local origin) slowly, so they don't spin like a propeller
  BINARY_STAR_DISPLAY_RADIUS = 26
  BINARY_STAR_PERIOD = 24

  def binary?
    bodies.count { |b| b.type == "star" } >= 2
  end

  def assign_parents!
    stars = bodies.select { |b| b.type == "star" }
    planets = bodies.select { |b| b.type == "planet" }
    moons = bodies.select { |b| b.type == "moon" }

    # Planets orbit the star, or a binary's common centre (an unnamed,
    # undrawn point that the stars themselves circle too)
    center = if stars.size >= 2
      barycentre = Body.new("x" => SYSTEM_CENTER, "y" => SYSTEM_CENTER, "radius" => 0, "type" => "barycentre")
      stars.each { |star| star.parent = barycentre }
      barycentre
    else
      stars.first
    end
    planets.each { |p| p.parent = center }

    moons.each do |m|
      # Přiřaď nejbližší planetu jako rodiče
      parent = bodies.select { |b| b.type == "planet" }
                     .min_by { |p| Math.sqrt((p.x - m.x)**2 + (p.y - m.y)**2) }
      m.parent = parent
    end
  end

  def generate_background
    @background = Array.new(100) do
      {
        cx: rand(800),
        cy: rand(800),
        r: rand < 0.97 ? 0.5 : 1.5,
        color: rand < 0.97 ? "#ffffaa" : "#ffaa00"
      }
    end
  end

  # Generate SVG visualization of the system
  # @param output [String, nil] Output path for SVG file
  # @return [String] Path to generated SVG file
  def to_svg(output = nil)
    output ||= GalaxyService.system_svg_path(system_id)
    raise ArgumentError, "No output path for system #{system_id}" unless output

    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(output))

    scale_factor = 180.0 / bodies.map(&:radius).max
    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |svg|
      svg.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 800 800", width: "800", height: "800",
              "data-system-id": system_id,
              "data-system-name": system_name) do
        # Add system metadata as hidden metadata element
        svg.metadata do
          svg.system do
            svg.id_ system_id
            svg.name_ system_name
            if system_x && system_y
              svg.galaxyPosition do
                svg.x_ system_x.round(2)
                svg.y_ system_y.round(2)
              end
            end
          end
        end

        svg.rect(x: 0, y: 0, width: 800, height: 800, fill: "#001022")

        # Pozadí
        background.each do |obj|
          svg.circle(cx: obj[:cx], cy: obj[:cy], r: obj[:r], fill: obj[:color])
        end

        # Orbitální dráhy (a binary's two stars share one ring)
        bodies.each do |body|
          next unless body.parent
          next if body.type == "star" && body != bodies.find { |b| b.type == "star" }
          r = body.orbit_radius
          svg.circle(cx: body.parent.x, cy: body.parent.y, r: r.round(1),
                     fill: "none", stroke: "#555", "stroke-dasharray": "3,2",
                     class: "orbit-path",
                     "data-body-name": body.name,
                     "data-parent-name": body.parent.name)
        end

        # Tělesa
        bodies.each do |body|
          scaled_radius = (body.radius * scale_factor).clamp(1, 50)
          scaled_radius = [ scaled_radius, BINARY_STAR_DISPLAY_RADIUS ].min if body.type == "star" && binary?

          # Získat mass pro data atribut
          raw_body = raw_bodies.find { |b| b["name"] == body.name }
          mass = raw_body ? raw_body["mass"] : 0

          # Vypočítat orbitální parametry pro animaci
          orbit_radius = body.orbit_radius
          parent_name = body.parent ? body.parent.name.to_s : ""
          parent_x = body.parent ? body.parent.x : 0
          parent_y = body.parent ? body.parent.y : 0

          # Počáteční úhel na orbitě (v radiánech)
          if body.parent
            initial_angle = Math.atan2(body.y - parent_y, body.x - parent_x)
          else
            initial_angle = 0
          end

          # Orbitální perioda (úměrná poloměru orbity - zjednodušený Keplerův zákon)
          # Menší hodnota = rychlejší otáčení
          if body.type == "star" && orbit_radius && orbit_radius > 0
            orbital_period = BINARY_STAR_PERIOD
          elsif orbit_radius && orbit_radius > 0
            # Perioda v sekundách pro jeden oběh (čím dále, tím pomaleji)
            orbital_period = (orbit_radius / 50.0) ** 1.5 * 10
          else
            orbital_period = 0
          end

          svg.circle(
            cx: body.x,
            cy: body.y,
            r: scaled_radius.round(1),
            fill: body.color,
            "data-name": body.name,
            "data-type": body.type,
            "data-radius": body.radius,
            "data-mass": mass,
            "data-dilation": body.dilation,
            "data-parent": parent_name,
            "data-parent-x": parent_x.round(2),
            "data-parent-y": parent_y.round(2),
            "data-orbit-radius": orbit_radius ? orbit_radius.round(2) : 0,
            "data-initial-angle": initial_angle.round(4),
            "data-orbital-period": orbital_period.round(2),
            "data-tone": body.tone,
            class: "celestial-body"
          )
          svg.text_("#{body.name}", x: body.x + scaled_radius + 5, y: body.y - scaled_radius - 5,
                     "font-size": "10", fill: "white")
        end
      end
    end

    File.write(output, builder.to_xml)
    Rails.logger.info("PlanetarySystem: SVG rendered to #{output}") if defined?(Rails)
    output.to_s
  end

  # Class method for convenience - generate SVG from system file
  # @param json_path [String] Path to system JSON file
  # @param system_id [String, nil] Optional system ID
  # @param output_path [String, nil] Optional output path
  # @return [String] Path to generated SVG
  def self.generate(json_path:, system_id: nil, output_path: nil)
    system = new(json_path, system_id: system_id)
    system.to_svg(output_path)
  end
end
