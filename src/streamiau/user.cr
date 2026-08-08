module Streamiau
  class User
    include JSON::Serializable

    private class_getter cache = Cache::MemoryStore(User).new(expires_in: 1.hour)
    class_getter guest = User.new("Guest", Role::Guest, "")

    getter username : String # identifier
    getter role : Role
    getter email : String
    getter! steamid : UInt64?
    getter! youtubeid : String?

    @[JSON::Field(key: "_tokens")]
    getter tokens : Array(String)

    # TODO: Use JSON initialize only?
    def initialize(@username, @role, @email, @steamid = nil, @youtubeid = nil, @tokens = [] of String)
    end

    def tokens_clear
      @tokens = [] of String
      Store.write("user:#{@username}", to_json)
    end

    def tokens_revoke(token : String)
      @tokens.delete(token)
      Store.write("user:#{@username}", to_json)
    end

    def tokens_new
      @tokens.push Random::Secure.hex(32)
      Store.write("user:#{@username}", to_json)
    end

    def verify_token(token)
      raise UnauthorizedError.new "Token inválido." unless @tokens.includes?(token)
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

    def self.get_user_by_username(key : String) : User
      fetch?(key) || guest
    end

    enum Role
      Admin
      Streamer
      User
      Guest
    end
  end
end
