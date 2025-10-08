# frozen_string_literal: true

# Cache Statistics Rake Tasks
# Provides commands to view and reset cache performance metrics

namespace :cache do
  desc "Display cache performance statistics"
  task stats: :environment do
    report = CacheInstrumentation::Monitor.report

    puts "\n" + "=" * 80
    puts "CACHE PERFORMANCE REPORT - system_data cache"
    puts "=" * 80

    puts "\n📊 Cache Effectiveness:"
    puts "  Hit Rate:           #{report[:cache_hit_rate]}"
    puts "  Total Hits:         #{report[:total_hits]}"
    puts "  Total Misses:       #{report[:total_misses]}"

    puts "\n⏱️  Performance Metrics:"
    puts "  Avg Fetch Time:     #{report[:average_fetch_time_ms]} ms (cache miss - file read + JSON parse)"
    puts "  Avg Read Time:      #{report[:average_cache_read_time_ms]} ms (cache hit - memory read)"
    puts "  Time Saved per Hit: #{report[:time_saved_per_hit_ms]} ms"

    puts "\n📅 Monitoring Period:"
    puts "  Started:            #{report[:last_reset]}"
    puts "  Duration:           #{report[:monitoring_duration].round(2)} seconds"

    total_requests = report[:total_hits] + report[:total_misses]
    if total_requests > 0
      total_time_without_cache = total_requests * report[:average_fetch_time_ms]
      total_time_with_cache = (report[:total_hits] * report[:average_cache_read_time_ms]) +
                               (report[:total_misses] * report[:average_fetch_time_ms])
      time_saved = total_time_without_cache - total_time_with_cache

      puts "\n💾 Cache Impact:"
      puts "  Total Requests:     #{total_requests}"
      puts "  Without Cache:      #{total_time_without_cache.round(2)} ms total"
      puts "  With Cache:         #{total_time_with_cache.round(2)} ms total"
      puts "  Time Saved:         #{time_saved.round(2)} ms (#{(time_saved / 1000).round(2)}s)"
      puts "  Performance Gain:   #{((time_saved / total_time_without_cache) * 100).round(2)}%"
    end

    puts "\n" + "=" * 80

    if report[:cache_hit_rate].to_f < 90
      puts "\n⚠️  WARNING: Cache hit rate is below 90% (target: >90%)"
      puts "   Consider investigating cache invalidation frequency."
    else
      puts "\n✅ Cache hit rate meets performance target (>90%)"
    end

    puts "\n"
  end

  desc "Reset cache performance statistics"
  task reset_stats: :environment do
    old_stats = CacheInstrumentation::Monitor.report
    CacheInstrumentation::Monitor.reset!

    puts "\n✅ Cache statistics reset!"
    puts "   Previous hit rate: #{old_stats[:cache_hit_rate]}"
    puts "   Previous hits:     #{old_stats[:total_hits]}"
    puts "   Previous misses:   #{old_stats[:total_misses]}"
    puts "\n"
  end

  desc "Benchmark cache performance (runs 100 cache reads)"
  task benchmark: :environment do
    puts "\n🔬 Running cache performance benchmark..."
    puts "=" * 80

    # Ensure cache is primed
    Rails.cache.fetch('system_data') do
      JSON.parse(File.read(Rails.root.join("data/system_data.json")))
    rescue Errno::ENOENT, JSON::ParserError
      { "bodies" => [] }
    end

    # Warm up
    5.times do
      Rails.cache.read('system_data')
    end

    # Benchmark cache hits
    hit_times = []
    100.times do
      start = Time.now
      Rails.cache.read('system_data')
      hit_times << ((Time.now - start) * 1000)
    end

    # Benchmark cache miss (file read + JSON parse)
    Rails.cache.delete('system_data')
    miss_times = []
    10.times do
      Rails.cache.delete('system_data')
      start = Time.now
      Rails.cache.fetch('system_data') do
        JSON.parse(File.read(Rails.root.join("data/system_data.json")))
      rescue Errno::ENOENT, JSON::ParserError
        { "bodies" => [] }
      end
      miss_times << ((Time.now - start) * 1000)
    end

    puts "\n📊 Benchmark Results (100 cache hits, 10 cache misses):"
    puts "-" * 80
    puts "Cache Hit (memory read):"
    puts "  Average: #{(hit_times.sum / hit_times.size).round(4)} ms"
    puts "  Median:  #{hit_times.sort[hit_times.size / 2].round(4)} ms"
    puts "  Min:     #{hit_times.min.round(4)} ms"
    puts "  Max:     #{hit_times.max.round(4)} ms"

    puts "\nCache Miss (file I/O + JSON parse):"
    puts "  Average: #{(miss_times.sum / miss_times.size).round(4)} ms"
    puts "  Median:  #{miss_times.sort[miss_times.size / 2].round(4)} ms"
    puts "  Min:     #{miss_times.min.round(4)} ms"
    puts "  Max:     #{miss_times.max.round(4)} ms"

    speedup = (miss_times.sum / miss_times.size) / (hit_times.sum / hit_times.size)
    puts "\n⚡ Performance Improvement:"
    puts "  Cache is #{speedup.round(2)}x faster than file I/O"
    puts "  Time saved per hit: #{((miss_times.sum / miss_times.size) - (hit_times.sum / hit_times.size)).round(4)} ms"

    puts "\n" + "=" * 80 + "\n"
  end
end
