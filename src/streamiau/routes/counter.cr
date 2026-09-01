module Streamiau::Routes::Counter
  extend self

  def show(env)
    username = env.session.string("username")
    session_user = User.get_user_by_username(username)
    uuid = env.params.url["uuid"].as(String)
    csrf_token = env.session.string("csrf")

    render "src/streamiau/views/counter/show.ecr"
  end

  def list(env)
    username = env.session.string("username")
    session_user = User.get_user_by_username(username)
    counters = [] of NamedTuple(uuid: String, value: Int32, date: String?, sender: String?, message: String?)
    csrf_token = env.session.string("csrf")

    counters = API::V1::Counter.find({username: username})

    render "src/streamiau/views/counter/list.ecr"
  end

  # Send settings through websocket
  def broadcast_settings(env)
    username = env.session.string("username")
    uuid = env.params.url["uuid"].as(String)
    counter = API::V1::Counter.get(username, uuid)

    # possible settings
    font_family = env.params.body["font-family"]?
    prefix = env.params.body["prefix"]?
    font_color = env.params.body["font-color"]?
    font_size_prefix = env.params.body["font-size-prefix"]?
    font_size_counter = env.params.body["font-size-counter"]?

    message = API::V1::Counter::SettingsMessage.new
    message.font_family = font_family.as(String) if font_family
    message.prefix = prefix.as(String) if prefix
    message.font_color = font_color.as(String) if font_color
    message.font_size_prefix = font_size_prefix.to_i32 if font_size_prefix
    message.font_size_counter = font_size_counter.to_i32 if font_size_counter

    counter.broadcast(message)

    "Success"
  end
end
