# frozen_string_literal: true

class GenerateSystemJob < ApplicationJob
  queue_as :default

  # Retry on transient errors (file system issues, etc.)
  retry_on StandardError, wait: 5.seconds, attempts: 3 do |job, error|
    Rails.logger.error("GenerateSystemJob: Retry attempt failed - #{error.class}: #{error.message}")
  end

  # Don't retry on validation errors (invalid parameters)
  discard_on ArgumentError do |job, error|
    Rails.logger.error("GenerateSystemJob: Discarded due to invalid parameters - #{error.message}")
  end

  def perform(num_planets, max_moons)
    job_start_time = Time.current
    # Striktní validace vstupních parametrů
    begin
      # Ověříme, že parametry jsou celá čísla
      num_planets = Integer(num_planets)
      max_moons = Integer(max_moons)
    rescue ArgumentError, TypeError => e
      Rails.logger.error("GenerateSystemJob: Invalid parameters - #{e.message}")
      raise ArgumentError, "Invalid parameters: num_planets and max_moons must be integers"
    end

    # Validace rozsahů
    unless num_planets.between?(1, 10)
      Rails.logger.error("GenerateSystemJob: num_planets out of range: #{num_planets}")
      raise ArgumentError, "num_planets must be between 1 and 10"
    end

    unless max_moons.between?(0, 5)
      Rails.logger.error("GenerateSystemJob: max_moons out of range: #{max_moons}")
      raise ArgumentError, "max_moons must be between 0 and 5"
    end

    # Cesty ke skriptům
    generator_script = Rails.root.join("lib", "generator.rb").to_s
    visualizer_script = Rails.root.join("lib", "visualizer.rb").to_s

    # Audit log před spuštěním
    Rails.logger.info("GenerateSystemJob: Starting execution with num_planets=#{num_planets}, max_moons=#{max_moons}")

    begin
      # 1. Spustíme generátor nové soustavy
      # Použití spawn s explicitními argumenty místo string interpolace
      # zabraňuje command injection útokům
      generator_start = Time.current

      pid = Process.spawn(
        "ruby", generator_script, num_planets.to_s, max_moons.to_s,
        chdir: Rails.root.to_s,
        out: :out,  # Přesměruje stdout na standardní výstup
        err: :err   # Přesměruje stderr na standardní chybový výstup
      )

      # Wait for process with timeout protection (30 seconds max)
      begin
        Timeout.timeout(30) do
          Process.wait(pid)
        end
      rescue Timeout::Error
        Process.kill('TERM', pid)
        Process.wait(pid)
        raise "Generator script timed out after 30 seconds"
      end

      generator_status = $?.exitstatus
      generator_duration = Time.current - generator_start

      if generator_status != 0
        Rails.logger.error("GenerateSystemJob: Generator script failed with exit status #{generator_status}")
        raise "Generator script failed with exit status #{generator_status}"
      end

      Rails.logger.info("GenerateSystemJob: Generator completed successfully in #{generator_duration.round(2)}s")

      # 2. Spustíme vizualizér
      visualizer_start = Time.current
      Rails.logger.info("GenerateSystemJob: Executing visualizer")

      pid = Process.spawn(
        "ruby", visualizer_script,
        chdir: Rails.root.to_s,
        out: :out,
        err: :err
      )

      # Wait for process with timeout protection (30 seconds max)
      begin
        Timeout.timeout(30) do
          Process.wait(pid)
        end
      rescue Timeout::Error
        Process.kill('TERM', pid)
        Process.wait(pid)
        raise "Visualizer script timed out after 30 seconds"
      end

      visualizer_status = $?.exitstatus
      visualizer_duration = Time.current - visualizer_start

      if visualizer_status != 0
        Rails.logger.error("GenerateSystemJob: Visualizer script failed with exit status #{visualizer_status}")
        raise "Visualizer script failed with exit status #{visualizer_status}"
      end

      Rails.logger.info("GenerateSystemJob: Visualizer completed successfully in #{visualizer_duration.round(2)}s")

      # 3. Invalidujeme cache
      Rails.cache.delete('system_data')

      # Calculate total job execution time
      total_duration = Time.current - job_start_time

      # Log performance metrics
      Rails.logger.info("GenerateSystemJob: Cache invalidated")
      Rails.logger.info("=" * 80)
      Rails.logger.info("GenerateSystemJob PERFORMANCE SUMMARY:")
      Rails.logger.info("  Parameters: #{num_planets} planets, #{max_moons} max moons")
      Rails.logger.info("  Generator time: #{generator_duration.round(2)}s")
      Rails.logger.info("  Visualizer time: #{visualizer_duration.round(2)}s")
      Rails.logger.info("  Total time: #{total_duration.round(2)}s")
      Rails.logger.info("  Status: SUCCESS")

      if total_duration > 30
        Rails.logger.warn("  WARNING: Job exceeded 30s target (#{total_duration.round(2)}s)")
      else
        Rails.logger.info("  Performance: Within 30s target ✓")
      end
      Rails.logger.info("=" * 80)

      # Store performance metrics for monitoring
      store_performance_metrics(num_planets, max_moons, generator_duration, visualizer_duration, total_duration)

    rescue => e
      job_duration = Time.current - job_start_time
      Rails.logger.error("GenerateSystemJob: Execution failed after #{job_duration.round(2)}s - #{e.class}: #{e.message}")
      Rails.logger.error("  Backtrace: #{e.backtrace.first(5).join("\n  ")}")
      raise
    end
  end

  private

  def store_performance_metrics(num_planets, max_moons, gen_time, viz_time, total_time)
    # Store metrics in Rails cache for dashboard access
    metrics = {
      timestamp: Time.current,
      num_planets: num_planets,
      max_moons: max_moons,
      generator_duration: gen_time.round(3),
      visualizer_duration: viz_time.round(3),
      total_duration: total_time.round(3),
      within_target: total_time <= 30
    }

    # Keep last 20 job executions
    history = Rails.cache.fetch('job_performance_history') { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write('job_performance_history', history)

    Rails.logger.debug("GenerateSystemJob: Performance metrics stored")
  end
end
