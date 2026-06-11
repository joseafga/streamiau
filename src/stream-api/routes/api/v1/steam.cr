module Stream::Api::Routes::API::V1::Steam
  extend self

  def hours_played_by_username(env)
    env.response.content_type = "text/plain; charset=utf-8"
    username = env.params.url["username"].to_s
    appid = env.params.url["appid"].to_u32

    user = User.fetch(username)
    # Allowed only if user have a steamid
    if user.steamid?
      owned_games = owned_games(user.steamid, [appid])
      Log.debug { "steam owned_games=#{owned_games}" }

      if game = owned_games.games.try(&.find { |g| g.appid == appid })
        hours = game.playtime_forever // 60 # Convert minutes to hours
        return hours.to_s
      end
    end

    env.response.status_code = 403
    env.response.print "Forbidden"
    env.response.close
  end

  @[Deprecated("Use `#hours_played_by_username(HTTP::Server::Context)` instead")]
  def hours_played_by_steamid(env)
    env.response.content_type = "text/plain; charset=utf-8"
    steamid = env.params.url["steamid"].to_u64
    appid = env.params.url["appid"].to_u32

    owned_games = owned_games(steamid, [appid])
    Log.debug { "steam owned_games=#{owned_games}" }

    if game = owned_games.games.try(&.find { |g| g.appid == appid })
      hours = game.playtime_forever // 60 # Convert minutes to hours
      return hours.to_s
    end

    env.response.status_code = 403
    env.response.print "Forbidden"
    env.response.close
  end

  def owned_games(steamid : UInt64, appids = [] of UInt32) : OwnedGames
    request = OwnedGamesRequest.new(
      steamid: steamid,
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
      pp response.status_code

      case response.status_code
      when 429 # Too many requests -> try again
        break if (retries += 1) >= 5
        sleep 300.milliseconds * retries

        Log.debug { "steam 429: Trying again..." }
        next
      when 200
        owned_games = OwnedGames.from_json(response.body, root: "response")

        break
      end
    end

    raise "Request failed." if owned_games.nil?
    owned_games
  rescue
    Log.debug { "request failed, using cached games" }
    # TODO: Use cache
    OwnedGames.from_json(%({"response": {"game_count": 0}}), root: "response")
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

  struct OwnedGames
    include JSON::Serializable

    getter game_count : UInt32
    getter games : Array(Game)?
  end

  struct Game
    include JSON::Serializable

    getter appid : UInt32
    getter playtime_forever : UInt32
  end
end
