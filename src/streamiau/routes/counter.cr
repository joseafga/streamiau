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
