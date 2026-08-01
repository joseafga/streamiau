require "./routes/**"
require "uri"

module Streamiau
  get "/" do |env|
    render("src/streamiau/views/index.ecr")
  end

  get "/version" do |env|
    halt env.text(<<-TXT)
      Version: #{Streamiau::VERSION}
      Source: #{Streamiau::GITHUB}
      TXT
  end

  root = Kemal::Router.new

  root.namespace "/admin" do
    # Check if user is a Administrator
    before do |env|
      require_auth(env, User::Role::Admin)
    rescue UnauthorizedError
      halt env.status(401).html("Unauthorized")
    end

    get "/user/:target/token" { |env| Routes::Admin::User.generate_token(env) }
  end

  get "/counter" do |env|
    require_auth(env)
    Routes::Counter.list(env)
  rescue UnauthorizedError
    env.redirect "/login?redirect_to=#{URI.encode_path(env.request.resource)}"
  end

  post "/counter/:uuid/settings" do |env|
    require_auth(env)
    Routes::Counter.broadcast_settings(env)
  rescue UnauthorizedError
    halt env.status(401).html("Unauthorized")
  end

  api = Kemal::Router.new

  api.namespace "/" do
    before do |env|
      env.response.content_type = "text/plain; charset=utf-8"
    end

    ws "/counter/:username/:uuid/ws" { |socket, env| Routes::API::V1::Counter.websocket(socket, env) }
    get "/counter/:username/:uuid" { |env| Routes::API::V1::Counter.command(env) }
    get "/phrases/:username/:key" { |env| Routes::API::V1::Phrases.command(env) }
    get "/youtube/:username/videos/last" { |env| Routes::API::V1::Youtube.last_channel_video(env) }
    get "/youtube/:username/shorts/last" { |env| Routes::API::V1::Youtube.last_channel_short(env) }
    get "/steam/:username/:appid/hours" { |env| Routes::API::V1::Steam.command(env) }
  end

  root.mount "/api/v1", api
  mount root
end
