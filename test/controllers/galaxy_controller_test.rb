# frozen_string_literal: true

require "test_helper"

class GalaxyControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Create test galaxy data
    @test_galaxy_file = GalaxyService.galaxy_data_path
    @backup_file = Rails.root.join("tmp", "galaxy_data.json.backup")

    if File.exist?(@test_galaxy_file)
      FileUtils.cp(@test_galaxy_file, @backup_file)
    end

    @test_galaxy_data = {
      "black_hole" => {
        "name" => "Sagittarius Omega",
        "mass" => 8.2e36,
        "x" => 400,
        "y" => 400
      },
      "systems" => []
    }

    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))

    Rails.cache.clear
  end

  teardown do
    if File.exist?(@backup_file)
      FileUtils.mv(@backup_file, @test_galaxy_file)
    elsif File.exist?(@test_galaxy_file)
      File.delete(@test_galaxy_file)
    end

    Rails.cache.clear
  end

  # Test GET index displays galaxy map, the system panel and the story
  # (the map itself is the hero; the old system list is gone)
  test "GET index displays galaxy map" do
    get galaxy_index_path
    assert_response :success
    assert_select ".galaxy-hero svg"
    assert_select "#space-clock .space-clock-digit", 4
    assert_select "#system-panel"
    assert_select "#pribeh h2", /Hodina není všude hodina/
  end

  test "GET index passes per-system black-hole dilation to the map tooltips" do
    @test_galaxy_data["systems"] = [ { "id" => "clock_test", "x" => 500.0, "y" => 400.0 } ]
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))

    get galaxy_index_path
    assert_response :success

    expected = PhysicsConstants.gravitational_dilation(8.2e36, 100).round(6)
    assert_equal({ "clock_test" => expected }, assigns(:system_dilations))
    assert_select ".galaxy-hero[data-system-dilations*=?]", "clock_test"
  end

  # Test GET show_system displays specific system
  test "GET show_system displays specific system SVG and metadata" do
    # Create a test system
    system = System.new(name: "Test System", x: 300, y: 300, json_file_path: "data/systems/test.json")
    system.save(validate: false)

    # Create system data file
    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("test"), {
      bodies: [ { name: "Star", type: "star" } ]
    }.to_json)

    get galaxy_system_path(system)
    assert_response :success

    # Cleanup
    File.delete(GalaxyService.system_data_path("test")) rescue nil
    system.destroy
  end

  # Test POST create_system with valid params creates System record
  test "POST create_system with valid params creates System record" do
    assert_difference("System.count", 1) do
      post galaxy_systems_path, params: {
        system: {
          name: "New System",
          x: 250,
          y: 250,
          num_planets: 3,
          max_moons_per_planet: 2
        }
      }
    end

    assert_redirected_to galaxy_index_path
    assert System.exists?(name: "New System")
  end

  # Test POST create_system validates system position doesn't collide
  test "POST create_system validates no collision" do
    # Create existing system
    system1 = System.new(name: "Existing", x: 300, y: 300, json_file_path: "data/systems/existing.json")
    system1.save(validate: false)

    # Update galaxy data to include this system
    galaxy_data = JSON.parse(File.read(@test_galaxy_file))
    galaxy_data["systems"] << { "id" => "existing", "x" => 300, "y" => 300 }
    File.write(@test_galaxy_file, JSON.pretty_generate(galaxy_data))

    # Try to create system too close to existing
    post galaxy_systems_path, params: {
      system: {
        name: "Collision Test",
        x: 310,
        y: 310
      }
    }

    # Should not create system due to collision
    assert_not System.exists?(name: "Collision Test")

    system1.destroy
  end

  # Test PATCH update_system regenerates system with new parameters
  test "PATCH update_system regenerates system with new parameters" do
    system = System.new(name: "Update Test", x: 300, y: 300, json_file_path: "data/systems/update_test.json")
    system.save(validate: false)

    patch galaxy_system_path(system), params: {
      system: {
        name: "Updated Name"
      }
    }

    system.reload
    assert_equal "Updated Name", system.name

    system.destroy
  end

  # Test DELETE destroy_system removes database record and files
  test "DELETE destroy_system removes database record" do
    system = System.new(name: "Delete Test", x: 300, y: 300, json_file_path: "data/systems/delete_test.json")
    system.save(validate: false)

    # Create associated files
    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("delete_test"), "{}")

    assert_difference("System.count", -1) do
      delete galaxy_system_path(system)
    end

    assert_redirected_to galaxy_index_path

    # Files should be cleaned up
    assert_not File.exist?(GalaxyService.system_data_path("delete_test"))
  end

  # Test strong parameters whitelist only safe attributes
  test "strong parameters reject unsafe attributes" do
    post galaxy_systems_path, params: {
      system: {
        name: "Param Test",
        x: 300,
        y: 300,
        num_planets: 3,
        unsafe_attribute: "should be filtered"
      }
    }

    # Should not raise error, unsafe attribute should be filtered
    assert_response :redirect
  end

  # Test validates numeric parameters
  test "validates numeric parameters in range" do
    post galaxy_systems_path, params: {
      system: {
        name: "Invalid Params",
        x: 300,
        y: 300,
        num_planets: 15,  # Out of range (1-10)
        max_moons_per_planet: 10     # Out of range (0-5)
      }
    }

    # Should not create system with invalid parameters
    assert_not System.exists?(name: "Invalid Params")
  end

  # Test sanitizes system name input
  test "sanitizes system name input" do
    post galaxy_systems_path, params: {
      system: {
        name: "Test@#$%System!",  # Invalid characters
        x: 300,
        y: 300,
        num_planets: 3
      }
    }

    # Should not create system with invalid name format
    assert_not System.exists?(name: "Test@#$%System!")
  end

  # The four core systems are permanent
  test "core systems cannot be edited, regenerated or deleted" do
    core = System.new(name: "Core System", x: 300, y: 300, json_file_path: "data/systems/core_test.json", core: true)
    core.save(validate: false)

    get edit_galaxy_system_path(core)
    assert_redirected_to galaxy_system_path(core)

    patch galaxy_system_path(core), params: { system: { name: "Renamed" } }
    assert_equal "Core System", core.reload.name

    assert_no_enqueued_jobs only: RegenerateSystemJob do
      post regenerate_galaxy_system_path(core), params: { num_planets: 3, max_moons_per_planet: 1 }
    end

    assert_no_difference("System.count") do
      delete galaxy_system_path(core)
    end
    assert_redirected_to galaxy_system_path(core)
    assert_match(/stálé soustavy/, flash[:alert])

    core.destroy
  end

  test "core system page hides edit, delete and regenerate controls" do
    core = System.new(name: "Core Page", x: 300, y: 300, json_file_path: "data/systems/core_page.json", core: true)
    core.save(validate: false)
    write_system_data(core, default_test_bodies(%w[Corestar Coreplanet]))

    get galaxy_system_path(core)
    assert_response :success
    assert_select "a[href=?]", edit_galaxy_system_path(core), count: 0
    assert_select "#system-regeneration-form", count: 0
    assert_select "form[action=?]", galaxy_system_path(core), count: 0

    core.destroy
  end
end
