require "lru-cache"

module Streamiau
  # Added global expires option, log and fetch
  class Cache(K, V) < LRUCache(K, V)
    def initialize(*, @max_size : Int32? = nil, @expires_in : Time::Span? = nil)
      @items = {} of K => {V, Time?}
    end

    def set(key : K, item : Tuple(V, Time?)) : Cache
      @items.delete(key)

      if _max_size = @max_size
        if @items.size >= _max_size
          while @items.size >= _max_size
            deleted_key, deleted_item = @items.shift
            after_delete(deleted_key, deleted_item)
          end
        end
      end

      if item[1].nil? && (_expires_in = @expires_in)
        item = {item[0], Time.utc + _expires_in}
      end

      @items[key] = item
      after_set(key, item)
      self
    end

    def get(key : K) : V?
      Log.debug { "cache read: #{key}." }
      super
    end

    def fetch(key : K, value) : V
      fetch(key) { value }
    end

    # Try to get value or use block to set it
    def fetch(key : K, &) : V
      unless value = get(key)
        value = yield
        set(key, value)
      end

      value
    end

    private def after_set(key : K, item : Tuple(V, Time?))
      Log.debug { "cache set: #{key} -> `#{item[0]}` expires at #{item[1].try(&.to_local)}." }
    end

    private def after_delete(key : K, item : Tuple(V, Time?)?)
      Log.debug { "cache delete: #{key}." }
    end

    private def after_clear
      Log.debug { "cache clear." }
    end
  end
end
