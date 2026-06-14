require "levenshtein"

module Stream::Api::Routes::API::V1::Sentence
  extend self

  class_getter cache = Cache::MemoryStore(Hash(String, Array(String))).new(expires_in: 30.days)

  def sentences(username : String) : Hash(String, Array(String))
    key = "sentence:#{username}"

    @@cache.fetch(key) do
      Hash(String, Array(String)).from_json(Store.read(key))
    end
  end

  def command(env)
    env.response.content_type = "text/plain; charset=utf-8"
    username = env.params.url["username"].as(String)
    token = env.params.url["token"].as(String)
    name = env.params.url["name"].as(String)
    query = env.params.query["args"]?.as(String?)

    raise "Invalid sentence token." unless sentences(username)["tokens"].includes?(token)

    # Subcommand
    if query && query.presence
      args = query.split(' ', 2)

      case args[0]
      when "add"
        return add(username, name, args[1])
      else
        return find(username, name, query)
      end
    end

    random(username, name) # Fallback
  end

  def add(username : String, name : String, sentence : String)
    new_sentence = sentence.strip

    sentences(username)[name].push(new_sentence)
    Store.write("sentence:#{username}", sentences(username).to_json)

    "#{new_sentence} - Added successfully."
  end

  def random(username : String, name : String)
    sentences(username)[name].sample
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

  def find(username : String, name : String, search : String)
    sentences(username)[name].max_by? { |sentence| similarity(search, sentence) }
  end

  # Administrator page to generate or refresh sentence tokens.
  # Sentence allow some operations like `add` so token authetication is required.
  def refresh_token(env)
    logged = env.session.bool?("is_logged")

    if logged
      username = env.session.string?("username")
      target = env.params.url["username"].as(String)

      if username && (user = User.get(username))
        if user.role == User::Role::Admin
          tokens = [] of String
          tokens.push Random::Secure.hex(24)

          sentences(target)["tokens"] = tokens
          Store.write("sentence:#{target}", sentences(target).to_json)
        end
      end

      <<-HTML
        <h2>New Token</h2>
        <p>#{target}: #{tokens}</p>
        HTML
    else
      env.redirect "/login"
    end
  end
end
