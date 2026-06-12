require "kemal"
require "kemal-session"
require "log"
require "kv"
require "cache"
require "./stream-api/**"

# TODO: Write documentation for `Stream::Api`
module Stream::Api
  VERSION = "0.2.0"
  GITHUB = "https://github.com/joseafga/stream-api"
  STEAM_API_KEY = ENV["STEAM_API_KEY"]
  Log = ::Log.for("stream-api")

  # Kemal configuration
  Kemal.config.powered_by_header = false
  Kemal.config.add_handler Kemal::Session::CSRF.new
  serve_static({"dir_listing" => false, "gzip" => true, "dir_index" => true})

  # Session configuration
  Kemal::Session.config do |config|
    config.cookie_name = "sid"
    config.secret = "my-secret-key-change-this-in-production"
    config.gc_interval = 5.minutes
  end

  # TODO: check if namespace exists and create if not
  Store = KV::Client.new(ENV["CLOUDFLARE_ACCOUNT_ID"], ENV["CLOUDFLARE_API_TOKEN"]).get "147c5808c4414e7ca38cfbb06d1fc0ca"

  Kemal.run
end
