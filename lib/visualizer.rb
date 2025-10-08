require 'json'
require 'nokogiri'

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
    @color = color_for_type
    @parent = nil
  end

  def orbit_radius
    return nil unless parent
    Math.sqrt((x - parent.x)**2 + (y - parent.y)**2)
  end

  def color_for_type
    case type
    when "star" then "#ffff66"
    when "planet" then "#66ccff"
    when "moon" then "#cccccc"
    else "#ffffff"
    end
  end
end

# === Planetární systém ===
class PlanetarySystem
  attr_reader :bodies, :background

  def initialize(json_path)
    data = JSON.parse(File.read(json_path))
    raw_bodies = data["bodies"]

    @bodies = raw_bodies.map { |b| Body.new(b) }
    assign_parents!
    generate_background
  end

  def assign_parents!
    star = bodies.find { |b| b.type == "star" }
    planets = bodies.select { |b| b.type == "planet" }
    moons = bodies.select { |b| b.type == "moon" }

    planets.each { |p| p.parent = star }

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

  def to_svg(schedule_json_path = nil, output = "public/system.svg")
    scale_factor = 180.0 / bodies.map(&:radius).max
    builder = Nokogiri::XML::Builder.new do |svg|
      svg.svg(xmlns: "http://www.w3.org/2000/svg", width: "800", height: "800") do
        svg.rect(x: 0, y: 0, width: 800, height: 800, fill: "#001022")

        # Pozadí
        background.each do |obj|
          svg.circle(cx: obj[:cx], cy: obj[:cy], r: obj[:r], fill: obj[:color])
        end

        # Orbitální dráhy
        bodies.each do |body|
          next unless body.parent
          r = body.orbit_radius
          svg.circle(cx: body.parent.x, cy: body.parent.y, r: r.round(1),
                     fill: "none", stroke: "#555", "stroke-dasharray": "3,2")
        end

        # Tělesa
        bodies.each do |body|
          scaled_radius = (body.radius * scale_factor).clamp(1, 50)
          svg.circle(cx: body.x, cy: body.y, r: scaled_radius.round(1), fill: body.color)
          svg.text_("#{body.name}", x: body.x + scaled_radius + 5, y: body.y - scaled_radius - 5,
                     "font-size": "10", fill: "white")

        end
      end
    end

    File.write(output, builder.to_xml)
    puts "Vykresleno do #{"public/system.svg"}"
  end
end

# === Spuštění ===
system = PlanetarySystem.new("data/system_data.json")
system.to_svg("schedule.json")

