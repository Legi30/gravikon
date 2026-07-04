ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each parallel worker writes generated galaxy/system data into its own
    # tmp directory — tests must never touch the real data/ and public/ roots.
    parallelize_setup do |worker|
      Rails.application.config.x.gravikon.data_root = Rails.root.join("tmp/test_gravikon/#{worker}/data")
      Rails.application.config.x.gravikon.svg_root = Rails.root.join("tmp/test_gravikon/#{worker}/public")
    end

    setup do
      FileUtils.mkdir_p(GalaxyService.systems_data_dir)
      FileUtils.mkdir_p(GalaxyService.systems_svg_dir)
    end

    teardown do
      # Isolate tests from each other: wipe this worker's generated files
      FileUtils.rm_rf(GalaxyService.data_root)
      FileUtils.rm_rf(GalaxyService.svg_root)
      Rails.cache.clear
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Write a system data JSON file for the given System record (or file id)
    # inside the isolated test data root. Returns the parsed body list.
    def write_system_data(system_or_id, bodies)
      file_id = system_or_id.is_a?(System) ? system_or_id.system_id : system_or_id
      path = GalaxyService.system_data_path(file_id)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, ::JSON.pretty_generate({ "system_id" => file_id, "bodies" => bodies }))
      GalaxyService.clear_system_cache(file_id)
      bodies
    end

    # Minimal valid body set (star + two planets) for meeting tests
    def default_test_bodies(names = %w[Stelaris Plaxer Plomur])
      star, *planets = names
      bodies = [ { "name" => star, "type" => "star", "x" => 400, "y" => 400, "radius" => 7.0e7, "mass" => 1.9e27, "dilation" => 1.0 } ]
      planets.each_with_index do |name, i|
        bodies << { "name" => name, "type" => "planet", "x" => 400 + 100 + i * 60, "y" => 400, "radius" => 2.5e6, "mass" => 2.9e23, "dilation" => 0.9 }
      end
      bodies
    end
  end
end
