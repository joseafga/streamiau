require "./routes/**"

module Stream::Api
  root = Kemal::Router.new

  root.namespace "/admin" do
    # Check if user is a Administrator
    before do |env|
      logged = env.session.bool?("is_logged")
      is_admin = false

      if logged
        user = User.get env.session.string("username")
        is_admin = true if user.role == User::Role::Admin
      end

      halt env.status(401).html("<h1>Unauthorized</h1>") unless is_admin
    end

    get "/sentence/refresh_token/:target" { |env| Routes::Admin::Sentence.refresh_token(env) }
  end

  api = Kemal::Router.new

  api.namespace "/" do
    before do |env|
      env.response.content_type = "text/plain; charset=utf-8"
    end

    get "/counter/:username/:key/ws" { |env| Routes::API::V1::Sentence.command(env) }
    get "/counter/:username/:key/:command" { |env| Routes::API::V1::Sentence.command(env) }
    get "/sentence/:username/:token/:key" { |env| Routes::API::V1::Sentence.command(env) }
    get "/youtube/:username/videos/last" { |env| Routes::API::V1::Youtube.last_channel_video(env) }
    get "/youtube/:username/shorts/last" { |env| Routes::API::V1::Youtube.last_channel_short(env) }
    get "/steam/:username/:appid/hours" { |env| Routes::API::V1::Steam.command(env) }
  end

  root.mount "/api/v1", api
  mount root
end
