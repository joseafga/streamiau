module Stream::Api::Routes::API::V1::Sentence
  extend self

  class_getter cache = Cache::MemoryStore(Hash(String, Array(String))).new(expires_in: 30.days)

  def sentences : Hash(String, Array(String))
    @@cache.fetch("sentence:all") do
      Hash(String, Array(String)).from_json(Store.read("sentence:all"))
    end
  end

  def command(env)
    env.response.content_type = "text/plain; charset=utf-8"
    name = env.params.url["name"]
    query = env.params.query["args"]?.to_s

    unless query.empty?
      args = query.split(' ', 2)

      case args[0] # Command
      when "add"
        return add(name, args[1])
      end
    end

    random(name) # Fallback
  end

  def add(name : String, sentence : String)
    new_sentence = sentence.strip

    sentences[name].push(new_sentence)
    Store.write("sentence:all", sentences.to_json)

    "#{new_sentence} - Added successfully."
  end

  def random(name : String)
    sentences[name].sample
  end
end
