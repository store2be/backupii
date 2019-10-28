# frozen_string_literal: true

module BackupSpec
  class PerformedJob
    attr_reader :model, :logger, :package
    def initialize(model)
      @model = model
      @logger = Backup::Logger.saved.shift
      @package = Package.new(model)
    end
  end
end
