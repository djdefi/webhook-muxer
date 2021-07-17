# Webhook multiplexer
#
# Listens for webhooks from a GitHub repository and forwards it to multiple configurable endpoints
#
# Usage:
#   $ ./webhook-mux.rb [-c config.yml] [-p port] [-u url1,url2,...]
#
# Config:
#   -c, --config=CONFIG
#       Path to config file
#   -p, --port=PORT
#       Port to listen on for incoming hooks
#   -u, --url=URL
#       CSV list of URLs to forward webhooks to
#
# Example:
#   $ ./webhook-mux.rb -c config.yml -p 9090 -u http://localhost:8080,http://localhost:8081
#
# Notes:
#   - Config file is optional, but if provided, must be valid YAML
#   - If no port is provided, the default port will be used

# Start listening for webhooks
require 'sinatra'
require 'yaml'
require 'json'
require 'uri'
require 'net/http'
require 'logger'
require 'parallel'

# Load list of URLs to forward webhooks to from urls.txt
def load_urls
  urls = []
  File.open('urls.txt', 'r') do |f|
    f.each_line do |line|
      urls << line.strip
    end
  end
  urls
end


# Set up logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.datetime_format = "%Y-%m-%d %H:%M:%S"
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} - #{severity} - #{msg}\n"
end


# Set up Sinatra
set :logger, logger
set :public_folder, File.dirname(__FILE__) + '/public'
set :views, File.dirname(__FILE__) + '/views'


# Set up Sinatra helpers
helpers do
  def json_response(data)
    content_type :json
    data.to_json
  end
end

@@success_count = 0

# Set up Sinatra routes
get '/' do
  # Display configured urls and success count as a JSON object
  urls = load_urls
  urls_json = urls.map { |url| { 'url' => url } }
  json_response({ 'urls' => urls_json, 'successes' => @@success_count }.to_json)
end

  


# Handle webhooks
post '/' do
  # Start time
  client_start_time = Time.now
  logger.info("Client started at #{client_start_time}")

  logger.info("Received webhook")
  logger.info("  Payload: #{request.body.read}")
  logger.info("  Inspect: #{request.inspect}")
  
  # Parse webhook payload
  payload = JSON.parse(request.params.to_json)
  logger.info("  Payload parsed: #{payload.inspect}")

  # Forward webhooks to each URL
  urls = load_urls
  Parallel.each urls.uniq, in_threads: 10 do |url|
    @error_count = 0
    @error_uri_and_code = []
    logger.info("  Forwarding to #{url}")
    # Start time
    start_time = Time.now
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.start do
      request = Net::HTTP::Post.new(uri)
      request.body = payload.to_json
      response = http.request(request)
      logger.info("  Response: #{uri} #{response.code} #{response.message} #{response.body} ")
      
      # If an error occurred, remember it
      if response.code != "200"
        @error_count = @error_count + 1
        @error_uri_and_code << [uri, response.code]
      else
        # Increment success count
        @@success_count = @@success_count + 1
      end
    end
    # Deliver time
    deliver_time = Time.now - start_time
    logger.info("  Delivery time: #{deliver_time}")
  end

    # If an error occurred, log it
    if @error_count > 0
        logger.error("  #{@error_count} errors occurred")
        @error_uri_and_code.each do |uri|
            logger.error("    #{uri} #{@error_uri_and_code[0]}")
        end
    end
  logger.info("Done forwarding webhooks")
  logger.info("Client finished at #{Time.now} - #{Time.now - client_start_time}")
  
  # Client end time
  client_end_time = Time.now - client_start_time
  
  # Create hash of urls and their delivery times and success or error
   
  # Respond with number of webhooks forwarded, their urls, any response from the server, and the time it took to forward them
  json_response({"hooks" => urls.length, "errors" => @error_uri_and_code, "urls" => urls, "status" => response.status, "time" => client_end_time})

end

# Asyncronous webhook listener
post '/async' do
  # Start time
  client_start_time = Time.now
  logger.info("Async Send started at #{client_start_time}")

  logger.info("Received webhook")
  logger.info("  Payload: #{request.body.read}")
  logger.info("  Inspect: #{request.inspect}")

  # Route to webhook handler
  Thread.new do
    # Parse webhook payload
    payload = JSON.parse(request.params.to_json)
    logger.info("  Payload parsed: #{payload.inspect}")

    # Forward webhooks to each URL
    urls = load_urls
    Parallel.each urls.uniq, in_threads: 10 do |url|
      @error_count = 0
      @error_uri_and_code = []
      logger.info("  Forwarding to #{url}")
      # Start time
      start_time = Time.now
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.start do
        request = Net::HTTP::Post.new(uri)
        request.body = payload.to_json
        response = http.request(request)
        logger.info("  Response: #{uri} #{response.code} #{response.message} #{response.body} ")
        # If an error occurred, remember it
        if response.code != "200"
          @error_count = @error_count + 1
          @error_uri_and_code << [uri, response.code]
        else
            # Increment success count
            @@success_count = @@success_count + 1
        end
      end
      # Deliver time
      deliver_time = Time.now - start_time
      logger.info("  Delivery time: #{deliver_time}")
    end
    # If an error occurred, log it
    if @error_count > 0
        logger.error("  #{@error_count} errors occurred")
        @error_uri_and_code.each do |uri|
            logger.error("    #{uri} #{@error_uri_and_code[0]}")
        end
    end
    logger.info("Done forwarding webhooks")
    logger.info("Async Send finished at #{Time.now} - #{Time.now - client_start_time}")

 
  end

  # Client end time
  client_end_time = Time.now - client_start_time

  # Respond with number of webhooks forwarded, their urls, any response from the server, and the time it took to forward them
  json_response({"async" => "true", "status" => response.status, "time" => client_end_time})
   
end

