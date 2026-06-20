# module Stream::Api::Routes::API::V1
#   class Counter
#     private class_getter cache = Cache::MemoryStore(Hash(String, Int32)).new(expires_in: 24.hours)

#     def self.command(env)
#       username = env.params.url["username"].as(String)
#       phrases = new(username)

#       # Phrase allow some operations like `add` so token authetication may be required.
#       begin
#         token = env.params.url["token"].as(String)
#         phrases.verify_token(token)
#       rescue ex
#         haltf(env, 401, ex.message)
#       end

#       key = env.params.url["key"].as(String)
#       query = env.params.query["args"]?.as(String?).try(&.presence)

#       # Subcommand
#       if query
#         args = query.strip.split(' ', 2)

#         case args[0]
#         when "add", "+"
#           if phrase = phrases.add(key, args[1])
#             return %("#{phrase}" - Adicionado com sucesso.)
#           else
#             return %("#{phrase}" - Erro.)
#           end
#         when "remove", "rem", "-"
#           if phrase = phrases.remove(key, args[1])
#             return %("#{phrase}" - Removido com sucesso.)
#           else
#             return %("#{args[1]}" - Não encontrado.)
#           end
#         else
#           return phrases.find(key, query)
#         end
#       end
#   end
# end
