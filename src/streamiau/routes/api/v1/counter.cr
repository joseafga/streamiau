require "uuid"

module Streamiau::Routes::API::V1
  class Counter < Moongoon::Collection
    collection "counters"
    reference username, model: Streamiau::User, delete_cascade: true

    private class_getter cache = Streamiau::Cache({String, String}, Counter).new(expires_in: 1.hours)
    property username : String
    property uuid : String = UUID.random.to_s
    property value : Int32 = 0
    property metadata : Metadata?

    @[JSON::Field(ignore: true)]
    @[BSON::Field(ignore: true)]
    getter clients = Clients.new

    @[JSON::Field(ignore: true)]
    @[BSON::Field(ignore: true)]
    @persister : Persister?

    index keys: {username: 1, uuid: 1}, options: {unique: true}

    after_insert do |counter|
      @@cache.set({counter.username, counter.uuid}, counter)
    end

    after_remove do |counter|
      counter.terminate
    end

    private def persister : Persister
      @persister ||= Persister.new("#{@username}/#{@uuid}") { persist }
    end

    # Write counter changes
    private def persist
      update
    rescue Moongoon::Error::NotFound
      Log.warn { "Counter #{@username}/#{@uuid} no longer exists." }
      terminate
    end

    # The counter is gone: drop it from the cache and close clients, they get a close,
    # and on reconnect get a "not found".
    def terminate : Nil
      @@cache.delete({@username, @uuid})
      @clients.drop_all
    end

    # Check if clients still connected
    def check_health : Nil
      @clients.check_health
      @@cache.touch({@username, @uuid}) unless @clients.empty?
    end

    def set(other : Int32, metadata : Metadata? = nil) : Int32
      return other if @value == other && metadata.nil?

      @value = other
      @metadata = metadata
      message = CounterMessage.new(other, metadata)

      @@cache.touch({@username, @uuid}) # refresh the TTL
      persister.touch
      @clients.broadcast(message.to_json)

      other
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

    # Get `Counter` from the cache, or load it from the DB.
    def self.get(username : String, uuid : String)
      @@cache.fetch({username, uuid}) do
        Counter.find_one!({username: username, uuid: uuid})
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
      haltf(env, 200, "Não encontrado.") # StreamElements only shows 200's messages
    rescue ex : Exception
      Log.error(exception: ex) { "Counter command failed" }
      haltf(env, 200, ex.message.try(&.[..128])) # StreamElements only shows 200's messages
    end

    def self.websocket(socket, env)
      username = env.params.url["username"].as(String)
      uuid = env.params.url["uuid"].as(String)
      counter = Counter.get(username, uuid)
      user = User.get_by_username(username)
      ip = env.request.remote_address.as?(Socket::IPAddress).try(&.address) || "unknown"

      # Handle healthy connections: drop it if there is no pong is received.
      socket.on_pong do
        socket.alive = true
      end

      # Handle incoming messages from clients
      socket.on_message do |incoming|
        Log.debug { "WebSocket(#{ip}) received: #{incoming}" }
        message = CounterMessage.from_json(incoming)

        if token = message.token
          unless user.token_verify?(:web_socket, token)
            Log.warn { "WebSocket(#{ip}) unauthorized, closing..." }
            counter.clients.drop(socket, 1008, "Unauthorized.")
            next
          end

          counter.set(message.value, message.metadata)
        end
      rescue ex
        Log.error { "WebSocket(#{ip}) message with error: #{ex.message}" }
      end

      # Handle client disconnection
      socket.on_close do
        Log.info { "WebSocket(#{ip}) Closing..." }
        counter.clients.remove(socket)
      end

      counter.clients.add(socket) { CounterMessage.new(counter.value, counter.metadata).to_json } # send current value
      Log.info { "WebSocket(#{ip}) connected." }
    rescue ex
      Log.warn { "WebSocket rejected: #{ex.message}" }
      socket.close(1008, "Invalid Socket.") rescue nil
    end

    # All sockets start `alive`, when ping is send socket become `dead`, pong response
    # set as `alive` again. A failure in one counter never affects the others.
    def self.sweep : Nil
      @@cache.items.each do |_key, item|
        item[0].check_health
      rescue ex
        Log.error { "Janitor failed for counter: #{ex.message}" }
      end
    end

    # Janitor fiber
    spawn(name: "counter-janitor") do
      loop do
        sleep 30.seconds
        sweep
      rescue ex
        Log.error { "Janitor pass failed: #{ex.message}" }
      end
    end

    # Debounced write-behind. `touch` says "something changed" and makes sure a fiber is
    # waiting to save it: the fiber exists only while there is something to save and ends
    # by itself when idle, so there is no channel/signal and nothing can be left waiting
    # on a fiber that is gone. Knows nothing about counters: it just calls `save`.
    class Persister
      DEBOUNCE    = 1.second
      MAX_WAIT    = 10.seconds
      MAX_RETRIES = 3

      def initialize(@name : String, &@save)
        @version = 0_i64 # bumped on every change
        @running = false # `true` while the fiber is alive
      end

      def running? : Bool
        @running
      end

      def touch : Nil
        @version += 1
        return if @running

        @running = true
        spawn(name: "counter-#{@name}") { run }
      end

      private def run : Nil
        failures = 0
        waited = Time::Span.zero

        loop do
          last = @version
          sleep DEBOUNCE
          waited += DEBOUNCE

          next if @version != last && waited < MAX_WAIT
          saved = @version

          begin
            @save.call
            failures = 0
            waited = Time::Span.zero
          rescue ex
            failures += 1
            Log.error(exception: ex) { "Failed to persist #{@name}" }

            if failures >= MAX_RETRIES
              Log.error { "Giving up persisting #{@name}, will retry on next change" }
              break
            end

            next
          end

          # If nothing new arrived while saving... done.
          break if @version == saved
        end
      rescue ex
        Log.error(exception: ex) { "Persister crashed for #{@name}" }
      ensure
        @running = false
      end
    end

    # The connected websockets: list, ordered broadcast and health check. Knows nothing
    # about counters, it only moves strings to sockets.
    class Clients
      def initialize
        @sockets = [] of HTTP::WebSocket
        @lock = Mutex.new
      end

      def empty? : Bool
        @sockets.empty?
      end

      # Sends the welcome message and only then registers the socket
      def add(socket, & : -> String) : Nil
        @lock.synchronize do
          socket.send(yield)
          @sockets << socket
        end
      end

      def remove(socket) : Nil
        @sockets.delete(socket)
      end

      def drop(socket, code : Int32 = 1001, message : String = "Going Away.") : Nil
        remove(socket)
        socket.close(code, message) rescue nil
      end

      def drop_all : Nil
        @sockets.dup.each { |socket| drop(socket) }
      end

      # A broken socket must not prevent the others from receiving the message.
      def broadcast(payload : String) : Nil
        Log.debug { "Broadcasting -> #{payload}" }

        # Without the lock, another fiber's broadcast could overtake this one and some
        # clients would get an older value.
        @lock.synchronize do
          # Duplicate to keep state on memory, maybe socket close before send message.
          @sockets.dup.each do |socket|
            socket.send payload
          rescue ex
            Log.warn { "Broadcasting failed: #{ex.message}" }
            drop(socket)
          end
        end
      end

      # All sockets start `alive`, when ping is send socket become `dead`, pong response
      # set as `alive` again.
      def check_health : Nil
        @sockets.reject!(&.closed?)

        @sockets.dup.each do |socket|
          unless socket.alive?
            drop(socket)
            next
          end

          socket.alive = false

          begin
            socket.ping
          rescue
            drop(socket)
          end
        end
      end
    end
  end
end
