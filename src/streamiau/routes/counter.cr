module Streamiau::Routes::Counter
  extend self

  def settings(env)
    username = env.session.string("username")

    render "src/streamiau/views/counter.ecr"
  end

  # TODO: send settings through websocket
  def broadcast_settings(env)
  end
end
