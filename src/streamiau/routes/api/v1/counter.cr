require "uuid"

module Streamiau::Routes::API::V1
  class Counter
    private class_getter cache = Cache::MemoryStore(UInt32).new(expires_in: 24.hours)
    private class_getter instances = Hash(String, Counter).new
    class_getter sockets = [] of HTTP::WebSocket

    getter key : String
    getter value : UInt32
    getter channel = Channel(NamedTuple(value: UInt32, metadata: Metadata?)).new

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
          Log.info { "New subscribe event -> #{received}" }
          message = CounterMessage.new(received[:value], received[:metadata])

          # Update local and remote storage
          @@cache.write(@key, message.value)
          Store.write(@key, message.value, metadata: message.metadata)

          broadcast(message)
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

    def set(other : UInt32, metadata : Metadata? = nil) : UInt32
      if @value != other || metadata
        @value = other
        channel.send({value: @value, metadata: metadata})
      end

      @value
    end

    def increment(inc : UInt32? = 1, metadata : Metadata? = nil)
      set(@value + (inc || 1), metadata)
    rescue OverflowError
      set(UInt32::MAX, metadata)
    end

    def decrement(dec : UInt32?, metadata : Metadata? = nil)
      set(@value - (dec || 1), metadata)
    rescue OverflowError
      set(0_u32, metadata)
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
      args = env.params.query["args"]?.as(String?).try(&.presence)
      counter = instance(username, uuid)

      # Subcommand
      if args && !args.starts_with?('@')
        check_permission(env)
        parts = args.strip.split(/\s+/, 3)
        metadata = nil # optional sender metadata

        if sender_name = env.params.query["sender"]?.as(String?)
          sender_message = parts[2]?.as(String?)
          metadata = Metadata.new(sender_name, sender_message)
        end

        case parts[0]
        when "increment", "inc", "+", "add"
          counter.increment(parts[1]?.try(&.to_u32), metadata)
        when "decrement", "dec", "-", "remove"
          counter.decrement(parts[1]?.try(&.to_u32), metadata)
        when "set"
          counter.set(parts[1].to_u32, metadata) unless parts[1]?.nil?
        end
      end

      counter.value.to_s
    rescue ex : Exception
      # StreamElements only shows 200's messages
      haltf(env, 200, ex.message.try(&.[..128]))
    end

    def self.websocket(socket, env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      counter = Counter.instance(username, uuid)

      Counter.sockets.push socket
      Log.debug { "WebSocket connected: #{socket}" }
      socket.send CounterMessage.new(counter.value, nil).to_json # send current value

      # Handle client disconnection
      socket.on_close do |_|
        Counter.sockets.delete(socket)
        Log.debug { "Closing WebSocket: #{socket}" }
      end
    rescue
      socket.close(1008, "Invalid Socket.")
      return
    end

    struct Metadata
      include JSON::Serializable

      getter time = Time.utc
      property sender : String
      property message : String?

      def initialize(@sender, @message = nil); end
    end

    abstract struct Message
      include JSON::Serializable

      getter type : String
    end

    struct CounterMessage < Message
      getter type = "counter"
      property value : UInt32
      property metadata : Metadata?

      def initialize(@value, @metadata = nil); end
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
