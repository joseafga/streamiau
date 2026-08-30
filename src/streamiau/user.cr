module Streamiau
  class User
    include JSON::Serializable

    private class_getter cache = Cache(String, User).new(max_size: 100)
    class_getter? warmed_up : Bool = false
    class_getter guest = User.new("Guest", Role::Guest, "")

    getter username : String # identifier
    property role : Role
    property email : String
    property! steamid : UInt64?
    property! youtubeid : String?

    @[JSON::Field(key: "_tokens")]
    getter tokens : Array(Token)

    # TODO: Use JSON initialize only?
    def initialize(@username, @role, @email, @steamid = nil, @youtubeid = nil, @tokens = [] of Token)
    end

    def initials
      username[0..1].upcase
    end

    # Update user passing new values and save on KV store
    def update(*, role : Role? = nil, email : String? = nil, steamid : UInt64? = nil, youtubeid : String? = nil)
      @role = role unless role.nil?
      @email = email unless email.nil?
      @steamid = steamid unless steamid.nil?
      @youtubeid = youtubeid unless youtubeid.nil?

      update
    end

    # Save changes on KV store
    def update
      Store.write("user:#{@username}", to_json)
    end

    # Delete user
    def delete
      User.delete(@username)
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

    def self.get(key : String) : User
      key = "user:#{key.downcase}"

      @@cache.fetch(key) do
        from_json(Store.read(key))
      end
    end

    def self.get?(key : String) : User?
      return get(key) if exists?(key)
      nil
    end

    def self.fetch(key : String, fallback : User) : User
      get?(key) || fallback
    end

    def self.fetch(key : String, &) : User
      get?(key) || yield
    end

    def self.exists?(key : String) : Bool
      key = "user:#{key.downcase}"
      return true if @@cache.has?(key)

      # Only search on KV if cache is full
      if warmed_up? && @@cache.size == @@cache.max_size
        user = from_json(Store.read(key))
        @@cache.set(key, user)

        return true
      end

      false
    rescue KV::ResponseError
      false
    end

    def self.delete(key : String) : Nil
      Store.delete("user:#{key.downcase}")
    end

    # List all cached users
    def self.all : Hash(String, Tuple(User, Time?))
      @@cache.items
    end

    # Warm up cache
    def self.warm_up : Nil
      return if warmed_up?

      keys = Store.keys(prefix: "user:", limit: @@cache.max_size)
      result = Store.read_bulk(keys.map(&.name), type: User)

      result.values.each do |key, value|
        @@cache.set(key, value) if value
      end

      @@warmed_up = true
    end

    def self.get_user_by_username(key : String) : User
      fetch(key, guest)
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
