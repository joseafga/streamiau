module Streamiau
  extend self

  def require_auth(env, level : User::Role = User::Role::User)
    if env.session.bool?("is_logged")
      username = env.session.string("username")
      user = User.get_user_by_username(username)
      return if user.role <= level
    end

    raise UnauthorizedError.new "Authentication required or insufficient access level."
  end
end
