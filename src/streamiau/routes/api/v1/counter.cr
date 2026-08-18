require "uuid"

module Streamiau::Routes::API::V1
  class Counter
    private class_getter cache = Cache::MemoryStore(UInt32).new(expires_in: 24.hours)
    private class_getter instances = Hash(String, Counter).new

    getter key : String
    getter value : UInt32
    getter channel = Channel(NamedTuple(value: UInt32, metadata: Metadata?)).new
    getter sockets = [] of HTTP::WebSocket

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

      sockets.each do |socket|
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

    def self.parse(input : String?) : {String?, UInt32?, String?}
      return {nil, nil, nil} unless input = input.try(&.strip.presence)
      return {nil, nil, nil} if input.starts_with?('@') # ignore subcommand when reply

      parts = input.strip.split(/\s+/, 3)
      if parts[0]? =~ /^\d+$/
        {"set", parts[0].to_u32, parts[1..2].join(" ").presence}
      else
        {parts[0], parts[1]?.try(&.to_u32), parts[2]?.as(String?)}
      end
    end

    def self.command(env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      args = env.params.query["args"]?.as(String?).try(&.presence)
      counter = instance(username, uuid)

      cmd, new_value, note = parse(args)

      # Subcommand
      if cmd
        check_permission(env)
        metadata = nil # optional sender metadata

        if sender = env.params.query["sender"]?.as(String?)
          metadata = Metadata.new(sender, note)
        end

        case cmd
        when "increment", "inc", "+", "add"
          counter.increment(new_value, metadata)
        when "decrement", "dec", "-", "remove"
          counter.decrement(new_value, metadata)
        when "set"
          counter.set(new_value, metadata) unless new_value.nil?
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
      user = User.get_user_by_username(username)

      counter.sockets.push socket
      Log.debug { "WebSocket connected: #{socket}" }
      socket.send CounterMessage.new(counter.value, nil).to_json # send current value

      socket.on_pong do
        socket.alive = true
      end

      # Handle incoming messages from clients
      socket.on_message do |incoming|
        Log.debug { "Received WebSocket(#{socket}): #{incoming}" }
        message = CounterMessage.from_json(incoming)

        if token = message.token
          user.verify_token(:web_socket, token)
          counter.set(message.value, message.metadata)
        end
      rescue ex
        Log.error { "Messsage with error WebSocket(#{socket}): #{ex.message}" }
      end

      # Handle client disconnection
      socket.on_close do |_|
        Log.debug { "Closing WebSocket: #{socket}" }
        counter.sockets.delete(socket)
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
      property token : String?

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

    # Check sockets connection.
    # All sockets start `alive`, when ping is send socket become `dead`, pong response
    # set as `alive` again
    spawn do
      loop do
        sleep 30.seconds

        @@instances.each do |_key, counter|
          counter.sockets.each do |socket|
            unless socket.alive?
              socket.close
              next
            end

            socket.alive = false

            begin
              socket.ping
            rescue
              socket.close
            end
          end
        end
      end
    end
  end
end
