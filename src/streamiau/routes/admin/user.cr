module Streamiau::Routes::Admin::User
  extend self

  # Administrator page to generate sentence tokens.
  # TODO: token management
  def generate_token(env)
    target = env.params.url["target"].as(String)

    user = Streamiau::User.get_user_by_username(target)
    user.tokens_new

    <<-HTML
      <h2>New Token</h2>
      <p>#{target}: #{user.tokens}</p>
      HTML
  end
end
