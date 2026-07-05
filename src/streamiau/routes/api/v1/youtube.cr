module Streamiau::Routes::API::V1::Youtube
  extend self

  def last_channel_video(env)
    list_channel_videos(:videos, env)
  end

  def last_channel_short(env)
    list_channel_videos(:shorts, env)
  end

  def list_channel_videos(type : Type, env)
    username = env.params.url["username"].as(String)
    user = User.get_user_by_username(username)
    lang = env.params.query["lang"]?.as(String?) || "en"

    if user.youtubeid?
      videos = [] of Entry
      fetch_entries("https://www.youtube.com/@#{user.youtubeid}/#{type.to_s.downcase}", lang, 1).each_line do |entry|
        videos.push Entry.from_json(entry)
      end

      return "#{videos.first.title} - #{videos.first.url}" if videos.first
    end

    haltf(env, 404, "Not Found")
  end

  def fetch_entries(url : String, lang : String = "en", limit = 1) : String
    raise ArgumentError.new("Invalid language: #{lang}") unless Languages.includes? lang

    process = Process.new("yt-dlp", [
      "--extractor-args",
      "youtube:lang=#{lang}",
      "--dump-json",
      "--no-download",
      "--flat-playlist",
      "--playlist-end=#{limit}",
      url,
    ], output: Process::Redirect::Pipe)

    output = process.output.gets_to_end
    process.close
    status = process.wait

    if status.success?
      output
    else
      raise "Command yt-dlp failed (#{status.exit_code})."
    end
  end

  Languages = %w[af az id ms bs ca cs da de et en-IN en-GB en es es-419 es-US eu fil fr fr-CA
    gl hr zu is it sw lv lt hu nl no uz pl pt-PT pt ro sq sk sl sr-Latn fi sv vi tr be bg ky
    kk mk mn ru sr uk el hy iw ur ar fa ne mr hi as bn pa gu or ta te kn ml si th lo my ka am
    km zh-CN zh-TW zh-HK ja ko]

  enum Type
    Videos
    Shorts
  end

  struct Thumbnail
    include JSON::Serializable

    getter url : String
    getter height : Int32
    getter width : Int32
  end

  struct Entry
    include JSON::Serializable

    getter title : String
    getter thumbnails : Array(Thumbnail)
    getter duration : Float64?
    # getter timestamp : String?
    # @[JSON::Field(key: "ie_key")]
    # getter ie_key : String
    getter id : String
    getter url : String
    # getter original_url : String
    # getter webpage_url : String
    # getter webpage_url_basename : String
    # getter webpage_url_domain : String
    # getter extractor : String
    # getter extractor_key : String
    # getter playlist_count : Int32?
    # getter playlist : String
    # getter playlist_id : String
    # getter playlist_title : String
    # getter playlist_uploader : String
    # getter playlist_uploader_id : String
    # getter playlist_channel : String
    # getter playlist_channel_id : String
    # getter playlist_webpage_url : String
    # getter n_entries : Int32
    # getter playlist_index : Int32
    # getter playlist_autonumber : Int32
    getter epoch : Int64
    # getter duration_string : String
    # getter release_year : Int32?
  end
end
