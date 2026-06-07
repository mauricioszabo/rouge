# encoding: utf-8

require 'tempfile'

module Rouge
  # Optional final formatting pass: run Rubocop's autocorrect over the emitted
  # Ruby when Rubocop is available, otherwise return it unchanged.
  module Formatter
    module_function

    def rubocop(source)
      return source unless available?

      Tempfile.create(["rouge", ".rb"]) do |file|
        file.write(source)
        file.flush
        system("rubocop", "-A", "--no-color", file.path,
               out: File::NULL, err: File::NULL)
        return File.read(file.path)
      end
    rescue StandardError
      source
    end

    def available?
      return @available unless @available.nil?

      @available = system("rubocop", "--version", out: File::NULL, err: File::NULL) || false
    end
  end
end

# vim: set sw=2 et cc=80:
