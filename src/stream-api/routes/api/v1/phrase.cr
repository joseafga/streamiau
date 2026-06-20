require "fzy"

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
      return if phrase.blank?

      new_phrase = phrase.strip
      all[key].push new_phrase
      Store.write("phrase:#{@username}", all.to_json)

      new_phrase
    end

    def remove(key : String, phrase : String)
      verify_key(key)

      if deleted = all[key].delete(phrase)
        Store.write("phrase:#{@username}", all.to_json)
      end

      deleted
    end

    def find(key : String, search : String)
      verify_key(key)

      matches = Fzy.search(search, all[key])
      matches.first?.try &.item || "No matches found."
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
      username = env.params.url["username"].as(String)
      phrases = new(username)

      # Phrase allow some operations like `add` so token authetication may be required.
      begin
        token = env.params.url["token"].as(String)
        phrases.verify_token(token)
      rescue ex
        haltf(env, 401, ex.message)
      end

      key = env.params.url["key"].as(String)
      query = env.params.query["args"]?.as(String?).try(&.presence)

      # Subcommand
      if query
        args = query.strip.split(' ', 2)

        case args[0]
        when "add", "+"
          if phrase = phrases.add(key, args[1])
            return %("#{phrase}" - Added successfully.)
          else
            return %("#{phrase}" - Error.)
          end
        when "remove", "rem", "-"
          if phrase = phrases.remove(key, args[1])
            return %("#{phrase}" - Successfully removed.)
          else
            return %("#{args[1]}" - Not found.)
          end
        else
          return phrases.find(key, query)
        end
      end

      phrases.all[key].sample # Fallback to random
    end
  end
end
