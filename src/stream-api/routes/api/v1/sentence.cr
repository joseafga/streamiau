require "levenshtein"

module Stream::Api::Routes::API::V1::Sentence
  extend self

  private class_getter cache = Cache::MemoryStore(Hash(String, Array(String))).new(expires_in: 30.days)

  def sentences(username : String) : Hash(String, Array(String))
    key = "sentence:#{username}"

    @@cache.fetch(key) do
      Hash(String, Array(String)).from_json(Store.read(key))
    end
  end

  # Sentence allow some operations like `add` so token authetication may be required.
  private def check_token(env)
    username = env.params.url["username"].as(String)
    token = env.params.url["token"].as(String)

    raise "Invalid sentence token." unless sentences(username)["tokens"].includes?(token)
    nil
  end

  # Parse sentence key to interact.
  def command(env)
    username = env.params.url["username"].as(String)
    key = env.params.url["key"].as(String)
    query = env.params.query["args"]?.as(String?)
    check_token(env)

    # Subcommand
    if query && query.presence
      args = query.split(' ', 2)

      case args[0]
      when "add"
        return add(username, key, args[1])
      else
        return find(username, key, query)
      end
    end

    random(username, key) # Fallback
  rescue ex
    env.response.status_code = 401
    env.response.print ex.message
    env.response.close
  end

  def add(username : String, key : String, sentence : String)
    new_sentence = sentence.strip

    sentences(username)[key].push(new_sentence)
    Store.write("sentence:#{username}", sentences(username).to_json)

    "#{new_sentence} - Added successfully."
  end

  def random(username : String, key : String)
    sentences(username)[key].sample
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

  def find(username : String, key : String, search : String)
    sentences(username)[key].max_by? { |sentence| similarity(search, sentence) }
  end
end
