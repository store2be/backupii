# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Cleaner do
    let(:model) { Model.new(:test_trigger, "test label") }

    describe "#prepare" do
      let(:error_tail) do
        <<-EOS.gsub(%r{^ +}, "  ")

          Please check the log for messages and/or your notifications
          concerning this backup: 'test label (test_trigger)'
          The temporary files which had to be removed should not have existed.
        EOS
      end

      context "when no temporary packaging folder or package files exist" do
        it "does nothing" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(false)

          expect(Cleaner).to receive(:package_files_for).with("test_trigger").and_return([])

          expect(FileUtils).to receive(:rm_rf).never
          expect(FileUtils).to receive(:rm_f).never
          expect(Logger).to receive(:warn).never

          Cleaner.prepare(model)
        end
      end

      context "when a temporary packaging folder exists" do
        it "removes the folder and logs a warning" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(true)

          expect(Cleaner).to receive(:package_files_for).with("test_trigger").and_return([])

          expect(FileUtils).to receive(:rm_rf)
            .with(File.join(Config.tmp_path, "test_trigger"))

          expect(FileUtils).to receive(:rm_f).never

          expect(Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of Cleaner::Error
            expect(err.message).to eq(<<-EOS.gsub(%r{^ +}, "  ").strip)
              Cleaner::Error: Cleanup Warning
              The temporary packaging folder still exists!
              '#{File.join(Config.tmp_path, "test_trigger")}'
              It will now be removed.
              #{error_tail}
            EOS
          end

          Cleaner.prepare(model)
        end
      end

      context "when package files exist" do
        it "removes the files and logs a warning" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(false)

          expect(Cleaner).to receive(:package_files_for)
            .with("test_trigger")
            .and_return(%w[file1 file2])

          expect(FileUtils).to receive(:rm_rf).never
          expect(FileUtils).to receive(:rm_f).with("file1")
          expect(FileUtils).to receive(:rm_f).with("file2")

          expect(Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of Cleaner::Error
            expect(err.message).to eq(<<-EOS.gsub(%r{^ +}, "  ").strip)
              Cleaner::Error: Cleanup Warning
              The temporary backup folder '#{Config.tmp_path}'
              appears to contain the package files from the previous backup!
              file1
              file2
              These files will now be removed.
              #{error_tail}
            EOS
          end

          Cleaner.prepare(model)
        end
      end

      context "when both the temporary packaging folder and package files exist" do
        it "removes both and logs a warning" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(true)

          expect(Cleaner).to receive(:package_files_for)
            .with("test_trigger")
            .and_return(%w[file1 file2])

          expect(FileUtils).to receive(:rm_rf)
            .with(File.join(Config.tmp_path, "test_trigger"))

          expect(FileUtils).to receive(:rm_f).with("file1")
          expect(FileUtils).to receive(:rm_f).with("file2")

          expect(Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of Cleaner::Error
            expect(err.message).to eq(<<-EOS.gsub(%r{^ +}, "  ").strip)
              Cleaner::Error: Cleanup Warning
              The temporary packaging folder still exists!
              '#{File.join(Config.tmp_path, "test_trigger")}'
              It will now be removed.
              #{"\n  #{"-" * 74}"}
              The temporary backup folder '#{Config.tmp_path}'
              appears to contain the package files from the previous backup!
              file1
              file2
              These files will now be removed.
              #{error_tail}
            EOS
          end

          Cleaner.prepare(model)
        end
      end
    end # describe '#prepare'

    describe "#remove_packaging" do
      it "removes the packaging directory" do
        expect(Logger).to receive(:info).with("Cleaning up the temporary files...")
        expect(FileUtils).to receive(:rm_rf)
          .with(File.join(Config.tmp_path, "test_trigger"))
        Cleaner.remove_packaging(model)
      end
    end

    describe "#remove_package" do
      it "removes the package files" do
        package = double(Backup::Package, filenames: %w[file1 file2])
        expect(Backup::Logger).to receive(:info).with("Cleaning up the package files...")
        expect(FileUtils).to receive(:rm_f).with(File.join(Config.tmp_path, "file1"))
        expect(FileUtils).to receive(:rm_f).with(File.join(Config.tmp_path, "file2"))
        Cleaner.remove_package(package)
      end
    end

    describe "#warnings" do
      let(:error_tail) do
        <<-EOS.gsub(%r{^ +}, "  ")

          Make sure you check these files before the next scheduled backup for
          'test label (test_trigger)'
          These files will be removed at that time!
        EOS
      end

      context "when no temporary packaging folder or package files exist" do
        it "does nothing" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(false)

          expect(Cleaner).to receive(:package_files_for).with("test_trigger").and_return([])

          expect(Logger).to receive(:warn).never

          Cleaner.warnings(model)
        end
      end

      context "when a temporary packaging folder exists" do
        it "logs a warning" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(true)

          expect(Cleaner).to receive(:package_files_for).with("test_trigger").and_return([])

          expect(Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of Cleaner::Error
            expect(err.message).to eq(<<-EOS.gsub(%r{^ +}, "  ").strip)
              Cleaner::Error: Cleanup Warning
              The temporary packaging folder still exists!
              '#{File.join(Config.tmp_path, "test_trigger")}'
              This folder may contain completed Archives and/or Database backups.
              #{error_tail}
            EOS
          end

          Cleaner.warnings(model)
        end
      end

      context "when package files exist" do
        it "logs a warning" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(false)

          expect(Cleaner).to receive(:package_files_for)
            .with("test_trigger")
            .and_return(%w[file1 file2])

          expect(Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of Cleaner::Error
            expect(err.message).to eq(<<-EOS.gsub(%r{^ +}, "  ").strip)
              Cleaner::Error: Cleanup Warning
              The temporary backup folder '#{Config.tmp_path}'
              appears to contain the backup files which were to be stored:
              file1
              file2
              #{error_tail}
            EOS
          end

          Cleaner.warnings(model)
        end
      end

      context "when both the temporary packaging folder and package files exist" do
        it "logs a warning" do
          expect(File).to receive(:exist?)
            .with(File.join(Config.tmp_path, "test_trigger"))
            .and_return(true)

          expect(Cleaner).to receive(:package_files_for)
            .with("test_trigger")
            .and_return(%w[file1 file2])

          expect(Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of Cleaner::Error
            expect(err.message).to eq(<<-EOS.gsub(%r{^ +}, "  ").strip)
              Cleaner::Error: Cleanup Warning
              The temporary packaging folder still exists!
              '#{File.join(Config.tmp_path, "test_trigger")}'
              This folder may contain completed Archives and/or Database backups.
              #{"\n  #{"-" * 74}"}
              The temporary backup folder '#{Config.tmp_path}'
              appears to contain the backup files which were to be stored:
              file1
              file2
              #{error_tail}
            EOS
          end

          Cleaner.warnings(model)
        end
      end
    end # describe '#warnings'

    describe "#package_files_for" do
      before do
        @tmpdir = Dir.mktmpdir("backup_spec")
        SandboxFileUtils.activate!(@tmpdir)
        Config.send(:update, root_path: @tmpdir)
        FileUtils.mkdir_p(Config.tmp_path)
      end

      after { FileUtils.rm_r(@tmpdir, force: true, secure: true) }

      context "when package files exist" do
        it "returns the package files for the given trigger" do
          package_files = [
            "test_trigger.tar",
            "test_trigger.tar-aa",
            "test_trigger.tar.enc",
            "test_trigger.tar.enc-aa"
          ].map { |f| File.join(Config.tmp_path, f) }

          other_files = [
            "test_trigger.target.tar",
            "other_trigger.tar",
            "foo.tar"
          ].map { |f| File.join(Config.tmp_path, f) }

          FileUtils.touch(package_files + other_files)
          expect(Dir[File.join(Config.tmp_path, "*")].count).to eq 7

          expect(Cleaner.send(:package_files_for, "test_trigger").sort)
            .to eq package_files
        end
      end

      context "when no packaging files exist" do
        it "returns an empty array" do
          other_files = [
            "test_trigger.target.tar",
            "other_trigger.tar",
            "foo.tar"
          ].map { |f| File.join(Config.tmp_path, f) }

          FileUtils.touch(other_files)
          expect(Dir[File.join(Config.tmp_path, "*")].count).to be 3

          expect(Cleaner.send(:package_files_for, "test_trigger")).to eq []
        end
      end
    end # describe '#package_files_for'
  end
end
