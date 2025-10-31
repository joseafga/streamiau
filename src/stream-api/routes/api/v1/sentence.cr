module Stream::Api::Routes::API::V1::Sentence
  extend self

  # TODO: Implement database
  SENTENCES = {
    "john" => [
      "Hello, world!",
      "Welcome to Stream API!",
      "Enjoy your stay!",
    ],
    "doe" => [
      "Hello, world",
      "Welcome to Stream API",
      "Enjoy your stay",
    ],
  }

  def command(env)
    env.response.content_type = "text/plain; charset=utf-8"
    name = env.params.url["name"].as(String)
    query = env.params.query["args"]?.as(String)

    unless query.empty?
      args = query.split(' ', 2)

      case args[0] # Command
      when "add"
        return add(env, name, args[1])
      end
    end

    random(env, name) # Fallback
  end

  def add(env, name : String, sentence : String)
    SENTENCES[name].push(sentence.strip)
    "Success"
  end

  def random(env, name : String)
    SENTENCES[name].sample
  end
end
