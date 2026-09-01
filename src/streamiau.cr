require "kemal"
require "kemal-session"
require "log"
require "moongoon"
require "lru-cache"
require "./streamiau/types"
require "./streamiau/ext/web_socket"
require "./streamiau/helpers/macros"
require "./streamiau/helpers/cache"
require "./streamiau/helpers/cache_handler"
require "./streamiau/helpers/auth"
require "./streamiau/helpers/email"
require "./streamiau/errors"
require "./streamiau/user"
require "./streamiau/routes"

# TODO: Write documentation for `Streamiau`
module Streamiau
  VERSION    = "0.3.0"
  GITHUB     = "https://github.com/joseafga/streamiau"
  APP_ORIGIN = ENV["APP_ORIGIN"]
  Log        = ::Log.for("streamiau")

  # Kemal configuration
  Kemal.config.powered_by_header = false
  ::Log.setup_from_env
  ::Moongoon.connect ENV["MONGODB_URL"], database_name: ENV["MONGODB_DB"]
  serve_static({"dir_listing" => false, "gzip" => true, "dir_index" => true})

  # Session configuration
  Kemal::Session.config do |config|
    config.cookie_name = "sid"
    config.secret = ENV["SESSION_SECRET"]
    config.timeout = 30.minutes
    config.gc_interval = 5.minutes
  end

  use Kemal::Session::CSRF.new(
    allowed_methods: ["GET", "HEAD", "OPTIONS"],
    allowed_routes: ["/api/v1"],
    error: "Invalid CSRF token",
    per_session: true
  )

  # Setup caches
  use "/api/v1/steam", CacheHandler.new(expires_in: 1.hour)
  use "/api/v1/youtube", CacheHandler.new(expires_in: 1.hour)
  User.warm_up

  Kemal.run
end
