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

    def add(key : String, phrase : String)
      return if phrase.blank?

      new_phrase = phrase.strip
      all[key].push new_phrase
      Store.write("phrase:#{@username}", all.to_json)

      new_phrase
    end

    def remove(key : String, phrase : String)
      if deleted = all[key].delete(phrase)
        Store.write("phrase:#{@username}", all.to_json)
      end

      deleted
    end

    def find(key : String, search : String)
      matches = Fzy.search(search, all[key])
      matches.first?.try &.item || "Nenhuma correspondência encontrada."
    end

    # Parse phrase key to interact.
    def self.command(env)
      username = env.params.url["username"].as(String)
      user = User.get(username)

      # Phrase allow some operations like `add` so token authetication may be required.
      begin
        token = env.params.url["token"].as(String)
        user.verify_token(token)
      rescue ex
        haltf(env, 401, ex.message)
      end

      key = env.params.url["key"].as(String)
      query = env.params.query["args"]?.as(String?).try(&.presence)
      phrases = new(username)

      # Subcommand
      if query
        args = query.strip.split(' ', 2)

        case args[0]
        when "add", "+"
          if phrase = phrases.add(key, args[1])
            return %("#{phrase}" - Adicionado com sucesso.)
          else
            return %("#{phrase}" - Erro.)
          end
        when "remove", "rem", "-"
          if phrase = phrases.remove(key, args[1])
            return %("#{phrase}" - Removido com sucesso.)
          else
            return %("#{args[1]}" - Não encontrado.)
          end
        else
          return phrases.find(key, query)
        end
      end

      phrases.all[key].sample # Fallback to random
    end
  end
end
