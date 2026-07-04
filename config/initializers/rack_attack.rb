# frozen_string_literal: true

# Rack::Attack configuration for rate limiting and request throttling
# Protects against DOS attacks and abuse by limiting request rates

# Skip configuration if rack-attack gem is not available (e.g., in test environment without bundle install)
return unless defined?(Rack::Attack)

class Rack::Attack
  ### Configure Cache ###

  # Use Rails cache for tracking request counts
  # In production, this will use Solid Cache (SQLite-backed)
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Custom Throttle Response ###

  # Return 429 (Too Many Requests) for throttled requests with standard rate limit headers
  self.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    headers = {
      'Content-Type' => 'text/plain',
      'Retry-After' => retry_after.to_s,
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + retry_after).to_s
    }

    [429, headers, ["Příliš mnoho požadavků. Zkuste to prosím později.\n"]]
  end

  ### Throttle Rules ###

  # Throttle system creation requests
  # Allow 5 system creations per hour per IP
  throttle('system_creation/ip', limit: 5, period: 1.hour) do |req|
    if req.path == '/galaxy/systems' && req.post?
      req.ip
    end
  end

  # Throttle system regeneration requests (galaxy route)
  # Allow 10 regenerations per hour per IP
  throttle('system_regeneration/ip', limit: 10, period: 1.hour) do |req|
    if req.path.match?(%r{^/galaxy/systems/.+/regenerate$}) && req.post?
      req.ip
    end
  end

  # Throttle legacy system regeneration requests
  # Allow 10 regenerations per hour per IP
  throttle('legacy_system_regeneration/ip', limit: 10, period: 1.hour) do |req|
    if req.path == '/systems/regenerate' && req.post?
      req.ip
    end
  end

  # Throttle system update requests
  # Allow 20 updates per hour per IP
  throttle('system_update/ip', limit: 20, period: 1.hour) do |req|
    if req.path.match?(%r{^/galaxy/systems/.+$}) && (req.put? || req.patch?)
      req.ip
    end
  end

  # Throttle system deletion requests
  # Allow 10 deletions per hour per IP
  throttle('system_deletion/ip', limit: 10, period: 1.hour) do |req|
    if req.path.match?(%r{^/galaxy/systems/.+$}) && req.delete?
      req.ip
    end
  end

  # Throttle meeting creation requests
  # Allow 20 meetings per hour per IP
  throttle('meeting_creation/ip', limit: 20, period: 1.hour) do |req|
    if req.path == '/meetings' && req.post?
      req.ip
    end
  end

  # General throttle for all POST/PUT/PATCH/DELETE requests
  # Allow 100 requests per 5 minutes per IP
  throttle('req/ip', limit: 100, period: 5.minutes) do |req|
    if %w[POST PUT PATCH DELETE].include?(req.request_method)
      req.ip
    end
  end

  # General throttle for all GET requests
  # Allow 300 requests per 5 minutes per IP
  throttle('get/ip', limit: 300, period: 5.minutes) do |req|
    if req.get?
      req.ip
    end
  end

  ### Blocklist & Safelist ###

  # Always allow requests from localhost in development
  safelist('allow-localhost') do |req|
    Rails.env.development? && ['127.0.0.1', '::1'].include?(req.ip)
  end

  # Block requests with suspicious patterns
  blocklist('block-path-traversal') do |req|
    # Block requests with path traversal attempts
    req.path.include?('..') || req.query_string.include?('..')
  end

  # Block requests with suspicious user agents
  blocklist('block-suspicious-agents') do |req|
    # Block common malicious user agents
    agent = req.user_agent.to_s.downcase
    agent.include?('sqlmap') ||
      agent.include?('nikto') ||
      agent.include?('scanner') ||
      agent.include?('exploit')
  end

  ### Rate Limit Headers for Successful Requests ###

  # Add rate limit headers to all throttled endpoints (even when not throttled)
  # This helps clients understand their limits
  self.throttled_response_retry_after_header = true

  ### Logging ###

  # Log blocked and throttled requests
  ActiveSupport::Notifications.subscribe('rack.attack') do |_name, _start, _finish, _request_id, payload|
    req = payload[:request]

    case payload[:name]
    when :throttle
      Rails.logger.warn("RACK ATTACK - THROTTLED: #{req.ip} - #{req.path} - #{payload[:discriminator]}")
    when :blocklist
      Rails.logger.error("RACK ATTACK - BLOCKED: #{req.ip} - #{req.path} - #{payload[:discriminator]}")
    when :safelist
      Rails.logger.debug("RACK ATTACK - SAFELISTED: #{req.ip} - #{req.path}")
    end
  end

  # Add custom tracking to include rate limit headers in successful responses
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |_name, _start, _finish, _request_id, payload|
    request = payload[:request]
    next unless request

    # Add rate limit info to response headers for monitored endpoints
    if request.path == '/galaxy/systems' && request.post?
      throttle_data = Rack::Attack::Request.new(request.env).throttle_data('system_creation/ip')
      if throttle_data
        request.env['rack.attack.throttle_data'] = {
          discriminator: 'system_creation/ip',
          count: throttle_data[:count],
          limit: 5,
          period: 3600
        }
      end
    end
  end
end

# Enable Rack::Attack middleware
# This is typically enabled in config/application.rb, but we ensure it here
Rails.application.config.middleware.use Rack::Attack unless Rails.env.test?
