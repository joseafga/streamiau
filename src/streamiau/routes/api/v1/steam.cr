module Streamiau::Routes::API::V1::Steam
  extend self

  STEAM_API_KEY      = ENV["STEAM_API_KEY"]
  DEPRECATED_STEAMID = ENV["ALLOWED_DEPRECATED_STEAMID"].split(',').map(&.to_u64)
  private class_getter cache = Cache(String, OwnedGames).new(max_size: 100)

  def command(env)
    username = env.params.url["username"]

    # New endpoint use almost same pattern of deprecated.
    # Deprecated use SteamID with only numbers, new one uses Username
    if username.match(/^\d+$/)
      hours_played_by_steamid(env)
    else
      hours_played_by_username(env)
    end
  end

  def hours_played_by_username(env)
    username = env.params.url["username"].as(String)
    user = User.get_user_by_username(username)
    appid = env.params.url["appid"].to_u32

    # Allowed only if user have a steamid
    if user.steamid?
      owned_games = owned_games(user.steamid, [appid])
      Log.debug { "steam owned_games=#{owned_games}" }

      if game = owned_games.games.try(&.find { |g| g.appid == appid })
        hours = game.playtime_forever // 60 # Convert minutes to hours
        return hours.to_s
      end
    end

    haltf(env, 403, "Forbidden")
  end

  @[Deprecated("Use `#hours_played_by_username(HTTP::Server::Context)` instead")]
  def hours_played_by_steamid(env)
    steamid = env.params.url["username"].as(String)
    appid = env.params.url["appid"].to_u32

    # Check if steamid is allowed
    if DEPRECATED_STEAMID.includes? steamid
      owned_games = owned_games(steamid, [appid])
      Log.debug { "steam owned_games=#{owned_games}" }

      if game = owned_games.games.try(&.find { |g| g.appid == appid })
        hours = game.playtime_forever // 60 # Convert minutes to hours
        return hours.to_s
      end
    end

    haltf(env, 403, "Forbidden")
  end

  def owned_games(steamid : String, appids = [] of UInt32) : OwnedGames
    request = OwnedGamesRequest.new(
      steamid: steamid.to_u64,
      include_appinfo: false,
      include_played_free_games: false,
      appids_filter: appids,
      include_free_sub: nil,
      language: nil, # "pt-BR"
      include_extended_appinfo: nil,
    )

    uri = URI.new("https", "api.steampowered.com", path: "/IPlayerService/GetOwnedGames/v1")
    uri.query = URI::Params.encode({
      "key"        => STEAM_API_KEY,
      "format"     => "json",
      "input_json" => request.to_json,
    })

    retries = 0
    owned_games = nil

    loop do
      response = HTTP::Client.get(uri)

      case response.status_code
      when 429 # Too many requests -> try again
        break if (retries += 1) >= 3
        sleep 300.milliseconds * retries

        Log.debug { "steam 429: Trying again..." }
        next
      when 200
        owned_games = OwnedGames.from_json(response.body, root: "response")
        cache.set("#{steamid}&#{appids.join(",")}", owned_games)

        break
      end
    end

    raise "Request failed." if owned_games.nil?
    owned_games
  rescue
    Log.debug { "request failed, using cached games" }

    cache.fetch("#{steamid}&#{appids.join(",")}", OwnedGames.new(0_u32, nil))
  end

  struct OwnedGamesRequest
    include JSON::Serializable

    getter steamid : UInt64
    getter? include_appinfo : Bool
    getter? include_played_free_games : Bool
    getter appids_filter : Array(UInt32)
    getter include_free_sub : Bool?
    getter language : String?
    getter include_extended_appinfo : Bool?

    def initialize(@steamid, @include_appinfo, @include_played_free_games, @appids_filter, @include_free_sub, @language, @include_extended_appinfo)
    end
  end

  record OwnedGames, game_count : UInt32, games : Array(Game)? do
    include JSON::Serializable
  end

  record Game, appid : UInt32, playtime_forever : UInt32 do
    include JSON::Serializable
  end
end
