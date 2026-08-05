module Streamiau::Routes::Counter
  extend self

  def get(env)
    username = env.session.string("username")
    initials = username[0..1].upcase
    uuid = env.params.url["uuid"].as(String)

    # API::V1::Counter.create(username, 0)
    csrf_token = env.session.string("csrf")

    render "src/streamiau/views/counter/get.ecr"
  end

  def list(env)
    username = env.session.string("username")
    initials = username[0..1].upcase
    counters = [] of NamedTuple(uuid: String, value: Int32)

    key_prefix = "counter:#{username}"
    keys = Store.keys(prefix: key_prefix)

    if keys.size > 0
      result = Store.read_bulk(keys.map(&.name))

      result["values"].as_h.each do |key, value|
        counters << {
          uuid:  key[(key_prefix.size + 1)..],
          value: value.as_i,
        }
      end
    end

    # API::V1::Counter.create(username, 0)
    csrf_token = env.session.string("csrf")

    render "src/streamiau/views/counter/list.ecr"
  end

  # Send settings through websocket
  def broadcast_settings(env)
    username = env.session.string("username")
    uuid = env.params.url["uuid"].as(String)
    counter = API::V1::Counter.instance(username, uuid)

    message = API::V1::Counter::SettingsMessage.new(
      env.params.body["font-family"].as(String),
      env.params.body["prefix"].as(String),
      env.params.body["font-color"].as(String),
      env.params.body["font-size-prefix"].to_i32,
      env.params.body["font-size-counter"].to_i32
    )

    counter.broadcast(message)

    "Success"
  end
end
