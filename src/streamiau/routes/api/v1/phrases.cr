require "fzy"

module Streamiau::Routes::API::V1
  class Phrases < Moongoon::Collection
    collection "phrases"
    reference username, model: Streamiau::User, delete_cascade: true

    private class_getter cache = Cache(String, Phrases).new(expires_in: 24.hours)
    property username : String
    property categories : Hash(String, Category)

    def add(category : String, phrase : String)
      return "Frase em branco." if phrase.blank?

      if id = @_id
        new_phrase = phrase.strip

        categories[category].phrases.push new_phrase
        Phrases.update_by_id(id, {"$push" => {"categories.#{category}.phrases" => new_phrase}})

        return %("#{new_phrase}" - Adicionado com sucesso.)
      end

      "`ObjectId` não encontrado"
    end

    def remove(category : String, phrase : String)
      return "Frase em branco." if phrase.blank?

      if id = @_id
        if deleted = categories[category].phrases.delete(phrase)
          Phrases.update_by_id(id, {"$pull" => {"categories.#{category}.phrases" => phrase}})

          return %("#{deleted}" - Removido com sucesso.)
        end
      end

      %("#{phrase}" - Não encontrado.)
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
      category = env.params.url["category"].as(String)
      args = env.params.query["args"]?.as(String?).try(&.presence)
      touser, cmd, params = parse(args)

      phrases = @@cache.fetch(username) do
        Phrases.find_one!({username: username})
      end

      # Subcommand
      Log.debug { "Subcommand: `#{cmd} (#{cmd.class})` with params `#{params} (#{params.class})`" }
      out = case cmd
            when "add", "+"
              check_permission(env)
              phrases.add(category, params) if params
            when "remove", "rem", "-"
              check_permission(env)
              phrases.remove(category, params) if params
            when "random"
              phrases.categories[category].phrases.sample
            when "find"
              phrases.categories[category].find(params) if params
            when .nil?
              phrases.categories[category].phrases.sample
            else # have args but is not a command
              phrases.categories[category].find([cmd, params].join(" "))
            end

      touser ? "#{touser}, #{out}" : out
    rescue ex : Exception
      # StreamElements only shows 200's messages
      haltf(env, 200, ex.message.try(&.[..128]))
    end

    class Category < Moongoon::Document
      property phrases : Array(String)

      def find(search : String)
        matches = Fzy.search(search, @phrases)
        matches.first?.try &.item || "Nenhuma correspondência encontrada."
      end
    end
  end
end
