require "uuid"

module Streamiau::Routes::API::V1
  class Counter < Moongoon::Collection
    collection "counters"
    reference username, model: Streamiau::User, delete_cascade: true

    private class_getter cache = Streamiau::Cache({String, String}, Counter).new(expires_in: 24.hours)
    property username : String
    property uuid : String = UUID.random.to_s
    property value : Int32 = 0
    property metadata : Metadata?

    @[JSON::Field(ignore: true)]
    @[BSON::Field(ignore: true)]
    getter sockets = [] of HTTP::WebSocket

    @[JSON::Field(ignore: true)]
    @[BSON::Field(ignore: true)]
    @channel = Channel(Tuple(Int32, Metadata?)).new

    @[JSON::Field(ignore: true)]
    @[BSON::Field(ignore: true)]
    @signal = Channel(Symbol).new

    index keys: {uuid: 1}, options: {unique: true}

    after_insert do |counter|
      @@cache.set({counter.username, counter.uuid}, counter)
      counter.subscribe
    end

    after_remove do |counter|
      @@cache.delete({counter.username, counter.uuid})
    end

    # Subscribe channel to update changes
    # Always write changes to cache but only write to DB after 1 second.
    def subscribe
      spawn do
        loop do
          select
          when received = @channel.receive
            loop do
              Log.debug { "New subscribe event -> `#{received}`" }
              message = CounterMessage.new(received[0], received[1])
              @@cache.set({@username, @uuid}, self)

              select
              when received = @channel.receive
              when timeout(1.second)
                update

                broadcast(message)
                break
              end
            end
          when signal = @signal.receive
            Log.debug { "Signal received -> `#{signal}`" }
            if signal == :stop
              @@cache.delete({@username, @uuid})
              break
            end
          end
        end
      end

      self
    end

    def unsubscribe
      @signal.send :stop
    end

    # Send message to all websocket clients
    def broadcast(message : Message)
      Log.debug { "Broadcasting -> #{message}" }

      sockets.each do |socket|
        socket.send message.to_json
      end
    end

    def set(other : Int32, metadata : Metadata? = nil) : Int32
      if @value != other || metadata
        @value = other
        @metadata = metadata
        @channel.send({@value, metadata})
      end

      @value
    rescue OverflowError
      set(0, metadata)
    end

    def increment(inc : Int32? = 1, metadata : Metadata? = nil)
      set(@value + (inc || 1), metadata)
    rescue OverflowError
      set(Int32::MAX, metadata)
    end

    def decrement(dec : Int32? = 1, metadata : Metadata? = nil)
      set(@value - (dec || 1), metadata)
    rescue OverflowError
      set(Int32::MIN, metadata)
    end

    def self.get(username : String, uuid : String)
      @@cache.fetch({username, uuid}) do
        counter = Counter.find_one!({username: username, uuid: uuid})
        counter.subscribe
      end
    end

    def self.parse(input : String?) : {String?, Int32?, String?}
      return {nil, nil, nil} unless input = input.try(&.strip.presence)
      return {nil, nil, nil} if input.starts_with?('@') # ignore subcommand when reply

      parts = input.strip.split(/\s+/, 3)
      if parts[0]? =~ /^\d+$/
        {"set", parts[0].to_i, parts[1..2].join(" ").presence}
      else
        {parts[0], parts[1]?.try(&.to_i), parts[2]?.as(String?)}
      end
    end

    def self.command(env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      args = env.params.query["args"]?.as(String?).try(&.presence)
      counter = get(username, uuid)

      cmd, new_value, note = parse(args)

      # Subcommand
      if cmd
        check_permission(env)
        metadata = nil # optional sender metadata

        if sender = env.params.query["sender"]?.as(String?)
          metadata = Metadata.new(sender: sender, message: note)
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
      counter = Counter.get(username, uuid)
      user = User.get_user_by_username(username)

      counter.sockets.push socket
      Log.info { "WebSocket connected: #{socket}" }
      socket.send CounterMessage.new(counter.value, counter.metadata).to_json # send current value

      socket.on_pong do
        socket.alive = true
      end

      # Handle incoming messages from clients
      socket.on_message do |incoming|
        Log.debug { "Received WebSocket(#{socket}): #{incoming}" }
        message = CounterMessage.from_json(incoming)

        if token = message.token
          user.token_verify(:web_socket, token)
          counter.set(message.value, message.metadata)
        end
      rescue ex
        Log.error { "Messsage with error WebSocket(#{socket}): #{ex.message}" }
      end

      # Handle client disconnection
      socket.on_close do |_|
        Log.info { "Closing WebSocket: #{socket}" }
        counter.sockets.delete(socket)
      end
    rescue
      socket.close(1008, "Invalid Socket.")
      return
    end

    class Metadata < Moongoon::Document
      getter time = Time.utc
      property sender : String
      property message : String?
    end

    abstract struct Message
      include JSON::Serializable

      getter type : String
    end

    struct CounterMessage < Message
      getter type = "counter"
      property value : Int32
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

        @@cache.items.each do |_key, item|
          item[0].sockets.each do |socket|
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

          # Stop loop and remove cache if have no more clients
          item[0].unsubscribe if item[0].sockets.empty?
        end
      end
    end
  end
end
