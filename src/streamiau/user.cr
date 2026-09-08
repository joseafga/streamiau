module Streamiau
  class User < Moongoon::Collection
    collection "users"

    private class_getter cache = Streamiau::Cache(String, User).new(max_size: 100)
    class_getter? warmed_up : Bool = false
    class_getter guest = User.new(username: "guest", realname: "Guest", email: "")
    property username : String # identifier
    property realname : String
    property email : String
    property steamid : String?
    property youtubeid : String?
    property role : Int32 = Streamiau::User::Role::Guest.value

    @[BSON::Field(key: "_tokens")]
    property tokens : Array(Token) = [] of Streamiau::User::Token

    index keys: {username: 1}, options: {unique: true}

    after_insert do |user|
      @@cache.set(user.username, user)
    end

    after_remove do |user|
      @@cache.delete(user.username)
    end

    def role : Role
      Role.from_value(@role)
    end

    def role=(other : Role)
      @role = other.value
    end

    def initials
      realname[0..1].upcase
    end

    # Check if user have token and change type is allowed
    def token_verify(type : Token::Type, value : String) : Nil
      @tokens.each do |token|
        return if token.allow.includes?(type) && token.value == value
      end

      raise UnauthorizedError.new "Token inválido."
    end

    def self.get_by_username(username : String) : User
      @@cache.fetch(username) do
        User.find_one!({username: username})
      end
    end

    # Get user or a guest if not found
    def self.get_by_username?(username : String) : User?
      return get_by_username(username) if exists?(username)
      nil
    end

    def self.get_by_username_or_guest(username : String) : User
      get_by_username?(username) || guest
    end

    def self.exists?(username : String) : Bool
      return true if @@cache.has?(username)

      # Only search on DB if cache is full
      if !warmed_up? || @@cache.size == @@cache.max_size
        if user = User.find_one({username: username})
          @@cache.set user.username, user

          return true
        end
      end

      false
    end

    # List all cached users
    def self.all : Hash(String, Tuple(User, Time?))
      @@cache.items
    end

    # Warm up cache
    def self.warm_up : Nil
      return if warmed_up?

      users = User.find
      users.each do |user|
        @@cache.set user.username, user
      end

      @@warmed_up = true
    end

    class Token < Moongoon::Document
      property value : String
      property allow : Array(Int32) = [] of Int32
      getter created_at : Time = Time.utc

      def allow : Array(Type)
        @allow.map { |v| Type.from_value(v) }
      end

      def allow=(other : Array(Type))
        @allow = other.map &.value
      end
    end
  end
end
