# Kemal macro for function
macro haltf(env, status_code = 200, response = "")
  {{ env }}.response.status_code = {{ status_code }}
  {{ env }}.response.print {{ response }}
  {{ env }}.response.close
  return
end

macro check_permission(env)
  begin
    token = {{ env }}.params.query["token"].as(String)
    user = User.get_user_by_username(username)
    user.verify_token(token)
  rescue ex
    haltf({{ env }}, 401, ex.message)
  end

  # 100 everyone, 250 subscriber, 300 regular, 400 VIP, 500 moderator, 1000 super moderator, 1500 broadcaster
  if permission = {{ env }}.params.query["permission"]?.try(&.to_u32)
    sender_level = {{ env }}.params.query["level"]?.try(&.to_u32) || 100 # $(sender.level)

    haltf({{ env }}, 401, "Não autorizado.") if sender_level < permission
  end
end
