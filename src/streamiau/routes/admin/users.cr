require "html"

module Streamiau::Routes::Admin::Users
  extend self

  def list(env)
    username = env.session.string("username")
    session_user = User.get_by_username_or_guest(username)
    csrf_token = env.session.string("csrf")

    users = User.find

    render "src/streamiau/views/admin/user/list.ecr"
  end

  def edit(env)
    if body = env.request.body
      username = env.params.url["username"].as(String)
      user = User.get_by_username(username)

      updated_user = User.from_json(body.gets_to_end)
      # assert it will update only some fields
      user.update_fields({
        realname:  updated_user.realname,
        email:     updated_user.email,
        role:      updated_user.role,
        steamid:   updated_user.steamid,
        youtubeid: updated_user.youtubeid,
      })

      return
    end

    haltf env, 400, "Bad Request"
  end

  def generate_token(env)
    if body = env.request.body
      username = env.params.url["username"].as(String)
      allowed = Array(Int32).from_json(body.gets_to_end)

      unless allowed.empty?
        user = User.get_by_username(username)
        token = User::Token.new(allow: allowed, value: Random::Secure.hex(32))

        user.tokens << token
        user.update

        return token.to_json
      end
    end

    haltf env, 400, "Bad Request"
  end

  def revoke_token(env)
    if body = env.request.body
      username = env.params.url["username"].as(String)
      user = User.get_by_username(username)
      token_value = body.gets_to_end

      user.tokens.reject! do |token|
        token.value == token_value
      end

      user.update
      return
    end

    haltf env, 400, "Bad Request"
  end
end
