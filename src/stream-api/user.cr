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

    def self.fetch(key : String) : User
      key = "user:#{key.downcase}" # real key

      @@cache.fetch(key) do
        from_json(Store.read(key))
      end
    end

    def self.fetch?(key : String) : User?
      fetch(key)
    rescue KV::ResponseError
      nil
    end

    def self.exists?(key : String) : Bool
      key = "user:#{key.downcase}"

      return true if @@cache.exists?(key) || Store.read(key)
      false
    rescue KV::ResponseError
      false
    end

    def self.guest
      User.new("Guest", Role::Guest, "")
    end

    enum Role
      Admin
      Streamer
      User
      Guest
    end
  end
end
