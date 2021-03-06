module RemoteRuby
  # Base class for Flavours: addons to execution context to insert additonal
  # code to the generated remote code.
  class Flavour
    def self.build_flavours(params = {})
      res = []

      {
        rails: RemoteRuby::RailsFlavour
      }.each do |name, klass|
        options = params.delete(name)

        res << klass.new(**options) if options
      end

      res
    end

    def initialize(params: {}); end

    def code_header; end
  end
end

require 'remote_ruby/flavour/rails_flavour'
