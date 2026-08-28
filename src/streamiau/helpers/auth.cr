module Streamiau
  extend self

  def require_auth(env, level : User::Role = User::Role::User)
    if env.session.bool?("is_logged")
      username = env.session.string("username")
      session_user = User.get_user_by_username(username)
      return if session_user.role <= level
    end

    raise UnauthorizedError.new "Autenticação necessária ou nível de acesso insuficiente."
  end

  # Check if OTP is expired
  def expired?(expires_at : Int64?) : Bool
    return true if expires_at.nil?

    Time.utc.to_unix > expires_at
  end
end
