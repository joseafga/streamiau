require "./spec_helper"
require "spec-kemal/session"

describe Streamiau do
  it "Get Steam owned games" do
    games = Streamiau::Routes::API::V1::Steam.owned_games(76561199118689987_u64, [381210_u32])
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

  it "Cache test" do
    Streamiau::User.fetch("test")
    Streamiau::User.fetch("test")
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

  it "Render Random Phrase" do
    token = Streamiau::User.get("test").tokens.first
    phrases = Streamiau::Routes::API::V1::Phrases.new("test", "john").value

    get "/api/v1/phrase/test/john?token=#{token}&args="
    phrases.includes?(response.body).should be_true
  end

  it "Render find a Phrase" do
    token = Streamiau::User.get("test").tokens.first

    get "/api/v1/phrase/test/john?token=#{token}&args=world"
    response.body.should eq "Hello, world!"
  end

  it "Create a Counter" do
    counter = Streamiau::Routes::API::V1::Counter.create("test", 10)
    counter.value.should eq 10
  end

  it "Set value to a Counter" do
    token = Streamiau::User.get("test").tokens.first
    keys = Streamiau::Store.keys(prefix: "counter:test:")
    uuid = keys.first.name.lstrip("counter:test:")

    get "/api/v1/counter/test/#{uuid}?args=set%2018&token=#{token}"
    response.body.should eq "18"
  end
end
