# Kemal macro for function
macro haltf(env, status_code = 200, response = "")
  {{ env }}.response.status_code = {{ status_code }}
  {{ env }}.response.print {{ response }}
  {{ env }}.response.close
  return
end
