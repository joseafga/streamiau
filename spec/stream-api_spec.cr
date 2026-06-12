require "./spec_helper"
require "spec-kemal/session"

describe Stream::Api do
  it "Get Steam owned games" do
    games = Stream::Api::Routes::API::V1::Steam.owned_games(76561199118689987_u64, [381210_u32])
    games.games.try &.first.appid.should eq 381210_u32
  end

  it "Render Steam hours played by steamid" do
    get "/api/v1/steam/76561199118689987/381210/hours"
    (response.body.to_i > 0).should be_true
  end

  it "Render Steam hours played by username" do
    get "/api/v1/jonh/steam/381210/hours"
    (response.body.to_i > 0).should be_true
  end

  it "Cache test" do
    Stream::Api::User.fetch("jonh")
  end

  it "User exists?" do
    Stream::Api::User.exists?("jonh").should be_true
  end

  it "User not exists?" do
    Stream::Api::User.exists?("whatever").should be_false
  end
end
