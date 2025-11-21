# Using [invidious](https://github.com/iv-org/invidious) code for flatting routes
{% for http_method in {"get", "post", "delete", "options", "patch", "put"} %}

  macro {{http_method.id}}(path, controller, method = :handle)
    unless Kemal::Utils.path_starts_with_slash?(\{{path}})
      raise Kemal::Exceptions::InvalidPathStartException.new({{http_method}}, \{{path}})
    end

    Kemal::RouteHandler::INSTANCE.add_route({{http_method.upcase}}, \{{path}}) do |env|
      \{{ controller }}.\{{ method.id }}(env)
    end
  end
{% end %}

get "/" do |env|
  env.response.content_type = "text/plain; charset=utf-8"

  "Stream API!"
end

get "/version" do |env|
  env.response.content_type = "text/plain; charset=utf-8"

  <<-TXT
    Version: #{Stream::Api::VERSION}
    Source: #{Stream::Api::GITHUB}
    TXT
end

# Login page
get "/login" do |env|
  csrf_token = env.session.string("csrf")

  <<-HTML
    <h2>Login</h2>
    <form method="post" action="/login">
      <input type="hidden" name="authenticity_token" value="#{csrf_token}">
      <input type="email" name="email" placeholder="Email" required>
      <button type="submit">Send</button>
    </form>
    <a href="/">Home</a>
    HTML
end

# Login Request
# Will generate a confirmation code and send it to the user's email
post "/login" do |env|
  email = env.params.body["email"].as(String)

  code = Random::Secure.hex(16)
  env.session.string("email", email)
  env.session.string("code", code)

  "Check your email! <a href='/login/confirm?email=#{email}&code=#{code}'>[Confirm]</a>"
end

# Login validation
# Check if the confirmation code is valid to do login
# /login/confirm?email=user@email.com&code=random_string_code
get "/login/confirm" do |env|
  email = env.params.query["email"].as(String)
  code = env.params.query["code"].as(String)

  if env.session.string?("email") == email && env.session.string?("code") == code
    env.session.bool("is_logged", true)
    env.session.string("role", "admin")
    env.redirect "/"
  else
    "Invalid! <a href='/login'>Try again</a>"
  end
end

# Logout process
get "/logout" do |env|
  env.session.destroy
  env.redirect "/"
end

# Profile page (login required)
get "/profile" do |env|
  logged = env.session.bool?("is_logged")

  if logged
    email = env.session.string?("email") || ""
    role = env.session.string?("role") || "user"

    <<-HTML
      <h2>Profile Page</h2>
      <p>Email: #{email}</p>
      <p>Role: #{role}</p>
      <p>Session ID: #{env.session.id}</p>
      <a href="/">Home</a>
      HTML
  else
    env.redirect "/login"
  end
end

# Display session information as JSON
get "/session/info" do |env|
  env.response.content_type = "application/json"

  {
    session_id:  env.session.id,
    visit_count: env.session.int?("visit_count"),
    email:       env.session.string?("email"),
  }.to_json
end

# API routes
get "/api/v1/sentence/:name", Stream::Api::Routes::API::V1::Sentence, :command
get "/api/v1/steam/:steamid/:appid/hours", Stream::Api::Routes::API::V1::Sentence, :command
get "/api/v1/youtube/:channel/video", Stream::Api::Routes::API::V1::Sentence, :command
get "/api/v1/youtube/:channel/short", Stream::Api::Routes::API::V1::Sentence, :command
get "/api/v1/counter/:key/ws", Stream::Api::Routes::API::V1::Sentence, :command
get "/api/v1/counter/:key/:command:", Stream::Api::Routes::API::V1::Sentence, :command
