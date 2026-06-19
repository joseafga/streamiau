module Stream::Api::Routes::Admin::Phrase
  extend self

  # Administrator page to generate sentence tokens.
  # TODO: token management
  def generate_token(env)
    target = env.params.url["target"].as(String)

    phrases = API::V1::Phrase.new(target)
    phrases.tokens_increment

    <<-HTML
      <h2>New Token</h2>
      <p>#{target}: #{phrases.tokens}</p>
      HTML
  end
end
