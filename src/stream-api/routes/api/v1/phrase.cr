require "levenshtein"

module Stream::Api::Routes::API::V1
  class Phrase
    private class_getter cache = Cache::MemoryStore(Hash(String, Array(String))).new(expires_in: 24.hours)

    def initialize(@username : String)
    end

    def all : Hash(String, Array(String))
      key = "phrase:#{@username}"

      @@cache.fetch(key) do
        Hash(String, Array(String)).from_json(Store.read(key))
      end
    end

    def tokens
      all["_tokens"]
    end

    def add(key : String, phrase : String)
      verify_key(key)
      new_phrase = phrase.strip

      all[key].push new_phrase
      Store.write("phrase:#{@username}", all.to_json)

      new_phrase
    end

    def find(key : String, search : String)
      verify_key(key)
      all[key].max_by? { |phrase| similarity(search, phrase) }
    end

    protected def similarity(search : String, target : String) : Float64
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

    def tokens_clear
      all["_tokens"] = [] of String
      Store.write("phrase:#{@username}", all.to_json)
    end

    def tokens_revoke(token : String)
      all["_tokens"].delete(token)
      Store.write("phrase:#{@username}", all.to_json)
    end

    def tokens_increment
      all["_tokens"].push Random::Secure.hex(24)
      Store.write("phrase:#{@username}", all.to_json)
    end

    def verify_token(token)
      raise "Invalid phrase token." unless tokens.includes?(token)
    end

    # Key starting with "_" are private and can't be exposed
    private def verify_key(key)
      raise "Invalid phrase key." if key.starts_with?('_')
    end

    # Parse phrase key to interact.
    def self.command(env)
      env.response.headers["Cache-Control"] = "no-cache"
      username = env.params.url["username"].as(String)
      token = env.params.url["token"].as(String)
      phrases = new(username)

      # Phrase allow some operations like `add` so token authetication may be required.
      begin
        phrases.verify_token(token)
      rescue ex
        env.response.status_code = 401
        env.response.print ex.message
        env.response.close
        return
      end

      key = env.params.url["key"].as(String)
      query = env.params.query["args"]?.as(String?)

      # Subcommand
      if query && query.presence
        args = query.split(' ', 2)

        case args[0]
        when "add"
          phrase = phrases.add(key, args[1])
          return "#{phrase} - Added successfully."
        else
          return phrases.find(key, query)
        end
      end

      phrases.all[key].sample # Fallback to random
    end
  end
end
