require "test_helper"

class GenerateSystemJobTest < ActiveJob::TestCase
  # Helper method to mock system generation without process execution
  def with_mocked_system_generation(success: true, &block)
    # Mock SystemGenerator to avoid actual file operations
    mock_generator = mock("SystemGenerator")
    mock_generator.stubs(:generate).returns(success ? { "bodies" => [] } : nil)
    mock_generator.stubs(:errors).returns(success ? [] : [ "Generation failed" ])

    SystemGenerator.stubs(:new).returns(mock_generator)

    # Mock GalaxyService methods
    GalaxyService.stubs(:add_system).returns(true)

    # Mock file operations
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:write).returns(true)

    # Mock PlanetarySystem visualization
    PlanetarySystem.stubs(:generate).returns(true)

    # Mock System.find_by to return a test system
    test_system = System.new(
      name: "Test System",
      x: 300.0,
      y: 300.0,
      json_file_path: "data/systems/test.json"
    )
    test_system.stubs(:save!).returns(true)
    System.stubs(:find_by).returns(test_system)

    block.call
  ensure
    SystemGenerator.unstub(:new)
    GalaxyService.unstub(:add_system)
    FileUtils.unstub(:mkdir_p)
    File.unstub(:write)
    PlanetarySystem.unstub(:generate)
    System.unstub(:find_by)
  end

  # === Parameter Validation Tests ===

  test "should validate num_planets is an integer" do
    assert_raises(ArgumentError, "Job accepted non-integer num_planets") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: "invalid",
        max_moons: 2
      )
    end
  end

  test "should validate max_moons is an integer" do
    assert_raises(ArgumentError, "Job accepted non-integer max_moons") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 5,
        max_moons: "invalid"
      )
    end
  end

  test "should raise error for num_planets less than 1" do
    assert_raises(ArgumentError, "Job accepted num_planets < 1") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 0,
        max_moons: 2
      )
    end
  end

  test "should raise error for num_planets greater than 10" do
    assert_raises(ArgumentError, "Job accepted num_planets > 10") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 11,
        max_moons: 2
      )
    end
  end

  test "should raise error for max_moons less than 0" do
    assert_raises(ArgumentError, "Job accepted max_moons < 0") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 5,
        max_moons: -1
      )
    end
  end

  test "should raise error for max_moons greater than 5" do
    assert_raises(ArgumentError, "Job accepted max_moons > 5") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 5,
        max_moons: 6
      )
    end
  end

  test "should accept num_planets at lower boundary (1)" do
    with_mocked_system_generation do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(
          system_id: "test",
          system_name: "Test",
          system_x: 300,
          system_y: 300,
          num_planets: 1,
          max_moons: 2
        )
      end
    end
  end

  test "should accept num_planets at upper boundary (10)" do
    with_mocked_system_generation do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(
          system_id: "test",
          system_name: "Test",
          system_x: 300,
          system_y: 300,
          num_planets: 10,
          max_moons: 2
        )
      end
    end
  end

  test "should accept max_moons at lower boundary (0)" do
    with_mocked_system_generation do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(
          system_id: "test",
          system_name: "Test",
          system_x: 300,
          system_y: 300,
          num_planets: 5,
          max_moons: 0
        )
      end
    end
  end

  test "should accept max_moons at upper boundary (5)" do
    with_mocked_system_generation do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(
          system_id: "test",
          system_name: "Test",
          system_x: 300,
          system_y: 300,
          num_planets: 5,
          max_moons: 5
        )
      end
    end
  end

  # === Security Tests - SystemGenerator Integration ===

  test "should use SystemGenerator.new with validated parameters" do
    generator_params = nil

    SystemGenerator.stubs(:new).with { |**params|
      generator_params = params
      true
    }.returns(stub(generate: { "bodies" => [] }, errors: []))

    GalaxyService.stubs(:add_system).returns(true)
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:write).returns(true)
    PlanetarySystem.stubs(:generate).returns(true)
    test_system = System.new(name: "Test", x: 300, y: 300, json_file_path: "data/systems/test.json")
    test_system.stubs(:save!).returns(true)
    System.stubs(:find_by).returns(test_system)

    GenerateSystemJob.perform_now(
      system_id: "test123",
      system_name: "TestSystem",
      system_x: 250.5,
      system_y: 350.75,
      num_planets: 5,
      max_moons: 2
    )

    assert_not_nil generator_params, "SystemGenerator.new was not called"
    assert_equal "test123", generator_params[:system_id]
    assert_equal "TestSystem", generator_params[:system_name]
    assert_equal 250.5, generator_params[:system_x]
    assert_equal 350.75, generator_params[:system_y]
    assert_equal 5, generator_params[:num_planets]
    assert_equal 2, generator_params[:max_moons_per_planet]
  ensure
    SystemGenerator.unstub(:new)
    GalaxyService.unstub(:add_system)
    FileUtils.unstub(:mkdir_p)
    File.unstub(:write)
    PlanetarySystem.unstub(:generate)
    System.unstub(:find_by)
  end

  # === Error Handling ===

  test "should raise error if system generation fails" do
    with_mocked_system_generation(success: false) do
      assert_raises(StandardError, "Job did not raise error for failed generator") do
        GenerateSystemJob.perform_now(
          system_id: "test",
          system_name: "Test",
          system_x: 300,
          system_y: 300,
          num_planets: 5,
          max_moons: 2
        )
      end
    end
  end

  # === Cache Invalidation ===

  test "should clear system_data cache after completion" do
    # Set up cache with test data under the real versioned key
    cache_key = "system_data_test_#{GalaxyService::CACHE_VERSION}"
    Rails.cache.write(cache_key, { "test" => "data" })

    with_mocked_system_generation do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 5,
        max_moons: 2
      )
    end

    # Verify cache was deleted
    assert_nil Rails.cache.read(cache_key), "Cache was not cleared"
  end

  # === Job Enqueuing ===

  test "should be enqueueable" do
    job_args = {
      system_id: "test",
      system_name: "Test",
      system_x: 300,
      system_y: 300,
      num_planets: 5,
      max_moons: 2
    }
    assert_enqueued_with(job: GenerateSystemJob) do
      GenerateSystemJob.perform_later(**job_args)
    end
  end

  test "should be enqueueable with different parameters" do
    job_args = {
      system_id: "test2",
      system_name: "Test2",
      system_x: 400,
      system_y: 400,
      num_planets: 8,
      max_moons: 3
    }
    assert_enqueued_with(job: GenerateSystemJob) do
      GenerateSystemJob.perform_later(**job_args)
    end
  end

  # === Integer Conversion Edge Cases ===

  test "should handle string integers correctly" do
    with_mocked_system_generation do
      # Should convert string to integer
      assert_nothing_raised do
        GenerateSystemJob.perform_now(
          system_id: "test",
          system_name: "Test",
          system_x: 300,
          system_y: 300,
          num_planets: "5",
          max_moons: "2"
        )
      end
    end
  end

  test "should reject float values" do
    assert_raises(ArgumentError, "Job accepted float num_planets") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: 5.5,
        max_moons: 2
      )
    end
  end

  test "should reject nil values" do
    assert_raises(ArgumentError, "Job accepted nil num_planets") do
      GenerateSystemJob.perform_now(
        system_id: "test",
        system_name: "Test",
        system_x: 300,
        system_y: 300,
        num_planets: nil,
        max_moons: 2
      )
    end
  end
end
