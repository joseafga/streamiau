require "./spec_helper"
require "spec-kemal/session"

describe Streamiau do
  it "Get Steam owned games" do
    games = Streamiau::Routes::API::V1::Steam.owned_games("76561199118689987", [381210_u32])
    games.games.try &.first.appid.should eq 381210_u32
  end

  it "Render Steam hours played by steamid" do
    get "/api/v1/steam/76561199118689987/381210/hours"
    response.body.to_i.should be > 0
  end

  it "Render Steam hours played by username" do
    get "/api/v1/steam/test/381210/hours"
    response.body.to_i.should be > 0
  end

  it "Create a user" do
    streamer = Streamiau::User.new(
      username: "test",
      realname: "Tester",
      email: "email@email.com",
      role: Streamiau::User::Role::Streamer,
      tokens: [
        Streamiau::User::Token.new(
          allow: [Streamiau::User::Token::Type::WebSocket, Streamiau::User::Token::Type::Phrases, Streamiau::User::Token::Type::Counter],
          value: "random_string_to_token",
        ),
      ],
    )
    streamer.insert
  end

  it "Cache test" do
    Streamiau::User.get("test")
    Streamiau::User.get("test")
  end

  it "User exists?" do
    Streamiau::User.exists?("test").should be_true
  end

  it "User not exists?" do
    Streamiau::User.exists?("whatever").should be_false
  end

  it "Render last Youtube video" do
    get "/api/v1/youtube/test/videos/last"
    response.body.should contain(" - ")
  end

  it "Render last Youtube short" do
    get "/api/v1/youtube/test/shorts/last"
    response.body.should contain(" - ")
  end

  it "Create a Phrases" do
    # token = Streamiau::User.get_user_by_username("test")
    phrases = Streamiau::Routes::API::V1::Phrases.new(
      username: "test",
      categories: {
        "thyria" => Streamiau::Routes::API::V1::Phrases::Category.new(phrases: [
          "phrase 1",
          "phrase 2",
          "phrase 3",
        ]),
        "john" => Streamiau::Routes::API::V1::Phrases::Category.new(phrases: [
          "seven minutes is all I can spare to play with you.",
          "poor performance indeed.",
          "you disappoint me. Is that the best you`ve got?",
          "is that all you have?",
        ]),
      }
    )
    phrases.insert
  end

  it "Render a random Phrase" do
    phrases = Streamiau::Routes::API::V1::Phrases.find_one!({username: "test"})

    get "/api/v1/phrases/test/john?&args="
    phrases.categories["john"].phrases.includes?(response.body).should be_true
  end

  it "Render find a Phrase" do
    get "/api/v1/phrases/test/john?args=performance"
    response.body.should eq "poor performance indeed."
  end

  it "Add a Phrase" do
    get "/api/v1/phrases/test/john?token=random_string_to_token&args=add%20Hello%20World"
    response.body.should eq %("Hello World" - Adicionado com sucesso.)
  end

  it "Remove a Phrase" do
    get "/api/v1/phrases/test/john?token=random_string_to_token&args=rem%20Hello%20World"
    response.body.should eq %("Hello World" - Removido com sucesso.)
  end

  it "Create a Counter" do
    counter = Streamiau::Routes::API::V1::Counter.new(username: "test", value: 10)
    counter.insert
    counter.value.should eq 10
  end

  it "Set value to a Counter" do
    counter = Streamiau::Routes::API::V1::Counter.find_one!({username: "test"})

    get "/api/v1/counter/test/#{counter.uuid}?args=set%2018&token=random_string_to_token"
    sleep 1.5.seconds # wait fiber write and broadcast
    response.body.should eq "18"
  end
end
