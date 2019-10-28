# frozen_string_literal: true

module BackupSpec
  CONFIG_TEMPLATE = Backup::Template.new.result("cli/config")
  PROJECT_ROOT = "/usr/src/backup"
  LOCAL_STORAGE_PATH = File.join(PROJECT_ROOT, "tmp", "Storage")

  module ExampleHelpers
    # Creates the config.rb file.
    #
    # By default, this will be created as ~/Backup/config.rb,
    # since Backup::Config is reset before each example.
    #
    # If paths will be changed when calling backup_perform(),
    # like --config-file or --root-path, then the full path to
    # the config file must be given here in +config_file+.
    #
    # The config file created here will disable console log output
    # and file logging, but this may be overridden in +text+.
    #
    # Note that the first line in +text+ will set the indent for the text being
    # given and that indent will be removed from all lines in +text+
    #
    # If you don"t intend to change the default config.rb contents or path,
    # you can omit this method from your example. Calling create_model()
    # will call this method if the +config_file+ does not exist.
    def create_config(text = nil, config_file = nil)
      config_file ||= Backup::Config.config_file
      config_path = File.dirname(config_file)

      unless text.to_s.empty?
        indent = text.lines.first.match(%r{^ *})[0].length
        text = text.lines.map { |l| l[indent..-1] }.join
      end
      config = <<-EOS.gsub(%r{^        }, "")
        # encoding: utf-8

        Backup::Utilities.configure do
          # silence the log output produced by the auto-detection
          tar_dist :gnu
        end

        Backup::Logger.configure do
          console.quiet = true
          logfile.enabled = false
        end

        Backup::Storage::Local.defaults do |local|
          local.path = "#{LOCAL_STORAGE_PATH}"
        end

        #{text}

        #{CONFIG_TEMPLATE}
      EOS

      # Create models path, since models are always relative to the config file.
      FileUtils.mkdir_p File.join(config_path, "models")
      File.open(config_file, "w") { |f| f.write config }
    end

    # Creates a model file.
    #
    # Pass +config_file+ if it won"t be at the default path +~/Backup/+.
    #
    # Creates the model as +/models/<trigger>.rb+, relative to the path
    # of +config_file+.
    #
    # Note that the first line in +text+ will set the indent for the text being
    # given and that indent will be removed from all lines in +text+
    def create_model(trigger, text, config_file = nil)
      config_file ||= Backup::Config.config_file
      model_path = File.join(File.dirname(config_file), "models")
      model_file = File.join(model_path, trigger.to_s + ".rb")

      create_config(nil, config_file) unless File.exist?(config_file)

      indent = text.lines.first.match(%r{^ *})[0].length
      text = text.lines.map { |l| l[indent..-1] }.join
      config = <<-EOS.gsub(%r{^        }, "")
        # encoding: utf-8

        #{text}
      EOS

      File.open(model_file, "w") { |f| f.write config }
    end

    # Runs the given trigger(s).
    #
    # Any +options+ given are passed as command line options to the
    # `backup perform` command. These should be given as String arguments.
    # e.g. job = backup_perform :my_backup, "--tmp-path=/tmp"
    #
    # The last argument given for +options+ may be a Hash, which is used
    # as options for this method. If { :exit_status => Integer } is set,
    # this method will rescue SystemExit and assert that the exit status
    # is correct. This allows jobs that log warnings to continue and return
    # the performed job(s).
    #
    # When :focus is added to an example, "--no-quiet" will be appended to
    # +options+ so you can see the log output as the backup is performed.
    def backup_perform(triggers, *options)
      triggers = Array(triggers).map(&:to_s)
      opts = options.last.is_a?(Hash) ? options.pop : {}
      exit_status = opts.delete(:exit_status)
      argv = ["perform", "-t", triggers.join(",")] + options

      # Reset config paths, utility paths and the logger.
      Backup::Config.send(:reset!)
      Backup::Utilities.send(:reset!)
      Backup::Logger.send(:reset!)
      # Ensure multiple runs have different timestamps
      sleep 1 unless Backup::Model.all.empty?
      # Clear previously loaded models and other class instance variables
      Backup::Model.send(:reset!)

      ARGV.replace(argv)

      if exit_status
        expect do
          Backup::CLI.start
        end.to raise_error(SystemExit) { |exit|
          expect(exit.status).to be(exit_status)
        }
      else
        Backup::CLI.start
      end

      models = triggers.map { |t| Backup::Model.find_by_trigger(t).first }
      jobs = models.map { |m| BackupSpec::PerformedJob.new(m) }
      jobs.count > 1 ? jobs : jobs.first
    end
  end
end
