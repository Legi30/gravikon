require "test_helper"

class GenerateSystemJobTest < ActiveJob::TestCase
  # Helper method to mock Process.spawn, Timeout, and exit status
  def with_mocked_process_execution(exit_status: 0, &block)
    Timeout.stub :timeout, lambda { |seconds, &blk| blk.call } do
      Process.stub :spawn, 12345 do
        Process.stub :wait, nil do
          $?.stub :exitstatus, exit_status do
            block.call
          end
        end
      end
    end
  end

  # === Parameter Validation Tests ===

  test "should validate num_planets is an integer" do
    assert_raises(ArgumentError, "Job accepted non-integer num_planets") do
      GenerateSystemJob.perform_now("invalid", 2)
    end
  end

  test "should validate max_moons is an integer" do
    assert_raises(ArgumentError, "Job accepted non-integer max_moons") do
      GenerateSystemJob.perform_now(5, "invalid")
    end
  end

  test "should raise error for num_planets less than 1" do
    assert_raises(ArgumentError, "Job accepted num_planets < 1") do
      GenerateSystemJob.perform_now(0, 2)
    end
  end

  test "should raise error for num_planets greater than 10" do
    assert_raises(ArgumentError, "Job accepted num_planets > 10") do
      GenerateSystemJob.perform_now(11, 2)
    end
  end

  test "should raise error for max_moons less than 0" do
    assert_raises(ArgumentError, "Job accepted max_moons < 0") do
      GenerateSystemJob.perform_now(5, -1)
    end
  end

  test "should raise error for max_moons greater than 5" do
    assert_raises(ArgumentError, "Job accepted max_moons > 5") do
      GenerateSystemJob.perform_now(5, 6)
    end
  end

  test "should accept num_planets at lower boundary (1)" do
    with_mocked_process_execution do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(1, 2)
      end
    end
  end

  test "should accept num_planets at upper boundary (10)" do
    with_mocked_process_execution do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(10, 2)
      end
    end
  end

  test "should accept max_moons at lower boundary (0)" do
    with_mocked_process_execution do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(5, 0)
      end
    end
  end

  test "should accept max_moons at upper boundary (5)" do
    with_mocked_process_execution do
      assert_nothing_raised do
        GenerateSystemJob.perform_now(5, 5)
      end
    end
  end

  # === Security Tests - Command Execution ===

  test "should use Process.spawn with explicit arguments (security)" do
    spawn_called = false
    spawn_args = nil

    # Mock Process.spawn to capture arguments
    Timeout.stub :timeout, lambda { |seconds, &blk| blk.call } do
      Process.stub :spawn, lambda { |*args|
        spawn_called = true
        spawn_args = args
        12345
      } do
        Process.stub :wait, nil do
          $?.stub :exitstatus, 0 do
            GenerateSystemJob.perform_now(5, 2)
          end
        end
      end
    end

    assert spawn_called, "Process.spawn was not called"
    # Verify first call is for generator with explicit arguments
    assert_equal "ruby", spawn_args[0], "First argument should be 'ruby'"
    assert spawn_args[1].include?("generator.rb"), "Second argument should include generator.rb path"
    assert_equal "5", spawn_args[2], "Third argument should be num_planets as string"
    assert_equal "2", spawn_args[3], "Fourth argument should be max_moons as string"
  end

  test "should not use shell interpolation (security)" do
    spawn_calls = []

    Timeout.stub :timeout, lambda { |seconds, &blk| blk.call } do
      Process.stub :spawn, lambda { |*args|
        spawn_calls << args
        # Verify no shell interpolation by checking each arg is separate
        args.each do |arg|
          next unless arg.is_a?(String)
          # If we find arguments joined with spaces, that's shell interpolation
          if arg.include?("generator.rb") && arg.include?(" ")
            raise "SECURITY VIOLATION: Using shell interpolation!"
          end
        end
        12345
      } do
        Process.stub :wait, nil do
          $?.stub :exitstatus, 0 do
            GenerateSystemJob.perform_now(5, 2)
          end
        end
      end
    end

    # Should have made 2 spawn calls (generator and visualizer)
    assert_equal 2, spawn_calls.length, "Should make 2 Process.spawn calls"
  end

  # === Exit Status Checking ===

  test "should raise error if generator script fails" do
    with_mocked_process_execution(exit_status: 1) do
      assert_raises(RuntimeError, "Job did not raise error for failed generator") do
        GenerateSystemJob.perform_now(5, 2)
      end
    end
  end

  test "should raise error if visualizer script fails" do
    spawn_count = 0
    exitstatus_calls = [0, 1]

    Timeout.stub :timeout, lambda { |seconds, &blk| blk.call } do
      Process.stub :spawn, lambda { |*args|
        spawn_count += 1
        12345
      } do
        Process.stub :wait, nil do
          # First call (generator) succeeds, second call (visualizer) fails
          $?.stub :exitstatus, lambda { exitstatus_calls.shift } do
            assert_raises(RuntimeError, "Job did not raise error for failed visualizer") do
              GenerateSystemJob.perform_now(5, 2)
            end
          end
        end
      end
    end
  end

  # === Cache Invalidation ===

  test "should clear system_data cache after completion" do
    # Set up cache with test data
    Rails.cache.write('system_data', {"test" => "data"})

    with_mocked_process_execution do
      GenerateSystemJob.perform_now(5, 2)
    end

    # Verify cache was deleted
    assert_nil Rails.cache.read('system_data'), "Cache was not cleared"
  end

  # === Job Enqueuing ===

  test "should be enqueueable" do
    assert_enqueued_with(job: GenerateSystemJob, args: [5, 2]) do
      GenerateSystemJob.perform_later(5, 2)
    end
  end

  test "should be enqueueable with different parameters" do
    assert_enqueued_with(job: GenerateSystemJob, args: [8, 3]) do
      GenerateSystemJob.perform_later(8, 3)
    end
  end

  # === Integer Conversion Edge Cases ===

  test "should handle string integers correctly" do
    with_mocked_process_execution do
      # Should convert string to integer
      assert_nothing_raised do
        GenerateSystemJob.perform_now("5", "2")
      end
    end
  end

  test "should reject float values" do
    assert_raises(ArgumentError, "Job accepted float num_planets") do
      GenerateSystemJob.perform_now(5.5, 2)
    end
  end

  test "should reject nil values" do
    assert_raises(ArgumentError, "Job accepted nil num_planets") do
      GenerateSystemJob.perform_now(nil, 2)
    end
  end
end
