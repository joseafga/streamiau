require "uuid"

module Streamiau::Routes::API::V1
  class Counter
    private class_getter cache = Cache::MemoryStore(UInt32).new(expires_in: 24.hours)
    private class_getter instances = Hash(String, Counter).new
    class_getter sockets = [] of HTTP::WebSocket

    getter key : String
    getter value : UInt32
    getter channel = Channel(UInt32).new

    def initialize(username : String, uuid : String)
      @key = "counter:#{username}:#{uuid}"

      @value = @@cache.fetch(@key) do
        Store.read(@key).to_u32
      end

      @@instances[@key] = self
      subscribe
    end

    # Subscribe to channel to update changes
    def subscribe
      spawn do
        loop do
          received = channel.receive
          Log.info { "New subscribe event from channel #{channel}" }

          # Update local and remote storage
          @@cache.write(@key, received)
          Store.write(@key, received.to_s)

          broadcast(CounterMessage.new(received))
          sleep 1.second # KV free plan
        end
      end
    end

    # Send message to all websocket clients
    def broadcast(message : Message)
      Log.info { "Broadcasting -> #{message}" }

      @@sockets.each do |socket|
        socket.send message.to_json
      end
    end

    def value=(other : UInt32) : UInt32
      unless @value == other
        @value = other
        channel.send(@value)
      end

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

    def self.instance(username : String, uuid : String)
      if instance = instances["counter:#{username}:#{uuid}"]?
        return instance
      end

      new(username, uuid)
    end

    def self.create(username : String, value : UInt32)
      uuid = UUID.random.to_s
      key = "counter:#{username}:#{uuid}"

      Store.write(key, value.to_s)
      new(username, uuid)
    end

    def self.command(env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      query = env.params.query["args"]?.as(String?).try(&.presence)
      counter = instance(username, uuid)

      # Subcommand
      if query
        args = query.strip.split(/\s+/, 2)

        # Token authetication required for operations
        begin
          token = env.params.query["token"].as(String)
          user = User.get_user_by_username(username)
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

    def self.websocket(socket, env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      counter = Counter.instance(username, uuid)

      Counter.sockets.push socket
      Log.debug { "WebSocket connected: #{socket}" }
      socket.send CounterMessage.new(counter.value).to_json # send current value

      # Handle client disconnection
      socket.on_close do |_|
        Counter.sockets.delete(socket)
        Log.debug { "Closing WebSocket: #{socket}" }
      end
    rescue
      socket.close(1008, "Socket inválido.")
      return
    end

    abstract struct Message
      include JSON::Serializable

      getter type : String
    end

    struct CounterMessage < Message
      getter type = "counter"
      property value

      def initialize(@value : UInt32); end
    end

    struct SettingsMessage < Message
      getter type = "settings"
      property font_family : String
      property prefix : String
      property font_color : String
      property font_size_prefix : Int32
      property font_size_counter : Int32

      def initialize(@font_family = "Inter", @prefix = "", @font_color = "rgb(112, 85, 189)", @font_size_prefix = 42, @font_size_counter = 100); end
    end
  end
end
