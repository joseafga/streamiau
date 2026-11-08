module Streamiau::Routes::Phrases
  extend self

  def list(env)
    username = env.session.string("username")
    session_user = User.get_by_username_or_guest(username)
    phrases = API::V1::Phrases.find_one({username: username})
    csrf_token = env.session.string("csrf")

    render "src/streamiau/views/phrases/list.ecr"
  end

  # Add new phrase POST request
  def post(env)
    if body = env.request.body
      username = env.session.string("username")
      category = env.params.url["category"].as(String)

      if phrases = API::V1::Phrases.find_one({username: username})
        phrases.add(category, body.gets_to_end)

        responsef env, 201, phrases.to_json, "application/json"
      end
    end

    haltf env, 400, "Bad Request"
  end

  # Remove phrase DELETE request
  def delete(env)
    if body = env.request.body
      username = env.session.string("username")
      category = env.params.url["category"].as(String)

      if phrases = API::V1::Phrases.find_one({username: username})
        phrases.remove(category, body.gets_to_end)

        responsef env, 204
      end
    end

    haltf env, 400, "Bad Request"
  end
end
