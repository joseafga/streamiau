module Streamiau::Routes::Counter
  extend self

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
    render "src/streamiau/views/counter.ecr"
  end

  # TODO: send settings through websocket
  def broadcast_settings(env)
  end
end
