require "kemal"
require "kemal-session"
require "./stream-api/**"

# TODO: Write documentation for `Stream::Api`
module Stream::Api
  VERSION = "0.2.0"
  GITHUB = "https://github.com/joseafga/stream-api"

  # Kemal configuration
  Kemal.config.powered_by_header = false
  Kemal.config.add_handler Kemal::Session::CSRF.new
  serve_static({"dir_listing" => false, "gzip" => true, "dir_index" => true})

  # Session configuration
  Kemal::Session.config do |config|
    config.cookie_name = "sid"
    config.secret = "my-secret-key-change-this-in-production"
    config.gc_interval = 2.minutes
  end

  Kemal.run
end
