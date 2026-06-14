require "./spec_helper"
require "spec-kemal/session"

describe Stream::Api do
  it "Get Steam owned games" do
    games = Stream::Api::Routes::API::V1::Steam.owned_games(76561199118689987_u64, [381210_u32])
    games.games.try &.first.appid.should eq 381210_u32
  end

  it "Render Steam hours played by steamid" do
    get "/api/v1/steam/76561199118689987/381210/hours"
    response.body.to_i.should be > 0
  end

  it "Render Steam hours played by username" do
    get "/api/v1/test/steam/381210/hours"
    response.body.to_i.should be > 0
  end

  it "Cache test" do
    Stream::Api::User.fetch("test")
    Stream::Api::User.fetch("test")
  end

  it "User exists?" do
    Stream::Api::User.exists?("test").should be_true
  end

  it "User not exists?" do
    Stream::Api::User.exists?("whatever").should be_false
  end

  it "Get Youtube videos using yt-dlp" do
    Stream::Api::Routes::API::V1::Youtube.fetch_entries("https://www.youtube.com/@youtube/videos").should be_a(String)
  end

  it "Render last Youtube video" do
    get "/api/v1/youtube/test/video"
    response.body.should contain(" - ")
  end

  it "Render last Youtube short" do
    get "/api/v1/youtube/test/short"
    response.body.should contain(" - ")
  end

  it "Random Sentence" do
    sentences = Stream::Api::Routes::API::V1::Sentence.sentences["john"]
    response = Stream::Api::Routes::API::V1::Sentence.random("john")
    sentences.includes?(response).should be_true
  end
end
