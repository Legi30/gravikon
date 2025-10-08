# frozen_string_literal: true

# Background Job Performance Benchmarking
# Measures GenerateSystemJob execution time for different parameter values

namespace :job do
  desc "Benchmark GenerateSystemJob performance across different parameter values"
  task benchmark: :environment do
    puts "\n" + "=" * 80
    puts "BACKGROUND JOB PERFORMANCE BENCHMARK"
    puts "=" * 80
    puts "\nTesting GenerateSystemJob with varying parameters..."
    puts "Target: Complete within 30 seconds for all configurations\n"

    test_cases = [
      { planets: 1, moons: 0, description: "Minimum (1 planet, 0 moons)" },
      { planets: 3, moons: 1, description: "Small (3 planets, 1 moon)" },
      { planets: 5, moons: 2, description: "Medium (5 planets, 2 moons)" },
      { planets: 7, moons: 3, description: "Large (7 planets, 3 moons)" },
      { planets: 10, moons: 5, description: "Maximum (10 planets, 5 moons)" }
    ]

    results = []

    test_cases.each do |test_case|
      puts "\n" + "-" * 80
      puts "Test Case: #{test_case[:description]}"
      puts "-" * 80

      begin
        # Execute job synchronously and measure time
        start_time = Time.current
        GenerateSystemJob.perform_now(test_case[:planets], test_case[:moons])
        duration = Time.current - start_time

        # Retrieve metrics from cache
        history = Rails.cache.fetch('job_performance_history') { [] }
        latest = history.last

        results << {
          test_case: test_case[:description],
          planets: test_case[:planets],
          moons: test_case[:moons],
          total_time: duration.round(3),
          generator_time: latest ? latest[:generator_duration] : nil,
          visualizer_time: latest ? latest[:visualizer_duration] : nil,
          within_target: duration <= 30,
          status: "SUCCESS"
        }

        puts "  Total Time:      #{duration.round(3)}s"
        puts "  Generator:       #{latest ? latest[:generator_duration] : 'N/A'}s"
        puts "  Visualizer:      #{latest ? latest[:visualizer_duration] : 'N/A'}s"
        puts "  Target Met:      #{duration <= 30 ? '✓ YES' : '✗ NO (exceeded 30s)'}"

      rescue => e
        duration = Time.current - start_time rescue 0
        results << {
          test_case: test_case[:description],
          planets: test_case[:planets],
          moons: test_case[:moons],
          total_time: duration.round(3),
          generator_time: nil,
          visualizer_time: nil,
          within_target: false,
          status: "FAILED",
          error: e.message
        }

        puts "  Status:          FAILED"
        puts "  Error:           #{e.message}"
        puts "  Duration:        #{duration.round(3)}s"
      end
    end

    # Summary report
    puts "\n" + "=" * 80
    puts "BENCHMARK SUMMARY"
    puts "=" * 80

    successful = results.select { |r| r[:status] == "SUCCESS" }
    failed = results.select { |r| r[:status] == "FAILED" }
    within_target = successful.select { |r| r[:within_target] }

    puts "\n📊 Overall Statistics:"
    puts "  Total Tests:           #{results.size}"
    puts "  Successful:            #{successful.size}"
    puts "  Failed:                #{failed.size}"
    puts "  Within 30s Target:     #{within_target.size}/#{successful.size}"

    if successful.any?
      times = successful.map { |r| r[:total_time] }
      puts "\n⏱️  Execution Time Statistics:"
      puts "  Fastest:               #{times.min}s (#{successful.min_by { |r| r[:total_time] }[:test_case]})"
      puts "  Slowest:               #{times.max}s (#{successful.max_by { |r| r[:total_time] }[:test_case]})"
      puts "  Average:               #{(times.sum / times.size).round(3)}s"
      puts "  Median:                #{times.sort[times.size / 2].round(3)}s"
    end

    # Detailed results table
    puts "\n📋 Detailed Results:"
    puts "-" * 80
    printf("%-30s %8s %6s %10s %8s\n", "Test Case", "Planets", "Moons", "Time (s)", "Target")
    puts "-" * 80

    results.each do |r|
      target_symbol = r[:status] == "SUCCESS" ? (r[:within_target] ? "✓" : "✗") : "✗"
      printf("%-30s %8d %6d %10.3f %8s\n",
             r[:test_case],
             r[:planets],
             r[:moons],
             r[:total_time],
             target_symbol)
    end
    puts "-" * 80

    # Performance assessment
    puts "\n🎯 Performance Assessment:"
    if failed.any?
      puts "  ⚠️  WARNING: #{failed.size} test(s) failed"
      failed.each { |r| puts "     - #{r[:test_case]}: #{r[:error]}" }
    end

    if successful.any? && within_target.size == successful.size
      puts "  ✅ EXCELLENT: All tests completed within 30s target"
    elsif within_target.size > 0
      puts "  ⚠️  PARTIAL: #{within_target.size}/#{successful.size} tests within target"
      exceeded = successful - within_target
      exceeded.each { |r| puts "     - #{r[:test_case]}: #{r[:total_time]}s (exceeded by #{(r[:total_time] - 30).round(2)}s)" }
    else
      puts "  ❌ POOR: No tests completed within 30s target"
    end

    # Scaling analysis
    if successful.size >= 3
      puts "\n📈 Scaling Analysis:"
      small = results.find { |r| r[:planets] == 1 }
      large = results.find { |r| r[:planets] == 10 }

      if small && large && small[:status] == "SUCCESS" && large[:status] == "SUCCESS"
        scaling_factor = (large[:total_time] / small[:total_time]).round(2)
        puts "  Time increase (1→10 planets): #{scaling_factor}x"
        puts "  Complexity: #{scaling_factor < 5 ? 'Sub-linear (good)' : scaling_factor < 10 ? 'Linear' : 'Super-linear (concerning)'}"
      end
    end

    puts "\n" + "=" * 80 + "\n"
  end

  desc "View recent job performance history"
  task performance_history: :environment do
    history = Rails.cache.fetch('job_performance_history') { [] }

    if history.empty?
      puts "\nNo job performance data available yet."
      puts "Run some system regenerations or execute: rake job:benchmark\n"
      return
    end

    puts "\n" + "=" * 80
    puts "JOB PERFORMANCE HISTORY (Last #{history.size} executions)"
    puts "=" * 80

    puts "\n%-19s %8s %6s %10s %10s %10s %8s" % [
      "Timestamp", "Planets", "Moons", "Gen (s)", "Viz (s)", "Total (s)", "Target"
    ]
    puts "-" * 80

    history.each do |metrics|
      printf("%-19s %8d %6d %10.3f %10.3f %10.3f %8s\n",
             metrics[:timestamp].strftime("%Y-%m-%d %H:%M:%S"),
             metrics[:num_planets],
             metrics[:max_moons],
             metrics[:generator_duration],
             metrics[:visualizer_duration],
             metrics[:total_duration],
             metrics[:within_target] ? "✓" : "✗")
    end

    puts "-" * 80

    # Statistics
    total_times = history.map { |m| m[:total_duration] }
    within_target_count = history.count { |m| m[:within_target] }

    puts "\n📊 Statistics:"
    puts "  Total Executions:      #{history.size}"
    puts "  Within Target (30s):   #{within_target_count}/#{history.size} (#{(within_target_count.to_f / history.size * 100).round(1)}%)"
    puts "  Average Time:          #{(total_times.sum / total_times.size).round(3)}s"
    puts "  Fastest:               #{total_times.min.round(3)}s"
    puts "  Slowest:               #{total_times.max.round(3)}s"

    puts "\n" + "=" * 80 + "\n"
  end

  desc "Clear job performance history"
  task clear_history: :environment do
    Rails.cache.delete('job_performance_history')
    puts "\n✅ Job performance history cleared\n"
  end
end
