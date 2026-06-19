require "kemal"
require "kemal-session"
require "log"
require "kv"
require "cache"
require "./stream-api/helpers/macros"
require "./stream-api/helpers/cache_handler"
require "./stream-api/user"
require "./stream-api/routes"

# TODO: Write documentation for `Stream::Api`
module Stream::Api
  VERSION       = "0.2.0"
  GITHUB        = "https://github.com/joseafga/stream-api"
  STEAM_API_KEY = ENV["STEAM_API_KEY"]
  Log           = ::Log.for("stream-api")

  # Kemal configuration
  Kemal.config.powered_by_header = false
  ::Log.setup_from_env
  Store = KV::Client.new(ENV["CF_ACCOUNT_ID"], ENV["CF_API_TOKEN"]).get ENV["KV_NAMESPACE_ID"]
  serve_static({"dir_listing" => false, "gzip" => true, "dir_index" => true})

  # Session configuration
  Kemal::Session.config do |config|
    config.cookie_name = "sid"
    config.secret = ENV["SESSION_SECRET"]
    config.gc_interval = 5.minutes
  end

  use Kemal::Session::CSRF.new
  use "/api/v1/steam", CacheHandler.new(expires_in: 1.hour)
  use "/api/v1/youtube", CacheHandler.new(expires_in: 1.hour)

  Kemal.run
end
