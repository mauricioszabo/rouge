require 'spec_helper'
require 'cursed/nrepl/server'
require 'socket'
require 'timeout'
require 'tmpdir'

describe Cursed::Nrepl::Bencode do
  it "round-trips integers, strings, lists and dicts" do
    value = { "op" => "eval", "n" => 42, "xs" => ["a", "b"], "nested" => { "k" => 1 } }
    io = StringIO.new(described_class.encode(value))
    io.binmode
    decoded = described_class::Decoder.new(io).message
    expect(decoded).to eq("op" => "eval", "n" => 42, "xs" => ["a", "b"],
                          "nested" => { "k" => 1 })
  end

  it "encodes dict keys in sorted order and drops nils" do
    expect(described_class.encode("z" => 1, "a" => 2, "skip" => nil))
      .to eq "d1:ai2e1:zi1ee"
  end
end

describe Cursed::Nrepl::Server do
  around { |ex| Dir.mktmpdir { |d| @dir = d; ex.run } }

  before(:all) { @b = Cursed::Nrepl::Bencode }

  def with_server
    server = described_class.new(config: Cursed::Config.new(@dir), port: 0)
    thread = Thread.new { server.start }
    port = nil
    portfile = File.join(@dir, ".nrepl-port")
    Timeout.timeout(5) { sleep 0.02 until File.exist?(portfile) && (port = File.read(portfile).to_i) > 0 }
    sock = TCPSocket.new("127.0.0.1", port)
    sock.binmode
    yield sock, Cursed::Nrepl::Bencode::Decoder.new(sock)
  ensure
    sock&.close
    thread&.kill
  end

  # Send a request, collect reply messages up to (and including) "done".
  def request(sock, dec, msg)
    sock.write(Cursed::Nrepl::Bencode.encode(msg))
    sock.flush
    msgs = []
    Timeout.timeout(5) do
      loop do
        m = dec.message
        msgs << m
        break if m["status"]&.include?("done")
      end
    end
    msgs
  end

  it "describes its ops" do
    with_server do |sock, dec|
      reply = request(sock, dec, "op" => "describe", "id" => "1").first
      expect(reply["ops"].keys).to include("eval", "clone", "load-file")
    end
  end

  it "clones a session and evaluates expressions in it" do
    with_server do |sock, dec|
      sid = request(sock, dec, "op" => "clone", "id" => "1").first["new-session"]
      expect(sid).to be_a(String)

      msgs = request(sock, dec, "op" => "eval", "id" => "2", "session" => sid, "code" => "(+ 1 2)")
      expect(msgs.map { |m| m["value"] }.compact).to eq ["3"]
      expect(msgs.last["status"]).to include("done")
    end
  end

  it "captures stdout" do
    with_server do |sock, dec|
      sid = request(sock, dec, "op" => "clone", "id" => "1").first["new-session"]
      msgs = request(sock, dec, "op" => "eval", "id" => "2", "session" => sid,
                                "code" => '(println "hello")')
      expect(msgs.map { |m| m["out"] }.compact.join).to include("hello")
    end
  end

  it "load-file then uses the loaded namespace live" do
    File.write(File.join(@dir, "cursed.edn"), '{:source-roots ["."] :output-root "out"}')
    File.write(File.join(@dir, "math.rg"), "(ns ^:module mymath)\n(defn sq [n] (* n n))")
    with_server do |sock, dec|
      sid = request(sock, dec, "op" => "clone", "id" => "1").first["new-session"]
      request(sock, dec, "op" => "load-file", "id" => "2", "session" => sid,
                         "file" => File.read(File.join(@dir, "math.rg")))
      msgs = request(sock, dec, "op" => "eval", "id" => "3", "session" => sid,
                                "code" => "(mymath/sq 9)")
      expect(msgs.map { |m| m["value"] }.compact).to eq ["81"]
    end
  end

  it "reports evaluation errors" do
    with_server do |sock, dec|
      sid = request(sock, dec, "op" => "clone", "id" => "1").first["new-session"]
      msgs = request(sock, dec, "op" => "eval", "id" => "2", "session" => sid, "code" => "(/ 1 0)")
      expect(msgs.last["status"]).to include("eval-error")
      expect(msgs.map { |m| m["ex"] }.compact).to include("ZeroDivisionError")
    end
  end
end

# vim: set sw=2 et cc=80:
