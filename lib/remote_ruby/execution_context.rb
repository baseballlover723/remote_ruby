require 'method_source'
require 'colorize'
require 'digest'
require 'fileutils'

require 'remote_ruby/compiler'
require 'remote_ruby/connection_adapter'
require 'remote_ruby/unmarshaler'
require 'remote_ruby/locals_extractor'
require 'remote_ruby/source_extractor'
require 'remote_ruby/flavour'
require 'remote_ruby/runner'

module RemoteRuby
  # This class is responsible for executing blocks on the remote host with the
  # specified adapters. This is the entrypoint to RemoteRuby logic.
  class ExecutionContext
    def initialize(
      adapter: ::RemoteRuby::SSHStdinAdapter,
      use_cache: false,
      save_cache: false,
      cache_dir: File.join(Dir.pwd, 'cache'),
      out_stream: $stdout,
      err_stream: $stderr,
      **params
    )
      add_flavours(params)
      @use_cache = use_cache
      @save_cache = save_cache
      @cache_dir = cache_dir
      @out_stream = out_stream
      @err_stream = err_stream
      @adapter_klass = adapter
      @params = params

      FileUtils.mkdir_p(@cache_dir)
    end

    def execute(locals = nil, &block)
      if locals.nil?
        extractor =
          ::RemoteRuby::LocalsExtractor.new(block, ignore_types: self.class)
        locals = extractor.locals
      end

      source_extractor = ::RemoteRuby::SourceExtractor.new
      source = source_extractor.extract(&block)

      result = execute_code(source, **locals)

      locals.each do |key, _|
        if result[:locals].key?(key)
          block.binding.local_variable_set(key, result[:locals][key])
        end
      end

      result[:result]
    end

    private

    def context_hash(code_hash)
      Digest::MD5.hexdigest(
        self.class.name +
        adapter_klass.name.to_s +
        params.to_s +
        code_hash
      )
    end

    def cache_path(code_hash)
      hsh = context_hash(code_hash)
      File.join(cache_dir, hsh)
    end

    def cache_exists?(code_hash)
      hsh = cache_path(code_hash)
      File.exist?("#{hsh}.stdout") || File.exist?("#{hsh}.stderr")
    end

    def execute_code(ruby_code, client_locals = {})
      compiler = RemoteRuby::Compiler.new(
        ruby_code,
        client_locals: client_locals,
        ignore_types: self.class,
        flavours: flavours
      )

      runner = ::RemoteRuby::Runner.new(
        code: compiler.compile,
        adapter: adapter(compiler.code_hash),
        out_stream: out_stream,
        err_stream: err_stream
      )

      runner.run
    end

    def adapter(code_hash)
      if use_cache && cache_exists?(code_hash)
        cache_adapter(code_hash)
      elsif save_cache
        caching_adapter(code_hash)
      else
        adapter_klass.new(params)
      end
    end

    def cache_adapter(code_hash)
      ::RemoteRuby::CacheAdapter.new(
        connection_name: adapter.connection_name,
        cache_path: cache_path(code_hash)
      )
    end

    def caching_adapter(code_hash)
      ::RemoteRuby::CachingAdapter.new(
        adapter: adapter_klass.new(params),
        cache_path: cache_path(code_hash)
      )
    end

    def add_flavours(params)
      @flavours = ::RemoteRuby::Flavour.build_flavours(params)
    end

    attr_reader :params, :adapter_klass, :use_cache, :save_cache, :cache_dir,
                :out_stream, :err_stream, :flavours
  end
end
