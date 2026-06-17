# encoding: utf-8

module Rouge
  module Nrepl
    # Minimal bencode codec — just the grammar nREPL uses: integers (+i..e+),
    # byte strings (+<len>:<bytes>+), lists (+l..e+) and dictionaries (+d..e+,
    # string keys).  Enough to talk to CIDER/Calva without a gem dependency.
    module Bencode
      module_function

      def encode(obj)
        case obj
        when ::Integer then "i#{obj}e".b
        when ::Symbol  then encode(obj.to_s)
        when ::String  then "#{obj.bytesize}:".b + obj.b
        when ::Array   then "l".b + obj.map { |e| encode(e) }.join.b + "e".b
        when ::Hash
          body = obj.reject { |_, v| v.nil? }
                    .sort_by { |k, _| k.to_s }
                    .map { |k, v| encode(k.to_s) + encode(v) }.join
          "d".b + body.b + "e".b
        when nil then encode("")
        else encode(obj.to_s)
        end
      end

      # Reads complete bencode values off a byte stream (a socket), one message
      # at a time, with a one-byte pushback for lookahead.
      class Decoder
        def initialize(io)
          @io = io
          @peek = nil
        end

        # Read one top-level value (a message dict).  Raises EOFError at stream
        # end.
        def message
          read_value
        end

        private

        def read_value
          b = peek_byte
          raise EOFError, "end of bencode stream" if b.nil?

          case b
          when 0x69            then read_int     # 'i'
          when 0x6C            then read_list    # 'l'
          when 0x64            then read_dict    # 'd'
          when 0x30..0x39      then read_string  # digit
          else raise "invalid bencode byte: #{b}"
          end
        end

        def read_int
          next_byte # 'i'
          digits = +""
          digits << next_byte while peek_byte != 0x65 # 'e'
          next_byte # 'e'
          digits.to_i
        end

        def read_string
          len = +""
          len << next_byte while peek_byte != 0x3A # ':'
          next_byte # ':'
          bytes = Array.new(len.to_i) { next_byte }
          bytes.pack("C*").force_encoding("UTF-8")
        end

        def read_list
          next_byte # 'l'
          arr = []
          arr << read_value while peek_byte != 0x65
          next_byte # 'e'
          arr
        end

        def read_dict
          next_byte # 'd'
          dict = {}
          until peek_byte == 0x65
            key = read_string
            dict[key] = read_value
          end
          next_byte # 'e'
          dict
        end

        def peek_byte
          @peek ||= @io.getbyte
        end

        def next_byte
          if @peek
            b = @peek
            @peek = nil
            b
          else
            @io.getbyte
          end
        end
      end
    end
  end
end

# vim: set sw=2 et cc=80:
