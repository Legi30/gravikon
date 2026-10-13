# frozen_string_literal: true

module DashboardHelper
  # One profile per star system for the dashboard (ordered by id, like the
  # system colours): the star, its "inhabitants" (planets with their moons),
  # how fast time runs for each, its relations to the other systems and the
  # meetings it takes part in. All physics goes through RelativisticCalculator.
  #
  # @return [Array<Hash>]
  def galaxy_system_profiles
    calculator = RelativisticCalculator.new
    systems = System.order(:id).to_a
    meetings = Meeting.order(:start_time).to_a
    rates = systems.to_h { |system| [ system.id, calculator.calculate_black_hole_dilation(system.x, system.y) ] }

    systems.map do |system|
      bodies = (system.load_system_data&.dig("bodies") || []).map do |body|
        {
          name: body["name"],
          type: body["type"],
          x: body["x"].to_f,
          y: body["y"].to_f,
          dilation: calculator.calculate_time_dilation(body, system.id)
        }
      end
      planets = bodies.select { |body| body[:type] == "planet" }
      moons = bodies.select { |body| body[:type] == "moon" }

      # A moon belongs to its nearest planet (same rule as PlanetarySystem#assign_parents!)
      moons_by_planet = moons.group_by do |moon|
        planets.min_by { |planet| Math.hypot(planet[:x] - moon[:x], planet[:y] - moon[:y]) }&.dig(:name)
      end

      own_meetings = meetings.select { |meeting| meeting_involves_system?(meeting, system.id) }

      relations = (systems - [ system ]).map do |other|
        distance = calculator.calculate_inter_system_distance(system.id, other.id)
        {
          system: other,
          distance: distance,
          signal_delay: calculator.calculate_signal_delay(distance),
          # Minutes that pass over there while one hour passes here
          minutes_there_per_hour_here: rates[system.id].positive? ? 60 * rates[other.id] / rates[system.id] : nil,
          shared_meetings: own_meetings.count { |meeting| meeting_involves_system?(meeting, other.id) }
        }
      end

      {
        system: system,
        distance: Math.hypot(system.x - PhysicsConstants::GALAXY_CENTER_X, system.y - PhysicsConstants::GALAXY_CENTER_Y),
        rate: rates[system.id],
        # Two stars for a binary, primary first
        stars: bodies.select { |body| body[:type] == "star" },
        planets: planets.map { |planet| planet.merge(moons: moons_by_planet[planet[:name]] || []) },
        moon_count: moons.size,
        relations: relations,
        meetings: own_meetings
      }
    end
  end

  # Generated one-paragraph introduction of a system (demo systems get fresh
  # random bodies every night, so the intro is always built from live data)
  def system_intro(profile)
    star_names = profile[:stars].map { |star| star[:name] }
    subject = if star_names.size >= 2
      "Dvojhvězda #{star_names.first(2).join(" a ")}, jejíž hvězdy krouží kolem sebe,"
    else
      "Soustava hvězdy #{star_names.first || profile[:system].name}"
    end
    parts = [
      "#{subject} leží #{format_distance_km(profile[:distance])} od černé díry, " \
      "takže tu za vaši hodinu uběhne #{format_minutes(profile[:rate] * 60)} min."
    ]

    inhabitants = profile[:planets] + profile[:planets].flat_map { |planet| planet[:moons] }
    if inhabitants.size >= 2
      slowest = inhabitants.min_by { |body| body[:dilation] }
      fastest = inhabitants.max_by { |body| body[:dilation] }
      parts << "Nejpomaleji plyne čas na tělese #{slowest[:name]} (#{format_minutes(slowest[:dilation] * 60)} min za hodinu), " \
               "nejrychleji na tělese #{fastest[:name]} (#{format_minutes(fastest[:dilation] * 60)} min)."
    end

    parts.join(" ")
  end

  # Who lives in the four core systems: hand-written, and they play on each
  # system's real place in the galaxy (Alfa Centauri is the closest to the
  # black hole, Proxima the farthest).
  SYSTEM_STORIES = {
    "Alfa Centauri" => "Pod dvěma slunci žijí Kentauřané, nejstarší národ galaxie. Obíhají nejblíž " \
                       "černé díře, takže jim čas plyne nejpomaleji ze všech: než dokončí pozdrav, " \
                       "ostatní soustavy už dávno jednají o něčem jiném. Jediný spor dodnes " \
                       "nevyřešili: které z jejich dvou sluncí je to hlavní.",
    "Kepler-442" => "Keplerijci jsou úředníci galaxie. Každou zprávu potvrzují ve třech kopiích, " \
                    "na každé planetě sídlí jiný úřad a signál, který k nim letí sotva půl minuty, " \
                    "považují za podezřele rychlý. Bez razítka se tu neuskuteční ani schůzka.",
    "Trappist" => "Trapisté složili slib mlčení. Mluvit spolu nesmějí, a tak se z nich stali " \
                  "nejlepší signalisté galaxie: každou větu pošlou světlem a trpělivě čekají, " \
                  "až doletí. Na jejich schůzkách je nejvíc slyšet ticho.",
    "Proxima" => "Proximané jsou ve vesmíru nováčci. Žijí nejdál od černé díry, takže jim čas " \
                 "utíká nejrychleji ze všech, a na každou schůzku dorazí jako první. Mezisystémovou " \
                 "komunikaci se teprve učí a pořád nechápou, proč odpověď nepřijde hned."
  }.freeze

  # Systems people add get one of these, picked by name so it never changes;
  # %{planet} is the system's first planet
  SYSTEM_STORY_POOL = [
    "Na planetě %{planet} žijí kočovní obchodníci. Do galaxie vyrážejí s nákladem " \
    "času: kde plyne pomaleji, tam ho levně nakoupí, a prodají ho tam, kde utíká.",
    "Obyvatelé planety %{planet} se o zbytku galaxie dozvěděli teprve nedávno. " \
    "Na první mezisystémový signál odpověděli s nadšením a o dvanáct verzí později " \
    "se pořád dolaďuje pozdrav.",
    "Tuhle soustavu obývají sběratelé ticha. Na planetě %{planet} mají archiv všech " \
    "zpráv, které kdy prolétly kolem, a žádnou z nich ještě nikdo nepřečetl celou.",
    "Na planetě %{planet} žijí astronomové, kteří celý život pozorují černou díru. " \
    "Tvrdí, že vidí, jak jim čas protéká mezi prsty, a vedou si o tom pečlivé tabulky.",
    "Soustavu osídlili horníci z daleka. Na planetě %{planet} těží krystaly, které " \
    "prý zpomalují čas, a na schůzky chodí vždy s prachem na botách."
  ].freeze

  # @return [String] story about who lives in the system
  def system_story(profile)
    system = profile[:system]
    story = SYSTEM_STORIES[system.name]
    return story if story

    seed = system.name.to_s.each_byte.reduce(0) { |acc, byte| (acc * 31 + byte) % 1_000_000 }
    planet = profile[:planets].first&.dig(:name) || system.name
    format(SYSTEM_STORY_POOL[seed % SYSTEM_STORY_POOL.size], planet: planet)
  end

  # Czech count with the right plural form: 1 planeta, 2–4 planety, 5+ planet
  def cs_count(count, one, few, many)
    word = if count == 1 then one
    elsif (2..4).cover?(count) then few
    else many
    end
    "#{count} #{word}"
  end

  # Minutes with one decimal and a Czech decimal comma
  def format_minutes(minutes)
    number_with_precision(minutes, precision: 1, separator: ",")
  end

  # Data for the "time across the galaxy" chart: every body's total time
  # dilation (own gravity × black hole, via RelativisticCalculator) against
  # its system's distance from the black hole, plus the black-hole-only
  # dilation curve for reference. Systems are ordered by id and carry their
  # shared system colour (ApplicationHelper#system_color).
  #
  # @return [Hash] { systems: [{ name:, color:, other:, distance:, bodies: [{ name:, type:, dilation: }] }], curve: [{ x:, y: }] }
  def galaxy_time_chart_data
    calculator = RelativisticCalculator.new
    center_x = PhysicsConstants::GALAXY_CENTER_X
    center_y = PhysicsConstants::GALAXY_CENTER_Y

    systems = System.order(:id).map do |system|
      bodies = system.load_system_data&.dig("bodies") || []
      {
        name: system.name,
        color: system_color(system.id),
        other: system_color(system.id) == ApplicationHelper::SYSTEM_OTHER_COLOR,
        distance: Math.hypot(system.x - center_x, system.y - center_y).round(1),
        bodies: bodies.map do |body|
          { name: body["name"], type: body["type"], dilation: calculator.calculate_time_dilation(body, system.id).round(5) }
        end
      }
    end

    # Systems stay >= 50 units from the black hole; the curve runs to the
    # first round 50 past the farthest system (canvas corner is ~566 units out)
    farthest = systems.map { |s| s[:distance] }.max || 400
    max_distance = [ ((farthest + 30) / 50.0).ceil * 50, 600 ].min
    curve = (50..max_distance).step(5).map do |r|
      { x: r, y: calculator.calculate_black_hole_dilation(center_x + r, center_y).round(5) }
    end

    { systems: systems, curve: curve }
  end

  # Numbers the landing story quotes, from the same profiles as the panel:
  # the slowest and the fastest system, and the pair whose signal flies longest
  #
  # @return [Hash, nil] nil with fewer than two systems
  def galaxy_story_facts(profiles)
    return nil if profiles.size < 2

    from, relation = profiles.flat_map { |profile| profile[:relations].map { |rel| [ profile, rel ] } }
                             .max_by { |_, rel| rel[:signal_delay] }
    {
      slowest: profiles.min_by { |profile| profile[:rate] },
      fastest: profiles.max_by { |profile| profile[:rate] },
      far_from: from[:system],
      far_to: relation[:system],
      far_delay: relation[:signal_delay]
    }
  end

  # The black hole's own panel on the landing page: its mass and horizon, how
  # slowly time runs at the closest distance a system may have, and every
  # system around it, nearest first (same physics as the system profiles)
  #
  # @return [Hash]
  def black_hole_profile(galaxy_data, profiles)
    black_hole = galaxy_data["black_hole"] || {}
    mass = (black_hole["mass"] || PhysicsConstants::BLACK_HOLE_MASS).to_f
    limit = GalaxyService::MIN_DISTANCE_FROM_BLACK_HOLE
    calculator = RelativisticCalculator.new(galaxy_data: galaxy_data)

    {
      name: black_hole["name"] || "Černá díra",
      mass: mass,
      horizon: PhysicsConstants.schwarzschild_radius(mass) / PhysicsConstants::UNIT_METERS,
      limit: limit,
      limit_rate: calculator.calculate_black_hole_dilation(PhysicsConstants::GALAXY_CENTER_X + limit, PhysicsConstants::GALAXY_CENTER_Y),
      systems: profiles.sort_by { |profile| profile[:distance] }
    }
  end

  # Mass as "6,69 × 10<sup>27</sup> kg" (generated masses span 1e20-1e40)
  def format_mass(kg)
    return "–" unless kg.to_f.positive?

    exponent = Math.log10(kg.to_f).floor
    mantissa = number_with_precision(kg.to_f / 10**exponent, precision: 2, separator: ",")
    safe_join([ "#{mantissa} × 10", content_tag(:sup, exponent), " kg" ])
  end

  # Body radius (stored in metres) in km with a space as thousands separator
  def format_radius_km(meters)
    return "–" unless meters.to_f.positive?

    "#{number_with_delimiter((meters.to_f / 1000).round, delimiter: " ")} km"
  end

  # Signal delay for display, Czech decimal comma (matches format_minutes)
  def format_delay_display(seconds)
    return "0 s" if seconds.nil? || seconds.zero?

    if seconds >= 60
      "#{number_with_precision(seconds / 60.0, precision: 2, separator: ",")} min"
    else
      "#{number_with_precision(seconds, precision: 2, separator: ",")} s"
    end
  end

  private

  def meeting_involves_system?(meeting, system_id)
    if meeting.is_inter_system
      meeting.participant_systems_hash.values.include?(system_id)
    else
      meeting.system_id == system_id
    end
  end
end
