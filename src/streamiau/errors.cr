class UnauthorizedError < Exception
end

error 404 do |env|
  env.response.content_type = "text/plain"
  "404 - O gato comeu!"
end

error 500 do |env, exception|
  env.response.content_type = "text/plain"
  "500 - Internal Server Error: #{exception.message}"
end
