require "fzy"

module Streamiau::Routes::API::V1
  class Phrases
    private class_getter cache = Cache::MemoryStore(Hash(String, Array(String))).new(expires_in: 24.hours)
    property value : Array(String)

    def initialize(@username : String, @key : String)
      @value = Phrases.all(@username)[@key]
    end

    def add(phrase : String)
      return %("#{phrase}" - Frase em branco.) if phrase.blank?

      new_phrase = phrase.strip
      @value.push new_phrase
      Store.write("phrases:#{@username}", Phrases.all(@username).to_json)

      %("#{new_phrase}" - Adicionado com sucesso.)
    end

    def remove(phrase : String)
      return %("#{phrase}" - Frase em branco.) if phrase.blank?

      if deleted = @value.delete(phrase)
        Store.write("phrases:#{@username}", Phrases.all(@username).to_json)
        return %("#{deleted}" - Removido com sucesso.)
      end

      %("#{phrase}" - Não encontrado.)
    end

    def find(search : String)
      matches = Fzy.search(search, @value)
      matches.first?.try &.item || "Nenhuma correspondência encontrada."
    end

    def self.all(username) : Hash(String, Array(String))
      key = "phrases:#{username}"

      @@cache.fetch(key) do
        Hash(String, Array(String)).from_json(Store.read(key))
      end
    end

    # Parse phrases key to interact.
    def self.command(env)
      username = env.params.url["username"].as(String)
      key = env.params.url["key"].as(String)
      args = env.params.query["args"]?.as(String?).try(&.presence)
      phrases = new(username, key)

      # Subcommand
      if args
        parts = args.strip.split(/\s+/, 2)

        # Token authetication required for operations
        begin
          token = env.params.query["token"].as(String)
          user = User.get_user_by_username(username)
          user.verify_token(token)
        rescue ex
          haltf(env, 401, ex.message)
        end

        case parts[0]
        when "add", "+"
          check_permission(env)
          return phrases.add(parts[1]) if parts[1]?.try &.presence
        when "remove", "rem", "-"
          check_permission(env)
          return phrases.remove(parts[1]) if parts[1]?.try &.presence
        when "random"
          return phrases.value.sample
        else
          return phrases.find(args)
        end
      end

      phrases.value.sample # Fallback to random
    end
  end
end
