# frozen_string_literal: true

class DashboardController < ApplicationController
  # The dashboard introduces the star systems (one profile at a time) and
  # keeps the galaxy-wide time chart; meetings only appear inside the profile
  # of the systems they connect. Built through `helpers` because the data
  # helpers use view helpers (system colours, km formatting).
  def index
    @profiles = helpers.galaxy_system_profiles
    @galaxy_time_chart = helpers.galaxy_time_chart_data
  end

  def cache_stats
    # Get cache performance metrics
    @cache_report = CacheInstrumentation::Monitor.report
    @cache_stats = CacheInstrumentation::Monitor.stats

    # Calculate additional metrics
    total_requests = @cache_stats[:hits] + @cache_stats[:misses]
    if total_requests > 0
      avg_fetch = @cache_report[:average_fetch_time_ms]
      avg_read = @cache_report[:average_cache_read_time_ms]

      @total_time_without_cache = total_requests * avg_fetch
      @total_time_with_cache = (@cache_stats[:hits] * avg_read) + (@cache_stats[:misses] * avg_fetch)
      @time_saved = @total_time_without_cache - @total_time_with_cache
      @performance_gain = (@time_saved / @total_time_without_cache * 100).round(2)
    else
      @total_time_without_cache = 0
      @total_time_with_cache = 0
      @time_saved = 0
      @performance_gain = 0
    end

    respond_to do |format|
      format.html # render cache_stats.html.erb
      format.json { render json: @cache_report }
    end
  end

  def job_performance
    # Get job performance history from cache
    @job_history = Rails.cache.fetch("job_performance_history") { [] }

    if @job_history.any?
      # Calculate statistics
      total_times = @job_history.map { |m| m[:total_duration] }
      @within_target_count = @job_history.count { |m| m[:within_target] }
      @target_percentage = (@within_target_count.to_f / @job_history.size * 100).round(1)

      @avg_total_time = (total_times.sum / total_times.size).round(3)
      @min_time = total_times.min.round(3)
      @max_time = total_times.max.round(3)

      # Not every job type records these (galaxy visualization has no generator)
      generator_times = @job_history.filter_map { |m| m[:generator_duration] }
      visualizer_times = @job_history.filter_map { |m| m[:visualizer_duration] }
      @avg_generator_time = generator_times.any? ? (generator_times.sum / generator_times.size).round(3) : 0
      @avg_visualizer_time = visualizer_times.any? ? (visualizer_times.sum / visualizer_times.size).round(3) : 0
    else
      @within_target_count = 0
      @target_percentage = 0
      @avg_total_time = 0
      @min_time = 0
      @max_time = 0
      @avg_generator_time = 0
      @avg_visualizer_time = 0
    end

    respond_to do |format|
      format.html # render job_performance.html.erb
      format.json do
        render json: {
          history: @job_history,
          stats: {
            within_target_count: @within_target_count,
            target_percentage: @target_percentage,
            avg_total_time: @avg_total_time,
            min_time: @min_time,
            max_time: @max_time
          }
        }
      end
    end
  end
end
