# frozen_string_literal: true

require "rubygems" if RUBY_VERSION < "1.9"
require "bundler/setup"
require "backup"

require "timecop"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module Backup
  module ExampleHelpers
    # ripped from MiniTest :)
    # RSpec doesn't have a method for this? Am I missing something?
    def capture_io
      require "stringio"

      orig_stdout = $stdout
      orig_stderr = $stderr
      captured_stdout = StringIO.new
      captured_stderr = StringIO.new
      $stdout = captured_stdout
      $stderr = captured_stderr

      yield

      [captured_stdout.string, captured_stderr.string]
    ensure
      $stdout = orig_stdout
      $stderr = orig_stderr
    end
  end
end

RSpec.configure do |config|
  ##
  # Example Helpers
  config.include Backup::ExampleHelpers

  config.filter_run focus: true
  config.run_all_when_everything_filtered = true

  config.before(:suite) do
    # Initializes SandboxFileUtils so the first call to deactivate!(:noop)
    # will set ::FileUtils to FileUtils::NoWrite
    SandboxFileUtils.activate!
  end

  config.before(:example) do
    # ::FileUtils will always be either SandboxFileUtils or FileUtils::NoWrite.
    SandboxFileUtils.deactivate!(:noop)

    # prevent system calls
    allow(Backup::Utilities).to receive(:gnu_tar?).and_return(true)
    allow(Backup::Utilities).to receive(:utility)
    allow(Backup::Utilities).to receive(:run)
    allow_any_instance_of(Backup::Pipeline).to receive(:run)

    Backup::Utilities.send(:reset!)
    Backup::Config.send(:reset!)
    # Logger only queues messages received until Logger.start! is called.
    Backup::Logger.send(:reset!)
  end
end

puts "\nRuby version: #{RUBY_DESCRIPTION}\n\n"
