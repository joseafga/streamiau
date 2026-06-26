module Streamiau
  # Cache Handler based on [valenciaj/kemal-cache-basic](https://github.com/valenciaj/kemal-cache-basic).
  # Changed to use `crystal-cache/cache`, store content-type and status code
  class CacheHandler < Kemal::Handler
    def initialize(expires_in : Time::Span, compress : Bool = true)
      @cache = Cache::MemoryStore(CacheResponse).new(expires_in, compress)
    end

    def call(context)
      if cached = @cache.read(context.request.resource)
        cached.content_type.try { |type| context.response.content_type = type }
        context.response.status_code = cached.status_code
        context.response.write cached.body
      else
        client = context.response.output
        buffer = IO::Memory.new
        context.response.output = IO::MultiWriter.new(context.response.output, buffer)

        # Continue request
        call_next context

        # Caching...
        @cache.write(context.request.resource, CacheResponse.new(
          buffer.to_slice,
          context.response.status_code,
          context.response.content_type
        ))

        client.close
      end
    end

    record CacheResponse, body : Bytes, status_code : Int32, content_type : String?
  end
end
