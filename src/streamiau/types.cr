module Streamiau
  class User < Moongoon::Collection
    enum Role
      Admin
      Streamer
      Member
      Guest

      def to_bson
        value
      end
    end

    class Token < Moongoon::Document
      enum Type
        WebSocket
        Phrases
        Counter

        def to_bson
          value
        end
      end
    end
  end

  # Counter WebSocket messages
  class Routes::API::V1::Counter < Moongoon::Collection
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
  end
end
