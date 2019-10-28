# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Storage::RSync do
    let(:model) { Model.new(:test_trigger, "test label") }
    let(:storage) { Storage::RSync.new(model) }
    let(:s) { sequence "" }

    before do
      allow_any_instance_of(Storage::RSync).to \
        receive(:utility).with(:rsync).and_return("rsync")
      allow_any_instance_of(Storage::RSync).to \
        receive(:utility).with(:ssh).and_return("ssh")
    end

    it_behaves_like "a class that includes Config::Helpers"
    it_behaves_like "a subclass of Storage::Base"

    describe "#initialize" do
      it "provides default values" do
        expect(storage.storage_id).to be_nil
        expect(storage.mode).to eq :ssh
        expect(storage.host).to be_nil
        expect(storage.port).to be 22
        expect(storage.ssh_user).to be_nil
        expect(storage.rsync_user).to be_nil
        expect(storage.rsync_password).to be_nil
        expect(storage.rsync_password_file).to be_nil
        expect(storage.compress).to be(false)
        expect(storage.path).to eq "~/backups"
        expect(storage.additional_ssh_options).to be_nil
        expect(storage.additional_rsync_options).to be_nil

        # this storage doesn't support cycling, but `keep` is still inherited
        expect(storage.keep).to be_nil
      end

      it "configures the storage" do
        storage = Storage::RSync.new(model, :my_id) do |rsync|
          rsync.mode                      = :valid_mode
          rsync.host                      = "123.45.678.90"
          rsync.port                      = 123
          rsync.ssh_user                  = "ssh_username"
          rsync.rsync_user                = "rsync_username"
          rsync.rsync_password            = "rsync_password"
          rsync.rsync_password_file       = "/my/rsync_password"
          rsync.compress                  = true
          rsync.path                      = "~/my_backups/"
          rsync.additional_ssh_options    = "ssh options"
          rsync.additional_rsync_options  = "rsync options"
        end

        expect(storage.storage_id).to eq "my_id"
        expect(storage.mode).to eq :valid_mode
        expect(storage.host).to eq "123.45.678.90"
        expect(storage.port).to be 123
        expect(storage.ssh_user).to eq "ssh_username"
        expect(storage.rsync_user).to eq "rsync_username"
        expect(storage.rsync_password).to eq "rsync_password"
        expect(storage.rsync_password_file).to eq "/my/rsync_password"
        expect(storage.compress).to be true
        expect(storage.path).to eq "~/my_backups/"
        expect(storage.additional_ssh_options).to eq "ssh options"
        expect(storage.additional_rsync_options).to eq "rsync options"
      end

      it "uses default port 22 for :ssh_daemon mode" do
        storage = Storage::RSync.new(model) do |s|
          s.mode = :ssh_daemon
        end
        expect(storage.mode).to eq :ssh_daemon
        expect(storage.port).to be 22
      end

      it "uses default port 873 for :rsync_daemon mode" do
        storage = Storage::RSync.new(model) do |s|
          s.mode = :rsync_daemon
        end
        expect(storage.mode).to eq :rsync_daemon
        expect(storage.port).to be 873
      end
    end # describe '#initialize'

    describe "#transfer!" do
      let(:package_files) do
        # source paths for package files never change
        ["test_trigger.tar-aa", "test_trigger.tar-ab"].map do |name|
          File.join(Config.tmp_path, name)
        end
      end

      before do
        allow(storage.package).to receive(:filenames).and_return(
          ["test_trigger.tar-aa", "test_trigger.tar-ab"]
        )
      end

      context "local transfer" do
        it "performs transfer with default values" do
          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path
          expect(FileUtils).to receive(:mkdir_p).with(File.expand_path("~/backups"))

          # First Package File
          dest = File.join(File.expand_path("~/backups"), "test_trigger.tar-aa")
          expect(Logger).to receive(:info).ordered.with(
            "Syncing to '#{dest}'..."
          )
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive '#{package_files[0]}' '#{dest}'"
          )

          # Second Package File
          dest = File.join(File.expand_path("~/backups"), "test_trigger.tar-ab")
          expect(Logger).to receive(:info).ordered.with(
            "Syncing to '#{dest}'..."
          )
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive '#{package_files[1]}' '#{dest}'"
          )

          storage.send(:transfer!)
        end

        it "uses given path, storage id and additional_rsync_options" do
          storage = Storage::RSync.new(model, "my storage") do |rsync|
            rsync.path = "/my/backups"
            rsync.additional_rsync_options = ["--arg1", "--arg2"]
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path
          expect(FileUtils).to receive(:mkdir_p).with("/my/backups")

          # First Package File
          dest = "/my/backups/test_trigger.tar-aa"
          expect(Logger).to receive(:info).ordered.with(
            "Syncing to '#{dest}'..."
          )
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --arg1 --arg2 '#{package_files[0]}' '#{dest}'"
          )

          # Second Package File
          dest = "/my/backups/test_trigger.tar-ab"
          expect(Logger).to receive(:info).ordered.with(
            "Syncing to '#{dest}'..."
          )
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --arg1 --arg2 '#{package_files[1]}' '#{dest}'"
          )

          storage.send(:transfer!)
        end
      end # context 'local transfer'

      context "remote transfer in :ssh mode" do
        it "performs the transfer" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.host = "host.name"
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path
          expect(storage).to receive(:run).ordered.with(
            %(ssh -p 22 host.name "mkdir -p 'backups'")
          )

          # First Package File
          dest = "host.name:'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            %(rsync --archive -e "ssh -p 22" '#{package_files[0]}' #{dest})
          )

          # Second Package File
          dest = "host.name:'backups/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            %(rsync --archive -e "ssh -p 22" '#{package_files[1]}' #{dest})
          )

          storage.send(:transfer!)
        end

        it "uses additional options" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.host = "host.name"
            rsync.port = 123
            rsync.ssh_user = "ssh_username"
            rsync.additional_ssh_options = "-i '/my/id_rsa'"
            rsync.compress = true
            rsync.additional_rsync_options = "--opt1"
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path
          expect(storage).to receive(:run).ordered.with(
            "ssh -p 123 -l ssh_username -i '/my/id_rsa' " +
            %(host.name "mkdir -p 'backups'")
          )

          # First Package File
          dest = "host.name:'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " +
            %(-e "ssh -p 123 -l ssh_username -i '/my/id_rsa'" ) +
            "'#{package_files[0]}' #{dest}"
          )

          # Second Package File
          dest = "host.name:'backups/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " +
            %(-e "ssh -p 123 -l ssh_username -i '/my/id_rsa'" ) +
            "'#{package_files[1]}' #{dest}"
          )

          storage.send(:transfer!)
        end
      end # context 'remote transfer in :ssh mode'

      context "remote transfer in :ssh_daemon mode" do
        it "performs the transfer" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :ssh_daemon
            rsync.host = "host.name"
            rsync.path = "module/path"
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path does nothing
          # (a call to #run would be an unexpected expectation)
          expect(FileUtils).to receive(:mkdir_p).never

          # First Package File
          dest = "host.name::'module/path/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            %(rsync --archive -e "ssh -p 22" '#{package_files[0]}' #{dest})
          )

          # Second Package File
          dest = "host.name::'module/path/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            %(rsync --archive -e "ssh -p 22" '#{package_files[1]}' #{dest})
          )

          storage.send(:transfer!)
        end

        it "uses additional options, with password" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :ssh_daemon
            rsync.host = "host.name"
            rsync.port = 123
            rsync.ssh_user = "ssh_username"
            rsync.additional_ssh_options = "-i '/my/id_rsa'"
            rsync.rsync_user = "rsync_username"
            rsync.rsync_password = "secret"
            rsync.compress = true
            rsync.additional_rsync_options = "--opt1"
          end

          # write_password_file
          password_file = double(File, path: "/path/to/password_file")
          expect(Tempfile).to receive(:new).ordered
            .with("backup-rsync-password").and_return(password_file)
          expect(password_file).to receive(:write).ordered.with("secret")
          expect(password_file).to receive(:close).ordered

          # create_remote_path does nothing

          # First Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='/path/to/password_file' " +
            %(-e "ssh -p 123 -l ssh_username -i '/my/id_rsa'" ) +
            "'#{package_files[0]}' #{dest}"
          )

          # Second Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='/path/to/password_file' " +
            %(-e "ssh -p 123 -l ssh_username -i '/my/id_rsa'" ) +
            "'#{package_files[1]}' #{dest}"
          )

          # remove_password_file
          expect(password_file).to receive(:delete).ordered

          storage.send(:transfer!)
        end

        it "ensures temporary password file is removed" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :ssh_daemon
            rsync.host = "host.name"
            rsync.rsync_password = "secret"
          end

          # write_password_file
          password_file = double(File, path: "/path/to/password_file")
          expect(Tempfile).to receive(:new).ordered
            .with("backup-rsync-password").and_return(password_file)
          expect(password_file).to receive(:write).ordered.with("secret")
          expect(password_file).to receive(:close).ordered

          # create_remote_path does nothing

          # First Package File (fails)
          dest = "host.name::'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive " \
            "--password-file='/path/to/password_file' " +
            %(-e "ssh -p 22" ) +
            "'#{package_files[0]}' #{dest}"
          ).and_raise("an error")

          # remove_password_file
          expect(password_file).to receive(:delete).ordered

          expect do
            storage.send(:transfer!)
          end.to raise_error("an error")
        end

        it "uses additional options, with password_file" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :ssh_daemon
            rsync.host = "host.name"
            rsync.port = 123
            rsync.ssh_user = "ssh_username"
            rsync.additional_ssh_options = "-i '/my/id_rsa'"
            rsync.rsync_user = "rsync_username"
            rsync.rsync_password_file = "my/pwd_file"
            rsync.compress = true
            rsync.additional_rsync_options = "--opt1"
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path does nothing

          # First Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='#{File.expand_path("my/pwd_file")}' " +
            %(-e "ssh -p 123 -l ssh_username -i '/my/id_rsa'" ) +
            "'#{package_files[0]}' #{dest}"
          )

          # Second Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='#{File.expand_path("my/pwd_file")}' " +
            %(-e "ssh -p 123 -l ssh_username -i '/my/id_rsa'" ) +
            "'#{package_files[1]}' #{dest}"
          )

          storage.send(:transfer!)
        end
      end # context 'remote transfer in :ssh_daemon mode'

      context "remote transfer in :rsync_daemon mode" do
        it "performs the transfer" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :rsync_daemon
            rsync.host = "host.name"
            rsync.path = "module/path"
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path does nothing

          # First Package File
          dest = "host.name::'module/path/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --port 873 '#{package_files[0]}' #{dest}"
          )

          # Second Package File
          dest = "host.name::'module/path/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --port 873 '#{package_files[1]}' #{dest}"
          )

          storage.send(:transfer!)
        end

        it "uses additional options, with password" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :rsync_daemon
            rsync.host = "host.name"
            rsync.port = 123
            rsync.rsync_user = "rsync_username"
            rsync.rsync_password = "secret"
            rsync.compress = true
            rsync.additional_rsync_options = "--opt1"
          end

          # write_password_file
          password_file = double(File, path: "/path/to/password_file")
          expect(Tempfile).to receive(:new).ordered
            .with("backup-rsync-password").and_return(password_file)
          expect(password_file).to receive(:write).ordered.with("secret")
          expect(password_file).to receive(:close).ordered

          # create_remote_path does nothing

          # First Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='/path/to/password_file' --port 123 " \
            "'#{package_files[0]}' #{dest}"
          )

          # Second Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='/path/to/password_file' --port 123 " \
            "'#{package_files[1]}' #{dest}"
          )

          # remove_password_file!
          expect(password_file).to receive(:delete).ordered

          storage.send(:transfer!)
        end

        it "ensures temporary password file is removed" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :rsync_daemon
            rsync.host = "host.name"
            rsync.rsync_password = "secret"
          end

          # write_password_file
          password_file = double(File, path: "/path/to/password_file")
          expect(Tempfile).to receive(:new).ordered
            .with("backup-rsync-password").and_return(password_file)
          expect(password_file).to receive(:write).ordered.with("secret")
          expect(password_file).to receive(:close).ordered

          # create_remote_path does nothing

          # First Package File (fails)
          dest = "host.name::'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive " \
            "--password-file='/path/to/password_file' --port 873 " \
            "'#{package_files[0]}' #{dest}"
          ).and_raise("an error")

          # remove_password_file
          expect(password_file).to receive(:delete).ordered

          expect do
            storage.send(:transfer!)
          end.to raise_error("an error")
        end

        it "uses additional options, with password_file" do
          storage = Storage::RSync.new(model) do |rsync|
            rsync.mode = :rsync_daemon
            rsync.host = "host.name"
            rsync.port = 123
            rsync.rsync_user = "rsync_username"
            rsync.rsync_password_file = "my/pwd_file"
            rsync.compress = true
            rsync.additional_rsync_options = "--opt1"
          end

          # write_password_file does nothing
          expect(Tempfile).to receive(:new).never

          # create_remote_path does nothing

          # First Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-aa'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='#{File.expand_path("my/pwd_file")}' --port 123 " \
            "'#{package_files[0]}' #{dest}"
          )

          # Second Package File
          dest = "rsync_username@host.name::'backups/test_trigger.tar-ab'"
          expect(storage).to receive(:run).ordered.with(
            "rsync --archive --opt1 --compress " \
            "--password-file='#{File.expand_path("my/pwd_file")}' --port 123 " \
            "'#{package_files[1]}' #{dest}"
          )

          storage.send(:transfer!)
        end
      end # context 'remote transfer in :rsync_daemon mode'
    end # describe '#perform!'
  end
end
