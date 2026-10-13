require "test_helper"

# The landing page: tilted galaxy map, slide-in system profiles (formerly
# the Přehled page) and the story with the galaxy time chart
class GalaxyLandingTest < ActionDispatch::IntegrationTest
  setup do
    Meeting.delete_all
    System.delete_all
    Rails.cache.clear

    # Two real systems in the isolated test data root; Luna sits next to
    # Earth so it belongs to Earth (nearest-planet rule)
    @system = System.create!(name: "Sol System", x: 200, y: 200, json_file_path: "data/systems/sol_dash.json")
    write_system_data(@system, [
      { "name" => "Sol", "type" => "star", "x" => 400, "y" => 400, "radius" => 6.96e8, "mass" => 1.989e30, "dilation" => 1.0 },
      { "name" => "Earth", "type" => "planet", "x" => 500, "y" => 400, "radius" => 6.371e6, "mass" => 5.972e24, "dilation" => 0.9 },
      { "name" => "Mars", "type" => "planet", "x" => 600, "y" => 400, "radius" => 3.389e6, "mass" => 6.39e23, "dilation" => 0.95 },
      { "name" => "Luna", "type" => "moon", "x" => 510, "y" => 400, "radius" => 1.737e6, "mass" => 7.3e22, "dilation" => 0.99 }
    ])

    @other = System.create!(name: "Vega System", x: 700, y: 400, json_file_path: "data/systems/vega_dash.json")
    write_system_data(@other, default_test_bodies(%w[Vega Rigel]))
  end

  test "should get index" do
    get root_url
    assert_response :success
  end

  test "the old Přehled page redirects to the landing page" do
    get dashboard_url
    assert_redirected_to root_path
  end

  test "builds one profile per system with planets and their moons" do
    get root_url

    profiles = assigns(:profiles)
    assert_equal [ "Sol System", "Vega System" ], profiles.map { |profile| profile[:system].name }

    sol = profiles.first
    assert_equal [ "Sol" ], sol[:stars].map { |star| star[:name] }
    assert_equal %w[Earth Mars], sol[:planets].map { |planet| planet[:name] }
    assert_equal [ "Luna" ], sol[:planets].first[:moons].map { |moon| moon[:name] }
    assert_equal 1, sol[:moon_count]
    # Total dilation = own gravity × black hole, so every body runs slower than its local factor
    assert sol[:planets].first[:dilation] < 0.9
  end

  test "a binary system lists both stars and introduces itself as a binary" do
    write_system_data(@other, [
      { "name" => "Vega", "type" => "star", "x" => 364, "y" => 400, "radius" => 6.0e7, "mass" => 1.9e27, "dilation" => 1.0 },
      { "name" => "Rigel", "type" => "star", "x" => 436, "y" => 400, "radius" => 5.0e7, "mass" => 1.5e27, "dilation" => 1.0 },
      { "name" => "Pluven", "type" => "planet", "x" => 520, "y" => 400, "radius" => 2.5e6, "mass" => 2.9e23, "dilation" => 0.9 }
    ])

    get root_url

    vega = assigns(:profiles).last
    assert_equal %w[Vega Rigel], vega[:stars].map { |star| star[:name] }
    assert_select "#profile-system-#{@other.id} .inhabitant--star", 2
    assert_select "#profile-system-#{@other.id} .profile-intro", /Dvojhvězda Vega a Rigel/
  end

  test "relations carry signal delay, relative time and shared meetings" do
    Meeting.create!(start_time: "09:00", end_time: "10:00", participants: '["Earth", "Vega"]',
                    is_inter_system: true, participant_systems: { "Earth" => @system.id, "Vega" => @other.id }.to_json,
                    local_avg_duration: 50, avg_delay: 30)

    get root_url

    relation = assigns(:profiles).first[:relations].first
    assert_equal @other, relation[:system]
    assert relation[:signal_delay].positive?
    # Vega System is farther from the black hole, so more time passes there
    assert relation[:minutes_there_per_hour_here] > 60
    assert_equal 1, relation[:shared_meetings]
  end

  test "a system profile lists its intra- and inter-system meetings only" do
    own = Meeting.create!(start_time: "09:00", end_time: "10:00", participants: '["Earth", "Mars"]', system: @system,
                          local_avg_duration: 50, avg_delay: 10)
    shared = Meeting.create!(start_time: "11:00", end_time: "12:00", participants: '["Earth", "Vega"]',
                             is_inter_system: true, participant_systems: { "Earth" => @system.id, "Vega" => @other.id }.to_json,
                             local_avg_duration: 50, avg_delay: 30)
    foreign = Meeting.create!(start_time: "13:00", end_time: "14:00", participants: '["Vega", "Rigel"]', system: @other,
                              local_avg_duration: 50, avg_delay: 10)

    get root_url

    sol, vega = assigns(:profiles)
    assert_equal [ own, shared ], sol[:meetings]
    assert_equal [ shared, foreign ], vega[:meetings]
  end

  test "renders every profile hidden in the panel, keyed by file id" do
    get root_url

    assert_select "#system-panel .system-profile[hidden]", 3 # two systems + the black hole
    assert_select "#profile-system-#{@system.id}[data-file-id=?][data-hash=?]", @system.system_id, "soustava-#{@system.id}"
    assert_select "#profile-system-#{@system.id} .profile-intro", /Soustava hvězdy Sol leží/
    assert_select "#profile-system-#{@system.id} a[href=?]", galaxy_system_path(@system)
  end

  test "the black hole has its own profile with mass, horizon and the systems around it" do
    get root_url

    assert_select "#profile-black-hole[data-file-id=?][data-hash=?]", "black-hole", "cerna-dira"
    assert_select "#profile-black-hole .profile-facts dd", /10/ # mass in scientific notation
    # Systems listed nearest first: Sol System (283 units) before Vega System (300)
    assert_select "#profile-black-hole .inhabitant-name", count: 2 do |names|
      assert_match(/Sol System/, names.first.text)
      assert_match(/Vega System/, names.last.text)
    end
  end

  test "the story quotes the slowest and fastest system and the longest signal" do
    get root_url

    # Sol System sits closer to the black hole than Vega System
    assert_select "#pribeh", /Na soustavě Sol System\s+uběhne za vaši hodinu/
    assert_select "#pribeh", /na soustavě Vega System/
    assert_select "#pribeh", /Ze soustavy (Sol|Vega) System na soustavu (Sol|Vega) System letí/
  end

  test "the story ends with the meetings already planned and links to plan more" do
    Meeting.create!(start_time: "09:00", end_time: "10:00", participants: '["Earth", "Mars"]', system: @system,
                    local_avg_duration: 50, avg_delay: 10)

    get root_url

    assert_select "#pribeh", /v kalendáři 1 schůzku/
    assert_select "#pribeh a[href=?]", meetings_path
    assert_select "#pribeh a[href=?]", new_meeting_path
  end

  test "Soustavy lists every system nearest to the black hole first, plus adding one" do
    @system.update!(core: true)

    get galaxy_systems_url

    assert_response :success
    # Sol System (283 units out) is nearer than Vega System (300)
    assert_select ".systems-row:not(.systems-row--add) h2", count: 2 do |names|
      assert_equal [ "Sol System", "Vega System" ], names.map { |name| name.text.strip }
    end
    assert_select ".systems-row a[href=?]", root_path(anchor: "soustava-#{@other.id}")
    assert_select "a[href=?]", edit_galaxy_system_path(@system), count: 0
    assert_select "a[href=?]", edit_galaxy_system_path(@other)
    assert_select ".systems-row--add a[href=?]", new_galaxy_system_path
    assert_select "nav a.nav-link.active[href=?]", galaxy_systems_path
  end

  test "Soustavy without systems still offers to add one" do
    System.destroy_all

    get galaxy_systems_url

    assert_response :success
    assert_select ".systems-list-head", /žádné soustavy/
    assert_select ".systems-row--add a[href=?]", new_galaxy_system_path
  end

  test "core systems hide the edit link in their profile" do
    @system.update!(core: true)

    get root_url

    assert_select "#profile-system-#{@system.id} a[href=?]", edit_galaxy_system_path(@system), count: 0
    assert_select "#profile-system-#{@other.id} a[href=?]", edit_galaxy_system_path(@other)
  end

  test "shows an empty state without systems" do
    System.destroy_all

    get root_url

    assert_response :success
    assert_select ".system-profile:not(#profile-black-hole)", 0 # the black hole is always there
    assert_select ".galaxy-hero-hint", /žádné soustavy/
  end

  test "should build the galaxy time chart from systems" do
    get root_url

    assert_response :success
    chart = assigns(:galaxy_time_chart)
    system = chart[:systems].first
    assert_equal "Sol System", system[:name]
    assert_equal ApplicationHelper::SYSTEM_COLORS.first, system[:color]
    assert_equal 4, system[:bodies].size
    assert system[:bodies].all? { |body| body[:dilation].between?(0.0, 1.0) }
    assert_equal 50, chart[:curve].first[:x]
    assert_select "canvas#galaxyTimeChart[data-chart]"
  end

  test "should not link the developer cache and job pages" do
    get root_url

    assert_select "a[href=?]", dashboard_cache_stats_path, count: 0
    assert_select "a[href=?]", dashboard_job_performance_path, count: 0
  end

  test "should handle missing system data file gracefully" do
    File.delete(@system.data_file_path)
    GalaxyService.clear_system_cache(@system.system_id)

    get root_url

    assert_response :success
    sol = assigns(:profiles).first
    assert_empty sol[:stars]
    assert_empty sol[:planets]
    assert_equal 0, assigns(:galaxy_time_chart)[:systems].first[:bodies].size
  end
end
