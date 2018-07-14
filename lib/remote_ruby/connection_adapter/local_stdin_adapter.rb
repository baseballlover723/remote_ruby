require 'open3'

module RemoteRuby
  # An adapter to expecute Ruby code on the local macine
  # inside a specified directory
  class LocalStdinAdapter < ConnectionAdapter
    attr_reader :working_dir

    def initialize(working_dir: '.')
      @working_dir = working_dir
    end

    def connection_name
      working_dir
    end

    def open
      result = nil

      Open3.popen3('ruby', chdir: working_dir) do |stdin, stdout, stderr, wait_thr|
        yield stdin, stdout, stderr
        result = wait_thr.value
      end

      return if result.success?
      raise "Remote connection exited with code #{result}"
    end
  end
end
