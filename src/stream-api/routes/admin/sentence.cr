module Stream::Api::Routes::Admin::Sentence
  extend self

  # Administrator page to generate or refresh sentence tokens.
  def refresh_token(env)
    target = env.params.url["target"].as(String)

    tokens = [] of String
    tokens.push Random::Secure.hex(24)

    API::V1::Sentence.sentences(target)["tokens"] = tokens
    Store.write("sentence:#{target}", API::V1::Sentence.sentences(target).to_json)

    <<-HTML
      <h2>New Token</h2>
      <p>#{target}: #{tokens}</p>
      HTML
  end
end
