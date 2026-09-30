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
    counters = [] of NamedTuple(uuid: String, value: Int32, date: String?, sender: String?, message: String?)
    csrf_token = env.session.string("csrf")

    counters = API::V1::Counter.find({username: username})

    render "src/streamiau/views/counter/list.ecr"
  end

  # Send settings through websocket
  def broadcast_settings(env)
    if body = env.request.body
      username = env.session.string("username")
      uuid = env.params.url["uuid"].as(String)
      counter = API::V1::Counter.get(username, uuid)
      message = API::V1::Counter::SettingsMessage.from_json(body.gets_to_end)

      counter.broadcast(message)
      return
    end

    haltf env, 400, "Bad Request"
  end
end
