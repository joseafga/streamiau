module Streamiau::Routes::Counter
  extend self

  def show(env)
    username = env.session.string("username")
    session_user = User.get_by_username_or_guest(username)
    uuid = env.params.url["uuid"].as(String)
    csrf_token = env.session.string("csrf")

    render "src/streamiau/views/counter/show.ecr"
  end

  def list(env)
    username = env.session.string("username")
    session_user = User.get_by_username_or_guest(username)
    counters = API::V1::Counter.find({username: username})
    csrf_token = env.session.string("csrf")

    render "src/streamiau/views/counter/list.ecr"
  end

  def post(env) : String
    username = env.session.string("username")
    counter = API::V1::Counter.new(username: username)
    counter.insert

    responsef env, 201, counter.to_json, "application/json"
  end

  def patch(env)
    if body = env.request.body
      username = env.session.string("username")
      uuid = env.params.url["uuid"].as(String)
      counter = API::V1::Counter.get(username, uuid)
      message = API::V1::Counter::CounterMessage.from_json(body.gets_to_end)
      # Ensure the correct values and not trust on sended one
      metadata = API::V1::Counter::Metadata.new(sender: username, message: message.metadata.try(&.message))

      counter.set(message.value, metadata)

      responsef env, 200, counter.to_json, "application/json"
    end

    haltf env, 400, "Bad Request"
  end

  def delete(env) : Nil
    username = env.session.string("username").as(String)
    uuid = env.params.url["uuid"].as(String)

    API::V1::Counter.get(username, uuid).remove
    responsef env, 204
  end

  # Send settings through websocket
  def broadcast_settings(env)
    if body = env.request.body
      username = env.session.string("username")
      uuid = env.params.url["uuid"].as(String)
      counter = API::V1::Counter.get(username, uuid)
      message = API::V1::Counter::SettingsMessage.from_json(body.gets_to_end)

      counter.clients.broadcast(message.to_json)
      return
    end

    haltf env, 400, "Bad Request"
  end
end
