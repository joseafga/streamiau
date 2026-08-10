module Streamiau
  extend self

  RESEND_API_KEY = ENV["RESEND_API_KEY"]
  SENDER_EMAIL = ENV["SENDER_EMAIL"]

  def send_access_code_email(to : String, username : String, code : String)
    headers = HTTP::Headers{"Authorization" => "Bearer #{RESEND_API_KEY}"}
    body = {
        from: SENDER_EMAIL,
        to: to,
        template: {
          id: "streamiau_access_code",
          variables: {
            USERNAME: username,
            CODE: code
          }
        }
    }

    HTTP::Client.post("https://api.resend.com/emails", headers: headers, body: body.to_json)
  end
end
