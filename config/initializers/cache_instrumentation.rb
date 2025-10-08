# frozen_string_literal: true

# Cache Instrumentation for Performance Monitoring
# Tracks cache hit/miss rates and performance metrics for system_data caching

module CacheInstrumentation
  class Monitor
    class << self
      def stats
        @stats ||= {
          hits: 0,
          misses: 0,
          total_fetch_time: 0.0,
          total_read_time: 0.0,
          fetch_count: 0,
          last_reset: Time.current
        }
      end

      def reset!
        @stats = {
          hits: 0,
          misses: 0,
          total_fetch_time: 0.0,
          total_read_time: 0.0,
          fetch_count: 0,
          last_reset: Time.current
        }
      end

      def hit_rate
        total = stats[:hits] + stats[:misses]
        return 0.0 if total.zero?
        (stats[:hits].to_f / total * 100).round(2)
      end

      def average_fetch_time
        return 0.0 if stats[:fetch_count].zero?
        (stats[:total_fetch_time] / stats[:fetch_count] * 1000).round(2) # ms
      end

      def average_read_time
        return 0.0 if stats[:hits].zero?
        (stats[:total_read_time] / stats[:hits] * 1000).round(2) # ms
      end

      def report
        {
          cache_hit_rate: "#{hit_rate}%",
          total_hits: stats[:hits],
          total_misses: stats[:misses],
          average_fetch_time_ms: average_fetch_time,
          average_cache_read_time_ms: average_read_time,
          time_saved_per_hit_ms: (average_fetch_time - average_read_time).round(2),
          monitoring_duration: Time.current - stats[:last_reset],
          last_reset: stats[:last_reset]
        }
      end

      def log_report
        Rails.logger.info("=" * 80)
        Rails.logger.info("CACHE PERFORMANCE REPORT - system_data cache")
        Rails.logger.info("=" * 80)
        report.each do |key, value|
          Rails.logger.info("  #{key}: #{value}")
        end
        Rails.logger.info("=" * 80)
      end
    end
  end
end

# Subscribe to ActiveSupport cache events
ActiveSupport::Notifications.subscribe("cache_read.active_support") do |name, start, finish, id, payload|
  # Only track system_data cache reads
  if payload[:key] == "system_data"
    duration = finish - start

    if payload[:hit]
      CacheInstrumentation::Monitor.stats[:hits] += 1
      CacheInstrumentation::Monitor.stats[:total_read_time] += duration
      Rails.logger.debug("Cache HIT: system_data (#{(duration * 1000).round(2)}ms)")
    else
      # Note: cache_read with miss=true means cache_fetch will generate value
      # The actual miss is tracked in cache_fetch_hit
    end
  end
end

ActiveSupport::Notifications.subscribe("cache_fetch_hit.active_support") do |name, start, finish, id, payload|
  if payload[:key] == "system_data"
    duration = finish - start
    CacheInstrumentation::Monitor.stats[:hits] += 1
    CacheInstrumentation::Monitor.stats[:total_read_time] += duration
    Rails.logger.debug("Cache FETCH_HIT: system_data (#{(duration * 1000).round(2)}ms)")
  end
end

ActiveSupport::Notifications.subscribe("cache_generate.active_support") do |name, start, finish, id, payload|
  if payload[:key] == "system_data"
    duration = finish - start
    CacheInstrumentation::Monitor.stats[:misses] += 1
    CacheInstrumentation::Monitor.stats[:total_fetch_time] += duration
    CacheInstrumentation::Monitor.stats[:fetch_count] += 1
    Rails.logger.info("Cache MISS: system_data - regenerating (#{(duration * 1000).round(2)}ms)")
  end
end

# Log cache stats periodically in development
if Rails.env.development?
  Thread.new do
    loop do
      sleep 300 # Every 5 minutes
      CacheInstrumentation::Monitor.log_report if CacheInstrumentation::Monitor.stats[:fetch_count] > 0
    end
  rescue => e
    Rails.logger.error("Cache instrumentation thread error: #{e.message}")
  end
end

Rails.logger.info("Cache instrumentation initialized for system_data cache monitoring")
