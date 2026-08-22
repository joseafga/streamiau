require "uri"
require "crypto/subtle"

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
  post "/login" do |env|
    # email = env.params.body["email"].as(String)
    username = env.params.body["username"].as(String)

    # Same response but creating the session only for real users.
    if User.exists?(username)
      user = User.get_user_by_username(username)
      code = Random::Secure.hex(4)

      env.session.string("username", username)
      env.session.string("otp_code", code)
      env.session.bigint("otp_expires_at", (Time.utc + 3.minutes).to_unix)

      response = Streamiau.send_access_code_email(user.email, username, code)
      unless response.success?
        Log.error { "Email send error #{response.status}: #{response.body}" }
        halt env.status(500).html("Falha ao enviar email.")
      end
    end

    halt env.html("O código de acesso foi enviado para o seu email cadastrado.")
  end

  # Login validation
  # Check if the confirmation code is valid to do login
  # /login/confirm?code=random_string_code
  get "/login/confirm" do |env|
    user_code = env.params.query["code"].as(String)
    session_code = env.session.string?("otp_code")
    expires_at = env.session.bigint?("otp_expires_at")

    if session_code.nil? || Streamiau.expired?(expires_at)
      halt env.status(401).html("Código expirado! <a href='/login'>Tente novamente</a>")
    end

    if session_code && Crypto::Subtle.constant_time_compare(user_code, session_code)
      env.session.bool("is_logged", true)

      if redirect_path = env.params.query["redirect_to"]?.as(String?)
        env.redirect URI.decode(redirect_path)
      else
        env.redirect "/home"
      end
    end

    halt env.status(401).html("Código inválido! <a href='/login'>Tente novamente</a>")
  ensure
    # One Time Password use, if success or not
    env.session.strings.delete("otp_code")
    env.session.bigints.delete("otp_expires_at")
  end

  # Logout process
  get "/logout" do |env|
    env.session.destroy
    env.redirect "/"
  end

  # Profile page (login required)
  get "/profile" do |env|
    Streamiau.require_auth(env, User::Role::User)
    username = env.session.string("username")
    user = User.get_user_by_username(username)

    render "src/streamiau/views/profile.ecr"
  rescue UnauthorizedError
    env.redirect "/login"
  end
end
