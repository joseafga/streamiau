require "uri"

module Streamiau::Routes
  # Login page
  get "/login" do |env|
    logged = env.session.bool?("is_logged")

    if logged
      env.redirect "/"
    else
      csrf_token = env.session.string("csrf")
      redirect_to = env.params.query["redirect_to"]?.as(String?)

      render "src/streamiau/views/login.ecr"
    end
  end

  # Login Request
  # TODO: Will generate a confirmation code and send it to the user's email
  post "/login" do |env|
    # email = env.params.body["email"].as(String)
    username = env.params.body["username"].as(String)

    # Same response but creating the session only for real users.
    if User.exists?(username)
      user = User.get_user_by_username(username)
      code = Random::Secure.hex(16)
      env.session.string("username", username)
      env.session.string("code", code)
      confirm_url = "#{APP_ORIGIN}/login/confirm?username=#{username}&code=#{code}"

      if redirect_to_encoded = env.params.body["redirect_to"]?.as(String?)
        confirm_url += "&redirect_to=#{redirect_to_encoded}"
      end

      if Kemal.config.env == "development" # DEV only
        env.redirect confirm_url
        next
      end

      response = Streamiau.send_access_code_email(user.email, confirm_url)
      unless response.success?
        Log.error { "Email send error #{response.status}: #{response.body}" }
        halt env, 500, "Falha ao enviar email."
      end
    end

    "Um link de acesso foi enviado para o seu email cadastrado."
  end

  # Login validation
  # Check if the confirmation code is valid to do login
  # /login/confirm?username=you&code=random_string_code
  get "/login/confirm" do |env|
    # email = env.params.query["email"].as(String)
    username = env.params.query["username"].as(String)
    code = env.params.query["code"].as(String)

    if env.session.string?("username") == username && env.session.string?("code") == code
      env.session.bool("is_logged", true)
      env.session.string("username", username)

      if redirect_path = env.params.query["redirect_to"]?.as(String?)
        env.redirect URI.decode(redirect_path)
      else
        env.redirect "/"
      end
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
      username = env.session.string?("username")

      if username && (user = User.get_user_by_username(username))
        name = user.username
        email = user.email
        role = user.role
      end

      <<-HTML
        <h2>Profile Page</h2>
        <p>Username: #{name}</p>
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
end
