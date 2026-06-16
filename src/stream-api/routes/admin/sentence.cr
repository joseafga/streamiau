module Stream::Api::Routes::Admin::Sentence
  extend self

  # Administrator page to generate or refresh sentence tokens.
  # Sentence allow some operations like `add` so token authetication is required.
  def refresh_token(env)
    logged = env.session.bool?("is_logged")

    if logged
      username = env.session.string?("username")
      target = env.params.url["target"].as(String)

      if username && (user = User.get(username))
        if user.role == User::Role::Admin
          tokens = [] of String
          tokens.push Random::Secure.hex(24)

          API::V1::Sentence.sentences(target)["tokens"] = tokens
          Store.write("sentence:#{target}", API::V1::Sentence.sentences(target).to_json)
        end
      end

      <<-HTML
        <h2>New Token</h2>
        <p>#{target}: #{tokens}</p>
        HTML
    else
      env.redirect "/login"
    end
  end
end
