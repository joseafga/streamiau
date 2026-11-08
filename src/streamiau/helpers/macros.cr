# Kemal macro for function
macro haltf(env, status_code = 200, response = "")
  {{ env }}.response.status_code = {{ status_code }}
  {{ env }}.response.print {{ response }}
  {{ env }}.response.close
  return
end

# HTTP response simplification for routes
macro responsef(env, status_code = 200, response = nil, content_type = "text/plain")
  {{ env }}.response.content_type = {{ content_type }}
  {{ env }}.response.status_code = {{ status_code }}
  return {{ response }}
end

macro check_permission(env)
  token = {{ env }}.params.query["token"].as(String)
  user = User.get_by_username(username)
  user.token_verify(Streamiau::User::Token::Type::{{ @type.name.split("::").last.id }}, token) # use Class name as Token type

  # 100 everyone, 250 subscriber, 300 regular, 400 VIP, 500 moderator, 1000 super moderator, 1500 broadcaster
  if permission = {{ env }}.params.query["permission"]?.try(&.to_u32)
    sender_level = {{ env }}.params.query["level"]?.try(&.to_u32) || 100 # $(sender.level)

    raise UnauthorizedError.new "Não autorizado." if sender_level < permission
  end
end
