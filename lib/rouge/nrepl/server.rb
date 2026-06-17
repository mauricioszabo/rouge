# encoding: utf-8

require 'socket'
require 'stringio'
require 'securerandom'
require 'rouge/nrepl/bencode'

module Rouge
  module Nrepl
    # A bencode nREPL server wrapping the Rouge +Interpreter+.  Each cloned
    # session gets its own Interpreter (its own Env, binding and :dev Loader), so
    # macros/defs/requires are isolated per session.  Speaks enough of the
    # protocol for CIDER/Calva: +clone+, +close+, +describe+, +eval+, +load-file+.
    #
    # Evals are serialized (one global mutex) because output capture swaps the
    # global +$stdout+/+$stderr+ — a known first-cut limitation.
    class Server
      OPS = %w[clone close describe eval load-file].freeze

      def initialize(config: nil, host: "127.0.0.1", port: 7888)
        @config = config || Rouge::Config.load
        @host = host
        @port = port
        @sessions = {}
        @mutex = Mutex.new
      end

      def start
        server = TCPServer.new(@host, @port)
        actual = server.addr[1]
        write_port_file(actual)
        warn "Rouge nREPL server started on #{@host}:#{actual}"
        loop do
          client = server.accept
          Thread.new(client) { |c| serve(c) }
        end
      end

      private

      def serve(client)
        client.binmode
        decoder = Bencode::Decoder.new(client)
        loop { handle(decoder.message, client) }
      rescue EOFError, IOError, Errno::ECONNRESET
        # client disconnected
      ensure
        client.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def handle(msg, client)
        case msg["op"]
        when "clone"     then op_clone(msg, client)
        when "close"     then op_close(msg, client)
        when "describe"  then op_describe(msg, client)
        when "eval"      then op_eval(msg, client)
        when "load-file" then op_load_file(msg, client)
        else respond(client, reply(msg, "status" => ["done", "unknown-op"]))
        end
      end

      # ---- ops --------------------------------------------------------------

      def op_clone(msg, client)
        id = SecureRandom.uuid
        @sessions[id] = Rouge::Interpreter.new(config: @config)
        respond(client, reply(msg, "new-session" => id, "status" => ["done"]))
      end

      def op_close(msg, client)
        @sessions.delete(msg["session"])
        respond(client, reply(msg, "status" => ["done"]))
      end

      def op_describe(msg, client)
        respond(client, reply(msg,
                           "ops" => OPS.to_h { |o| [o, {}] },
                           "versions" => { "rouge" => { "version-string" => Rouge::VERSION } },
                           "status" => ["done"]))
      end

      def op_eval(msg, client)
        run_eval(msg, client) do |interp|
          Rouge::Reader.read_all(msg["code"].to_s).each do |form|
            value = interp.eval_form(form)
            respond(client, reply(msg, "value" => pr_str(value)))
          end
        end
      end

      def op_load_file(msg, client)
        run_eval(msg, client) do |interp|
          value = interp.eval_str(msg["file"].to_s)
          respond(client, reply(msg, "value" => pr_str(value)))
        end
      end

      # ---- helpers ----------------------------------------------------------

      def run_eval(msg, client)
        interp = session_for(msg)
        @mutex.synchronize do
          with_captured_io(msg, client) { yield interp }
        end
        respond(client, reply(msg, "status" => ["done"]))
      rescue StandardError => e
        respond(client, reply(msg,
                           "ex" => e.class.name,
                           "err" => "#{e.class}: #{e.message}\n",
                           "status" => ["eval-error", "done"]))
      end

      def with_captured_io(msg, client)
        prev_out = $stdout
        prev_err = $stderr
        out = StringIO.new
        err = StringIO.new
        $stdout = out
        $stderr = err
        yield
      ensure
        $stdout = prev_out
        $stderr = prev_err
        respond(client, reply(msg, "out" => out.string)) unless out.string.empty?
        respond(client, reply(msg, "err" => err.string)) unless err.string.empty?
      end

      def session_for(msg)
        sid = msg["session"]
        @sessions[sid] ||= Rouge::Interpreter.new(config: @config)
      end

      def reply(msg, fields)
        base = {}
        base["id"] = msg["id"] if msg["id"]
        base["session"] = msg["session"] if msg["session"]
        base.merge(fields)
      end

      def pr_str(value)
        value.inspect
      end

      def respond(client, msg)
        client.write(Bencode.encode(msg))
        client.flush
      end

      def write_port_file(port)
        File.write(File.join(@config.root, ".nrepl-port"), port.to_s)
      rescue StandardError
        nil
      end
    end
  end
end

# vim: set sw=2 et cc=80:
