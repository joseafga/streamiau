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

    def self.parse(input : String?) : {String?, String?, String?}
      return {nil, nil, nil} unless input = input.try(&.strip.presence)

      touser : String? = nil

      if input.starts_with?('@')
        parts = input.split(/\s+/, 2)
        touser = parts[0]
        return {touser, nil, nil} unless input = parts[1]?.try(&.presence)
      end

      parts = input.split(/\s+/, 2)
      {touser, parts[0], parts[1]?}
    end

    # Parse phrases key to interact.
    def self.command(env)
      username = env.params.url["username"].as(String)
      key = env.params.url["key"].as(String)
      args = env.params.query["args"]?.as(String?).try(&.presence)
      phrases = new(username, key)
      touser, cmd, params = parse(args)

      # Subcommand
      Log.debug { "Subcommand: `#{cmd} (#{cmd.class})` with params `#{params} (#{params.class})`" }
      out = case cmd
            when "add", "+"
              check_permission(env)
              phrases.add(params) if params
            when "remove", "rem", "-"
              check_permission(env)
              phrases.remove(params) if params
            when "random"
              phrases.value.sample
            when "find"
              phrases.find(params) if params
            when .nil?
              phrases.value.sample
            else # have args but is not a command
              phrases.find("#{cmd} #{params}")
            end

      touser ? "#{touser}, #{out}" : out
    rescue ex : Exception
      # StreamElements only shows 200's messages
      haltf(env, 200, ex.message.try(&.[..128]))
    end
  end
end
