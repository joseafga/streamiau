require "uuid"

module Stream::Api::Routes::API::V1
  class Counter
    private class_getter cache = Cache::MemoryStore(Hash(String, UInt32)).new(expires_in: 24.hours)
    getter value = 0_u32

    def initialize(@username : String, @uuid : String)
      counters = Counter.all(@username)
      @value = counters[uuid]
    end

    def value=(other : UInt32) : UInt32
      counters = Counter.all(@username)
      @value = other.to_u32
      counters[@uuid] = @value

      Store.write("counter:#{@username}", counters.to_json)
      @value
    end

    def increment(inc : UInt32? = 1)
      self.value = @value + (inc || 1)
    rescue OverflowError
      self.value = UInt32::MAX
    end

    def decrement(dec : UInt32?)
      self.value = @value - (dec || 1)
    rescue OverflowError
      self.value = 0
    end

    def self.all(username)
      key = "counter:#{username}"

      @@cache.fetch(key) do
        Hash(String, UInt32).from_json(Store.read(key))
      end
    end

    def self.create(username : String, value : UInt32)
      key = "counter:#{username}"

      counters = @@cache.fetch(key) do
        Hash(String, UInt32).from_json(Store.read(key))
      end
      uuid = UUID.random.to_s

      counters[uuid] = value
      Store.write(key, counters.to_json)

      new(username, uuid)
    end

    def self.command(env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      query = env.params.query["args"]?.as(String?).try(&.presence)
      counter = new(username, uuid)

      # Subcommand
      if query
        args = query.strip.split(/\s+/, 2)

        # Token authetication required for operations
        begin
          token = env.params.query["token"].as(String)
          user = User.get(username)
          user.verify_token(token)
        rescue ex
          haltf(env, 401, ex.message)
        end

        case args[0]
        when "increment", "inc", "+"
          counter.increment(args[1]?.try &.to_u32)
        when "decrement", "dec", "-"
          counter.decrement(args[1]?.try &.to_u32)
        when "set"
          counter.value = args[1].to_u32 unless args[1]?.nil?
        end
      end

      counter.value.to_s
    end
  end
end
