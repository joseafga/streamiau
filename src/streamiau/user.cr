module Streamiau
  class User
    include JSON::Serializable

    private class_getter cache = Cache(String, User).new(max_size: 100)
    class_getter guest = User.new("Guest", Role::Guest, "")

    getter username : String # identifier
    getter role : Role
    getter email : String
    getter! steamid : UInt64?
    getter! youtubeid : String?

    @[JSON::Field(key: "_tokens")]
    getter tokens : Array(Token)

    # TODO: Use JSON initialize only?
    def initialize(@username, @role, @email, @steamid = nil, @youtubeid = nil, @tokens = [] of Token)
    end

    def initials
      username[0..1].upcase
    end

    def tokens_clear
      @tokens = [] of Token

      Store.write("user:#{@username}", to_json)
    end

    def tokens_revoke(value : String)
      @tokens.reject! do |token|
        token.value == value
      end

      Store.write("user:#{@username}", to_json)
    end

    def tokens_new(types : Array(Token::Type))
      @tokens << Token.new(types, Random::Secure.hex(32))

      Store.write("user:#{@username}", to_json)
    end

    def verify_token(type : Token::Type, value : String) : Nil
      @tokens.each do |token|
        return if token.allow.includes?(type) && token.value == value
      end

      raise UnauthorizedError.new "Token inválido."
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

      return true if @@cache.has?(key)
      return true if @@cache.set(key, from_json(Store.read(key)))

      false
    rescue KV::ResponseError
      false
    end

    def self.get_user_by_username(key : String) : User
      fetch?(key) || guest
    end

    record Token, allow : Array(Type), value : String do
      include JSON::Serializable
      getter created_at : Time = Time.utc

      enum Type
        WebSocket
        Phrases
        Counter
      end
    end

    enum Role
      Admin
      Streamer
      Member
      Guest
    end
  end
end
