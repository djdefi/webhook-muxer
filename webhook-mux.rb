# Webhook multiplexer
# Listens for webhooks from a GitHub repository and forwards it to multiple configurable endpoints

require 'optparse'
require 'sinatra'
require 'yaml'
require 'json'
require 'uri'
require 'net/http'
require 'logger'
require 'parallel'

# Check for urls.txt and exit if not found
abort("Error: urls.txt not found") unless File.exist?('urls.txt')

# Initialize options hash
options = { port: ENV['PORT'] || 4567 }

# Load list of URLs from urls.txt
def load_urls
  File.readlines('urls.txt').map(&:strip)
rescue StandardError => e
  STDERR.puts "Error reading urls.txt: #{e}"
  []
end

# Set up logger
def setup_logger
  logger = Logger.new(STDOUT)
  logger.level = Logger::INFO
  logger.datetime_format = "%Y-%m-%d %H:%M:%S"
  logger.formatter = proc do |severity, datetime, progname, msg|
    "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} - #{severity} - #{msg}\n"
  end
  logger
end

logger = setup_logger

# Set up Sinatra
set :logger, logger
set :port, options[:port].to_i
set :public_folder, File.dirname(__FILE__) + '/public'
set :views, File.dirname(__FILE__) + '/views'

helpers do
  def json_response(data)
    content_type :json
    data.to_json
  end
end

# Global variable for success count
$success_count = 0

# Forward webhook to given URL
def forward_webhook(url, payload, logger)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = payload.to_json
    response = http.request(request)
    logger.info("Response: #{uri} #{response.code} #{response.message} #{response.body}")
    response
  end
rescue StandardError => e
  logger.error("Error forwarding to #{url}: #{e}")
  nil
end

# Handle webhook forwarding
def handle_webhook(request_body, logger)
  payload = JSON.parse(request_body)
  urls = load_urls
  errors = []

  Parallel.each(urls.uniq, in_threads: 10) do |url|
    response = forward_webhook(url, payload, logger)
    if response.nil? || response.code != '200'
      errors << { url: url, code: response&.code }
    else
      $success_count += 1
    end
  end

  errors
end

# Routes
get '/' do
  urls = load_urls
  urls_json = urls.map { |url| { 'url' => url } }
  json_response({ 'urls' => urls_json, 'successes' => $success_count })
end

post '/' do
  errors = handle_webhook(request.body.read, logger)
  json_response({ 'hooks' => load_urls.length, 'errors' => errors, 'urls' => load_urls, 'status' => 'completed' })
end

post '/async' do
  Thread.new do
    errors = handle_webhook(request.body.read, logger)
    logger.info("Async processing completed with errors: #{errors}")
  end
  json_response({ 'async' => 'true', 'status' => 'processing' })
end

post '/echo' do
  request_body = request.body.read
  logger.info("Echo: #{request_body}")
  json_response({ 'echo' => request_body })
end

# Start the Sinatra application
run! if __FILE__ == $PROGRAM_NAME

