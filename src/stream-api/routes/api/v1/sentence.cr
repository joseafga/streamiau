require "levenshtein"

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
    name = env.params.url["name"].as(String)
    query = env.params.query["args"]?.as(String?)

    if query && query.presence
      args = query.split(' ', 2)

      case args[0] # Command
      when "add"
        return add(name, args[1])
      else
        return find(name, query)
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

  def similarity(search : String, target : String) : Float64
    search = search.downcase.split(" ").to_set
    target = target.downcase.split(" ").to_set

    # intersection = search & target
    intersection = 0.0

    search.each do |sword|
      current_intersection = 0.0

      target.each do |tword|
        # Inverting the distance and considers a tolerance of up to 4 (5 or more == 0)
        distance = (5.0 - Levenshtein.distance(sword, tword)) / 5.0

        if distance == 1.0 # exactly match
          current_intersection = distance
          break
        elsif distance > 0.0
          current_intersection = distance if distance > current_intersection
        end
      end

      intersection += current_intersection
    end

    # Dice coefficient = 2 * |A ∩ B| / (|A| + |B|)
    (2.0 * intersection) / (search.size + target.size)
  end

  def find(name : String, search : String)
    sentences[name].max_by? { |sentence| similarity(search, sentence) }
  end
end
