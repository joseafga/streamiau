module Stream::Api
  class User
    include JSON::Serializable
    @@cache = Cache::MemoryStore(User).new(expires_in: 30.days)

    getter username : String # identifier
    getter role : Role
    getter email : String
    getter! steamid : UInt64?
    getter! youtubeid : String?

    # TODO: Use JSON initialize only?
    def initialize(@username, @role, @email, @steamid = nil, @youtubeid = nil)
    end

    def self.fetch(key : String)
      key = "user:#{key.downcase}" # real key

      @@cache.fetch(key) do
        User.from_json(Store.read(key))
      end
    rescue KV::ResponseError
      User.new("Guest", User::Role::Guest, "")
    end

    enum Role
      Admin
      Streamer
      User
      Guest
    end
  end
end
