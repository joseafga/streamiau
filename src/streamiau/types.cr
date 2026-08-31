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
end
