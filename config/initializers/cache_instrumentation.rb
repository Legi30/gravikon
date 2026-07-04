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

# Track the galaxy/system data caches (keys are versioned, e.g.
# "galaxy_data_v2" and "system_data_<uuid>_v2" — match by prefix)
TRACKED_CACHE_KEY_PATTERN = /\A(system_data|galaxy_data)/

# Fetch hits are counted via cache_fetch_hit (NOT cache_read, which would
# double count the same fetch); misses via cache_generate.
ActiveSupport::Notifications.subscribe("cache_fetch_hit.active_support") do |name, start, finish, id, payload|
  if payload[:key].to_s.match?(TRACKED_CACHE_KEY_PATTERN)
    duration = finish - start
    CacheInstrumentation::Monitor.stats[:hits] += 1
    CacheInstrumentation::Monitor.stats[:total_read_time] += duration
  end
end

ActiveSupport::Notifications.subscribe("cache_generate.active_support") do |name, start, finish, id, payload|
  if payload[:key].to_s.match?(TRACKED_CACHE_KEY_PATTERN)
    duration = finish - start
    CacheInstrumentation::Monitor.stats[:misses] += 1
    CacheInstrumentation::Monitor.stats[:total_fetch_time] += duration
    CacheInstrumentation::Monitor.stats[:fetch_count] += 1
  end
end
