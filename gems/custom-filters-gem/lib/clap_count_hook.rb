require 'net/http'
require 'json'
require 'uri'

module ClapCountHook
  # Cache to avoid repeated API calls during development
  @@clap_cache = {}
  @@cache_file = '_clap_cache.json'

  def self.load_cache
    if File.exist?(@@cache_file)
      @@clap_cache = JSON.parse(File.read(@@cache_file))
    end
  end

  def self.save_cache
    File.write(@@cache_file, JSON.generate(@@clap_cache))
  end

  def self.fetch_clap_counts(urls)
    return {} if urls.empty?

    begin
      uri = URI('https://ip2o6c571d.execute-api.eu-west-2.amazonaws.com/production/get-multiple')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'text/plain'
      request.body = JSON.generate(urls)

      response = http.request(request)
      
      if response.code == '200'
        claps_data = JSON.parse(response.body)
        result = {}
        claps_data.each do |clap|
          result[clap['url']] = clap['claps'] || 0
        end
        return result
      else
        Jekyll.logger.warn "Clap API", "Failed to fetch clap counts: #{response.code}"
        return {}
      end
    rescue => e
      Jekyll.logger.warn "Clap API", "Error fetching clap counts: #{e.message}"
      return {}
    end
  end

  def self.get_post_url_for_api(post, site)
    # Convert post URL to the format expected by the API (without protocol)
    base_url = site.config['canonical']['url'] || site.config['url'] || 'https://blog.scottlogic.com'
    full_url = "#{base_url}#{post.url}"
    full_url.gsub(/^https?:\/\//, '')
  end
end

# Load cache on initialization
ClapCountHook.load_cache

Jekyll::Hooks.register :site, :post_read do |site|
  Jekyll.logger.info "Clap Count", "Loading clap counts for posts..."
  
  # Collect all post URLs
  urls = site.posts.docs.map do |post|
    ClapCountHook.get_post_url_for_api(post, site)
  end

  # Check cache first
  cached_urls = []
  fresh_urls = []
  
  urls.each do |url|
    if ClapCountHook.class_variable_get(:@@clap_cache).key?(url)
      cached_urls << url
    else
      fresh_urls << url
    end
  end

  # Fetch fresh clap counts
  if fresh_urls.any?
    Jekyll.logger.info "Clap Count", "Fetching #{fresh_urls.size} fresh clap counts..."
    fresh_claps = ClapCountHook.fetch_clap_counts(fresh_urls)
    ClapCountHook.class_variable_get(:@@clap_cache).merge!(fresh_claps)
    ClapCountHook.save_cache
  end

  # Assign clap counts to posts
  site.posts.docs.each do |post|
    url = ClapCountHook.get_post_url_for_api(post, site)
    clap_count = ClapCountHook.class_variable_get(:@@clap_cache)[url] || 0
    post.data['clap_count'] = clap_count
  end

  total_claps = ClapCountHook.class_variable_get(:@@clap_cache).values.sum
  Jekyll.logger.info "Clap Count", "Loaded clap counts for #{site.posts.docs.size} posts (#{total_claps} total claps)"
end

# Clear cache on clean builds
Jekyll::Hooks.register :site, :after_reset do |site|
  if File.exist?(ClapCountHook.class_variable_get(:@@cache_file))
    File.delete(ClapCountHook.class_variable_get(:@@cache_file))
    Jekyll.logger.info "Clap Count", "Cache cleared"
  end
end