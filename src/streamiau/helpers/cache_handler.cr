module Streamiau
  # Cache Handler based on [valenciaj/kemal-cache-basic](https://github.com/valenciaj/kemal-cache-basic).
  class CacheHandler < Kemal::Handler
    CACHEABLE_METHODS = {"GET"}

    def initialize(**kwargs)
      @cache = Cache(String, CacheResponse).new(**kwargs)
    end

    def call(context)
      unless CACHEABLE_METHODS.includes?(context.request.method)
        return call_next(context)
      end

      key = "#{context.request.method}:#{context.request.resource}"

      if cached = @cache.get(key)
        cached.content_type.try { |type| context.response.content_type = type }
        context.response.status_code = cached.status_code
        context.response.write cached.body
        return
      end

      output = context.response.output
      buffer = IO::Memory.new
      context.response.output = CacheIO.new(output, buffer)

      begin
        # Continue request
        call_next context
        # rescue ex : Kemal::Exceptions::CustomException # cache errors?
      ensure
        context.response.output = output
      end

      # Caching...
      @cache.set(key, CacheResponse.new(
        buffer.to_slice,
        context.response.status_code,
        context.response.content_type
      ))
    end

    class CacheIO < IO
      def initialize(@source : IO, @buffer : IO)
      end

      def read(slice : Bytes) : Int32
        @source.read(slice)
      end

      def write(slice : Bytes) : Nil
        @source.write(slice)
        @buffer.write(slice)
      end

      def flush
        @source.flush
        @buffer.flush
      end

      def close
        return if closed?
        super

        @source.close
        @buffer.close
      end

      # Keep source as default behavior
      forward_missing_to @source
    end

    record CacheResponse, body : Bytes, status_code : Int32, content_type : String?
  end
end
