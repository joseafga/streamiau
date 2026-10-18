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
    @channel = Channel(Int32).new

    @[JSON::Field(ignore: true)]
    @[BSON::Field(ignore: true)]
    @signal = Channel(Symbol).new

    index keys: {username: 1, uuid: 1}, options: {unique: true}

    after_insert do |counter|
      @@cache.set({counter.username, counter.uuid}, counter)
      counter.subscribe
    end

    after_remove do |counter|
      @@cache.delete({counter.username, counter.uuid})
    end

    # Always write changes to cache but only write to DB after *debounce*.
    private def handle_event(received, debounce : Time::Span) : Nil
      loop do
        Log.debug { "New subscribe event -> `#{received}`" }
        message = CounterMessage.new(@value, @metadata)
        @@cache.set({@username, @uuid}, self)

        select
        when received = @channel.receive
        when timeout(debounce)
          update
          broadcast(message)
          break
        end
      end
    end

    # TODO: Currently have only stop loop function but can have better use
    private def handle_signal(signal) : Nil
      Log.debug { "Signal received -> `#{signal}`" }

      case signal
      when :stop
        @@cache.delete({@username, @uuid})
      end
    end

    # Subscribe channel to update changes
    def subscribe
      spawn do
        loop do
          select
          when received = @channel.receive
            handle_event(received, 1.second)
          when signal = @signal.receive
            handle_signal(signal)
            break if signal == :stop
          end
        end
      end
    end

    def unsubscribe
      @signal.send :stop
    end

    # Send message to all websocket clients. A broken socket must not prevent the others
    # from receiving the message.
    def broadcast(message : Message)
      Log.debug { "Broadcasting -> #{message}" }

      payload = message.to_json

      # Duplicate to keep state on memory, maybe socket close before send message.
      sockets.dup.each do |socket|
        socket.send payload
      rescue ex
        Log.warn { "Dropping socket #{socket}: #{ex.message}" }
        sockets.delete(socket)
        socket.close rescue nil
      end
    end

    def set(other : Int32, metadata : Metadata? = nil) : Int32
      if @value != other || metadata
        @value = other
        @metadata = metadata
        @channel.send @value
      end

      @value
    end

    def increment(inc : Int32 = 1, metadata : Metadata? = nil) : Int32
      set(saturate(inc.to_i64), metadata)
    end

    def decrement(dec : Int32 = 1, metadata : Metadata? = nil) : Int32
      set(saturate(-dec.to_i64), metadata)
    end

    # Saturating arithmetic (Int64 internally): allowing `inc -5` and `set` has no
    # arithmetic so it needs no OverflowError.
    private def saturate(delta : Int64) : Int32
      (delta + @value).clamp(Int32::MIN..Int32::MAX).to_i32
    end

    # Get `Counter` and spawn a fiber to catch updates.
    # Every `Counter` in cache will have its own fiber, another global fiber checks for
    # clients and kill unused `Counter`s.
    def self.get(username : String, uuid : String)
      @@cache.fetch({username, uuid}) do
        counter = Counter.find_one!({username: username, uuid: uuid})
        counter.subscribe
        counter
      end
    end

    # Receive args and parse to {**command**, **value**, **metadata message**}:
    # - "+26" -> {"inc", 26, nil}
    # - "add 26" -> {"add", 26, nil}
    # - "+26 comment" -> {"inc", 26, "comment"}
    # - "+ 26 comment" -> {"+", 26, "comment"}
    def self.parse(input : String?) : {String?, Int32?, String?}
      return {nil, nil, nil} unless input = input.try(&.strip.presence)
      return {nil, nil, nil} if input.starts_with?('@') # ignore subcommand when reply

      parts = input.split(/\s+/, 3)
      first = parts[0]
      rest = parts[1..].join(" ").presence

      if match = first.match(/\A([+-]?)(\d+)\z/)
        sign, digits = match[1], match[2]
        amount = digits.to_i

        case sign
        when "-" then {"dec", amount, rest}
        when "+" then {"inc", amount, rest}
        else          {"set", amount, rest}
        end
      else
        amount = parts[1]?.try { |text| /\A[+-]?\d+\z/.matches?(text) ? text.to_i : nil }
        note = amount ? parts[2]? : rest

        {first, amount, note}
      end
    end

    def self.command(env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      args = env.params.query["args"]?.as(String?).try(&.presence)
      counter = get(username, uuid)

      cmd, arg_value, arg_msg = parse(args)

      # Subcommand
      if cmd
        check_permission(env)
        metadata = nil # optional sender metadata

        if sender = env.params.query["sender"]?.as(String?)
          metadata = Metadata.new(sender: sender, message: arg_msg)
        end

        case cmd
        when "increment", "inc", "+", "add"
          counter.increment(arg_value || 1, metadata)
        when "decrement", "dec", "-", "remove"
          counter.decrement(arg_value || 1, metadata)
        when "reset"
          counter.set(0, metadata)
        when "set"
          counter.set(arg_value, metadata) unless arg_value.nil?
        end
      end

      counter.value.to_s
    rescue Moongoon::Error::NotFound
      haltf(env, 200, "Não encontrado.")
    rescue ex : Exception # StreamElements only shows 200's messages
      Log.error(exception: ex) { "Counter command failed" }
      haltf(env, 200, ex.message.try(&.[..128]))
    end

    def self.websocket(socket, env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      counter = Counter.get(username, uuid)
      user = User.get_by_username(username)

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
        Log.error { "Message with error WebSocket(#{socket}): #{ex.message}" }
      end

      # Handle client disconnection
      socket.on_close do |_|
        Log.info { "Closing WebSocket: #{socket}" }
        counter.sockets.delete(socket)
      end
    rescue ex
      Log.warn { "WebSocket rejected: #{ex.message}" }
      socket.close(1008, "Invalid Socket.") rescue nil
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
