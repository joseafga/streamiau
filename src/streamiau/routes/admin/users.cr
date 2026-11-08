require "html"

module Streamiau::Routes::Admin::Users
  extend self

  def list(env)
    username = env.session.string("username")
    session_user = User.get_by_username_or_guest(username)
    csrf_token = env.session.string("csrf")

    users = User.find

    render "src/streamiau/views/admin/users/list.ecr"
  end

  def post(env)
    if body = env.request.body
      username = env.params.url["username"].as(String)
      unless User.exists?(username)
        new_user = User.from_json(body.gets_to_end)
        new_user.insert

        responsef env, 201, new_user.to_json, "application/json"
      end
    end

    haltf env, 400, "Bad Request"
  end

  def patch(env)
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

      responsef env, 200, user.to_json, "application/json"
    end

    haltf env, 400, "Bad Request"
  end

  def delete(env) : Nil
    username = env.params.url["username"].as(String)

    User.get_by_username(username).remove
    responsef env, 204
  end

  def generate_token(env)
    if body = env.request.body
      username = env.params.url["username"].as(String)
      allowed = Array(Int32).from_json(body.gets_to_end).uniq

      unless allowed.empty?
        user = User.get_by_username(username)
        token = User::Token.new(allow: allowed, value: Random::Secure.hex(32))

        user.tokens << token
        user.update

        responsef env, 201, token.to_json, "application/json"
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
      responsef env, 204
    end

    haltf env, 400, "Bad Request"
  end
end
