# frozen_string_literal: true

require "spec_helper"

describe Backup::Encryptor::GPG do
  let(:encryptor) do
    Backup::Encryptor::GPG.new do |e|
      e.mode = :symmetric
      e.passphrase = "test secret"
    end
  end

  it "should be a subclass of Encryptor::Base" do
    expect(Backup::Encryptor::GPG
      .superclass).to eq(Backup::Encryptor::Base)
  end

  it "supports three modes of operation" do
    expect(Backup::Encryptor::GPG::MODES).to eq([:asymmetric, :symmetric, :both])
  end

  describe "#mode=" do
    it "should accept valid modes" do
      mode = Backup::Encryptor::GPG::MODES.sample
      encryptor.mode = mode
      expect(encryptor.mode).to eq(mode)
    end

    it "should convert string input to a symbol" do
      mode = Backup::Encryptor::GPG::MODES.sample
      encryptor.mode = mode.to_s
      expect(encryptor.mode).to eq(mode)
    end

    it "should raise an error for invalid modes" do
      expect do
        encryptor.mode = "foo"
      end.to raise_error(Backup::Encryptor::GPG::Error)
    end
  end # describe '#mode='

  describe "#initialize" do
    after { Backup::Encryptor::GPG.clear_defaults! }

    it "should load pre-configured defaults" do
      expect_any_instance_of(Backup::Encryptor::GPG).to receive(:load_defaults!)
      encryptor
    end

    context "when no pre-configured defaults have been set" do
      it "should use the values given" do
        expect(encryptor.mode).to eq(:symmetric)
        expect(encryptor.passphrase).to eq("test secret")
      end

      it "should use default values if none are given" do
        encryptor = Backup::Encryptor::GPG.new
        expect(encryptor.mode).to eq(:asymmetric)
        expect(encryptor.keys).to be_nil
        expect(encryptor.recipients).to be_nil
        expect(encryptor.passphrase).to be_nil
        expect(encryptor.passphrase_file).to be_nil
        expect(encryptor.gpg_config).to be_nil
        expect(encryptor.gpg_homedir).to be_nil
      end
    end # context 'when no pre-configured defaults have been set'

    context "when pre-configured defaults have been set" do
      before do
        Backup::Encryptor::GPG.defaults do |e|
          e.mode = :both
          e.keys = { "test_key" => "test public key" }
          e.recipients = "test_key"
          e.passphrase_file = "my/pass/file"
        end
      end

      it "should use pre-configured defaults" do
        encryptor = Backup::Encryptor::GPG.new
        expect(encryptor.mode).to eq(:both)
        expect(encryptor.keys).to eq("test_key" => "test public key")
        expect(encryptor.recipients).to eq("test_key")
        expect(encryptor.passphrase_file).to eq("my/pass/file")
      end

      it "should override pre-configured defaults" do
        expect(encryptor.mode).to eq(:symmetric)
        expect(encryptor.keys).to eq("test_key" => "test public key")
        expect(encryptor.recipients).to eq("test_key")
        expect(encryptor.passphrase).to eq("test secret")
        expect(encryptor.passphrase_file).to eq("my/pass/file")
      end
    end # context 'when pre-configured defaults have been set'
  end # describe '#initialize'

  describe "#encrypt_with" do
    before do
      expect(encryptor).to receive(:log!)
      expect(encryptor).to receive(:prepare)
      expect(encryptor).to receive(:cleanup) # ensure call
    end

    context "when encryption can be performed" do
      it "should yield the encryption command and extension" do
        expect(encryptor).to receive(:mode_options).twice.and_return("mode_options")
        expect(encryptor).to receive(:base_options).and_return("base_options")
        expect(encryptor).to receive(:utility).with(:gpg).and_return("gpg")

        encryptor.encrypt_with do |command, ext|
          expect(command).to eq("gpg base_options mode_options")
          expect(ext).to eq(".gpg")
        end
      end
    end

    context "when encryption can not be performed" do
      it "should raise an error when no mode_options are returned" do
        expect(encryptor).to receive(:mode_options).and_return([])

        expect do
          encryptor.encrypt_with
        end.to raise_error(Backup::Encryptor::GPG::Error)
      end
    end
  end # describe '#encrypt_with'

  describe "#prepare and #cleanup" do
    it "should setup required variables" do
      encryptor.instance_variable_set(:@tempdirs, nil)
      expect(FileUtils).to receive(:rm_rf).never
      encryptor.send(:prepare)
      expect(encryptor.instance_variable_get(:@tempdirs)).to eq([])
    end

    it "should remove any tempdirs and clear all variables" do
      encryptor.instance_variable_set(:@tempdirs, %w[a b])
      expect(FileUtils).to receive(:rm_rf).with(%w[a b], secure: true)

      encryptor.instance_variable_set(:@base_options, true)
      encryptor.instance_variable_set(:@mode_options, true)
      encryptor.instance_variable_set(:@user_recipients, true)
      encryptor.instance_variable_set(:@user_keys, true)
      encryptor.instance_variable_set(:@system_identifiers, true)

      encryptor.send(:cleanup)

      expect(encryptor.instance_variable_get(:@tempdirs)).to eq([])
      expect(encryptor.instance_variable_get(:@base_options)).to be_nil
      expect(encryptor.instance_variable_get(:@mode_options)).to be_nil
      expect(encryptor.instance_variable_get(:@user_recipients)).to be_nil
      expect(encryptor.instance_variable_get(:@user_keys)).to be_nil
      expect(encryptor.instance_variable_get(:@system_identifiers)).to be_nil
    end
  end # describe '#prepare and #cleanup'

  describe "#base_options" do
    context "while caching the return value in @base_options" do
      before { encryptor.instance_variable_set(:@base_options, nil) }

      context "when #gpg_homedir is given" do
        it "should return the proper options" do
          expect(encryptor).to receive(:setup_gpg_homedir).once.and_return("/a/dir")
          expect(encryptor).to receive(:setup_gpg_config).once.and_return(false)

          ret = "--no-tty --homedir '/a/dir'"
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.instance_variable_get(:@base_options)).to eq(ret)
        end
      end

      context "when #gpg_config is given" do
        it "should return the proper options" do
          expect(encryptor).to receive(:setup_gpg_homedir).once.and_return(false)
          expect(encryptor).to receive(:setup_gpg_config).once.and_return("/a/file")

          ret = "--no-tty --options '/a/file'"
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.instance_variable_get(:@base_options)).to eq(ret)
        end
      end

      context "when #gpg_homedir and #gpg_config is given" do
        it "should return the proper options" do
          expect(encryptor).to receive(:setup_gpg_homedir).once.and_return("/a/dir")
          expect(encryptor).to receive(:setup_gpg_config).once.and_return("/a/file")

          ret = "--no-tty --homedir '/a/dir' --options '/a/file'"
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.instance_variable_get(:@base_options)).to eq(ret)
        end
      end

      context "when neither #gpg_homedir and #gpg_config is given" do
        it "should return the proper options" do
          expect(encryptor).to receive(:setup_gpg_homedir).once.and_return(false)
          expect(encryptor).to receive(:setup_gpg_config).once.and_return(false)

          ret = "--no-tty"
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.send(:base_options)).to eq(ret)
          expect(encryptor.instance_variable_get(:@base_options)).to eq(ret)
        end
      end
    end
  end # describe '#base_options'

  describe "#setup_gpg_homedir" do
    context "when #gpg_homedir is not set" do
      it "should return false" do
        encryptor.gpg_homedir = nil
        expect(encryptor.send(:setup_gpg_homedir)).to eq(false)
      end
    end

    context "when #gpg_homedir is set" do
      let(:path) { "some/path" }
      let(:expanded_path) { File.expand_path(path) }

      before do
        encryptor.gpg_homedir = path
        allow(Backup::Config).to receive(:user).and_return("a_user")
      end

      context "and no errors occur" do
        before do
          expect(FileUtils).to receive(:mkdir_p).with(expanded_path)
          expect(FileUtils).to receive(:chown).with("a_user", nil, expanded_path)
          expect(FileUtils).to receive(:chmod).with(0o700, expanded_path)
        end

        context "and the gpg_homedir files exist" do
          before do
            %w[pubring.gpg secring.gpg trustdb.gpg].each do |file|
              expect(File).to receive(:exist?).with(
                File.join(expanded_path, file)
              ).and_return(true)
            end
          end

          it "should ensure permissions and return the path" do
            expect(encryptor).to receive(:utility).never
            expect(encryptor.send(:setup_gpg_homedir)).to eq(expanded_path)
          end
        end

        context "and the gpg_homedir files do not exist" do
          before do
            allow(File).to receive(:exist?).and_return(false)
          end

          it "should call gpg to initialize the files" do
            expect(encryptor).to receive(:utility).with(:gpg).and_return("gpg")
            expect(encryptor).to receive(:run).with(
              "gpg --homedir '#{expanded_path}' -K 2>&1 >/dev/null"
            )
            expect(encryptor.send(:setup_gpg_homedir)).to eq(expanded_path)
          end
        end
      end

      context "and errors occur" do
        it "should wrap and raise the error" do
          expect(File).to receive(:expand_path).and_raise("error message")

          expect do
            encryptor.send(:setup_gpg_homedir)
          end.to raise_error(proc do |err|
            expect(err).to be_an_instance_of Backup::Encryptor::GPG::Error
            expect(err.message).to match("Failed to create or set permissions")
            expect(err.message).to match("RuntimeError: error message")
          end)
        end
      end
    end
  end # describe '#setup_gpg_homedir'

  describe "#setup_gpg_config" do
    context "when #gpg_config is not set" do
      it "should return false" do
        encryptor.gpg_config = nil
        expect(encryptor.send(:setup_gpg_config)).to eq(false)
      end
    end

    context "when #gpg_config is set" do
      before do
        encryptor.gpg_config = <<-EOF
          # a comment
          text which will be

          \tthe content of a gpg.conf file
        EOF
        allow(Backup::Config).to receive(:tmp_path).and_return("/Backup/tmp")
        encryptor.instance_variable_set(:@tempdirs, [])
      end

      context "when no errors occur" do
        let(:tempdir) { double }
        let(:tempfile) { double }
        let(:tempfile_path) { double }
        let(:path) { double }

        before do
          expect(encryptor).to receive(:cleanup).never
          allow(tempfile).to receive(:path).and_return(tempfile_path)
        end

        it "should create and return the file path" do
          # create temporary directory and convert to a Pathname object
          expect(Dir).to receive(:mktmpdir).with(
            "backup-gpg_config", "/Backup/tmp"
          ).and_return(tempdir)

          # create temporary file within the temporary directory
          expect(Tempfile).to receive(:open).with(
            "backup-gpg_config", tempdir
          ).and_return(tempfile)

          # write the gpg_config, stripping leading tabs/spaces
          expect(tempfile).to receive(:write).with(
            "# a comment\n" \
            "text which will be\n" \
            "\n" \
            "the content of a gpg.conf file\n"
          )
          # close the file
          expect(tempfile).to receive(:close)

          # check the config file
          expect(encryptor).to receive(:check_gpg_config).with(tempfile_path)

          # method returns the tempfile's path
          expect(encryptor.send(:setup_gpg_config)).to eq(tempfile_path)

          # tempdir added to @tempdirs
          expect(encryptor.instance_variable_get(:@tempdirs)[0]).to eq(tempdir)
        end
      end

      context "when errors occur" do
        before do
          expect(encryptor).to receive(:cleanup) # run before the error is raised
        end

        it "should wrap and raise the error" do
          expect(Dir).to receive(:mktmpdir).and_raise("an error")

          expect do
            encryptor.send(:setup_gpg_config)
          end.to raise_error(proc do |err|
            expect(err).to be_an_instance_of(Backup::Encryptor::GPG::Error)
            expect(err.message).to match("Error creating temporary file for #gpg_config")
            expect(err.message).to match("RuntimeError: an error")
          end)
        end
      end
    end
  end # describe '#setup_gpg_config'

  describe "#check_gpg_config" do
    let(:cmd_ret) { double }
    let(:file_path) { "/path/to/tempfile" }

    before do
      expect(encryptor).to receive(:utility).with(:gpg).and_return("gpg")
      expect(encryptor).to receive(:run).with(
        "gpg --options '#{file_path}' --gpgconf-test 2>&1"
      ).and_return(cmd_ret)
    end

    context "when no errors are reported" do
      before { expect(cmd_ret).to receive(:chomp).and_return("") }

      it "should do nothing" do
        expect(encryptor.send(:check_gpg_config, file_path)).to be_nil
      end
    end

    context "when errors are reported" do
      let(:error_message) { "gpg: /path/to/tempfile:1: invalid option" }
      before { expect(cmd_ret).to receive(:chomp).and_return(error_message) }

      it "should raise the error message reported" do
        expect do
          encryptor.send(:check_gpg_config, file_path)
        end.to raise_error(RuntimeError, error_message)
      end
    end
  end # describe '#check_gpg_config'

  describe "#mode_options" do
    let(:s_opts) { "-c --passphrase_file '/some/file'" }
    let(:a_opts) { "-e --trust-model always -r 'identifier'" }

    context "while caching the return value in @mode_options" do
      before { encryptor.instance_variable_set(:@mode_options, nil) }

      context "when #mode is :symmetric" do
        it "should return symmetric encryption options" do
          expect(encryptor).to receive(:symmetric_options).once.and_return(s_opts)
          expect(encryptor).to receive(:asymmetric_options).never

          encryptor.mode = :symmetric
          expect(encryptor.send(:mode_options)).to eq(s_opts)
          expect(encryptor.send(:mode_options)).to eq(s_opts)
          expect(encryptor.instance_variable_get(:@mode_options)).to eq(s_opts)
        end
      end

      context "when #mode is :asymmetric" do
        it "should return asymmetric encryption options" do
          expect(encryptor).to receive(:symmetric_options).never
          expect(encryptor).to receive(:asymmetric_options).once.and_return(a_opts)

          encryptor.mode = :asymmetric
          expect(encryptor.send(:mode_options)).to eq(a_opts)
          expect(encryptor.send(:mode_options)).to eq(a_opts)
          expect(encryptor.instance_variable_get(:@mode_options)).to eq(a_opts)
        end
      end

      context "when #mode is :both" do
        it "should return both symmetric and asymmetric encryption options" do
          expect(encryptor).to receive(:symmetric_options).once.and_return(s_opts)
          expect(encryptor).to receive(:asymmetric_options).once.and_return(a_opts)

          encryptor.mode = :both
          opts = "#{s_opts} #{a_opts}"

          expect(encryptor.send(:mode_options)).to eq(opts)
          expect(encryptor.send(:mode_options)).to eq(opts)
          expect(encryptor.instance_variable_get(:@mode_options)).to eq(opts)
        end
      end
    end
  end # describe '#mode_options'

  describe "#symmetric_options" do
    let(:path) { "/path/to/passphrase/file" }
    let(:s_opts) { "-c --passphrase-file '#{path}'" }

    context "when setup_passphrase_file returns a path" do
      it "should return the options" do
        expect(encryptor).to receive(:setup_passphrase_file).and_return(path)
        expect(File).to receive(:exist?).with(path).and_return(true)

        expect(encryptor.send(:symmetric_options)).to eq(s_opts)
      end
    end

    context "when setup_passphrase_file returns false" do
      before do
        expect(encryptor).to receive(:setup_passphrase_file).and_return(false)
      end

      context "and no :passphrase_file is set" do
        it "should return nil and log a warning" do
          expect(encryptor).to receive(:passphrase_file).and_return(nil)
          expect(Backup::Logger).to receive(:warn)

          expect(encryptor.send(:symmetric_options)).to be_nil
        end
      end

      context "and a :passphrase_file is set" do
        before do
          expect(encryptor).to receive(:passphrase_file).twice.and_return(path)
          expect(File).to receive(:expand_path).with(path).and_return(path)
        end

        context "when :passphrase_file exists" do
          it "should return the options" do
            expect(File).to receive(:exist?).with(path).and_return(true)
            expect(encryptor.send(:symmetric_options)).to eq(s_opts)
          end
        end

        context "when :passphrase_file is no valid" do
          it "should return nil and log a warning" do
            expect(File).to receive(:exist?).with(path).and_return(false)
            expect(Backup::Logger).to receive(:warn)
            expect(encryptor.send(:symmetric_options)).to be_nil
          end
        end
      end
    end
  end # describe '#symmetric_options'

  describe "#setup_passphrase_file" do
    context "when :passphrase is not set" do
      it "should return false" do
        expect(encryptor).to receive(:passphrase).and_return(nil)
        expect(encryptor.send(:setup_passphrase_file)).to eq(false)
      end
    end

    context "when :passphrase is set" do
      let(:tempdir) { double }
      let(:tempfile) { double }
      let(:tempfile_path) { double }

      before do
        encryptor.instance_variable_set(:@tempdirs, [])
        allow(Backup::Config).to receive(:tmp_path).and_return("/Backup/tmp")
        allow(encryptor).to receive(:passphrase).and_return("a secret")
        allow(tempfile).to receive(:path).and_return(tempfile_path)
      end

      context "and no errors occur" do
        it "should return the path for the temp file" do
          # creates temporary directory in Config.tmp_path
          expect(Dir).to receive(:mktmpdir)
            .with("backup-gpg_passphrase", "/Backup/tmp")
            .and_return(tempdir)

          # create the temporary file in that temporary directory
          expect(Tempfile).to receive(:open)
            .with("backup-gpg_passphrase", tempdir)
            .and_return(tempfile)
          expect(tempfile).to receive(:write).with("a secret")
          expect(tempfile).to receive(:close)

          expect(encryptor.send(:setup_passphrase_file)).to eq(tempfile_path)

          # adds the temporary directory to @tempdirs
          expect(encryptor.instance_variable_get(:@tempdirs)[0]).to eq(tempdir)
        end
      end

      context "and an error occurs" do
        it "should return false and log a warning" do
          expect(Dir).to receive(:mktmpdir).and_raise("an error")
          expect(Backup::Logger).to receive(:warn) do |err|
            expect(err).to be_an_instance_of(Backup::Encryptor::GPG::Error)
            expect(err.message).to match("Error creating temporary passphrase file")
            expect(err.message).to match("RuntimeError: an error")
          end
          expect(encryptor.send(:setup_passphrase_file)).to eq(false)
        end
      end
    end
  end # describe '#setup_passphrase_file'

  describe "#asymmetric_options" do
    context "when recipients are found" do
      it "should return the options" do
        allow(encryptor).to receive(:user_recipients).and_return(%w[keyid1 keyid2])
        expect(encryptor.send(:asymmetric_options)).to eq(
          "-e --trust-model always -r 'keyid1' -r 'keyid2'"
        )
      end
    end

    context "when no recipients are found" do
      it "should return nil log a warning" do
        expect(encryptor).to receive(:user_recipients).and_return([])
        expect(Backup::Logger).to receive(:warn)
        expect(encryptor.send(:asymmetric_options)).to be_nil
      end
    end
  end # describe '#asymmetric_options'

  describe "#user_recipients" do
    context "when an Array of :recipients are given" do
      it "should return the recipient list and cache the result" do
        expect(encryptor).to receive(:recipients).and_return(
          %w[key_id1 key_id2 key_id3 key_id4]
        )
        expect(encryptor).to receive(:clean_identifier).with("key_id1").and_return("key_id1")
        expect(encryptor).to receive(:clean_identifier).with("key_id2").and_return("key_id2")
        expect(encryptor).to receive(:clean_identifier).with("key_id3").and_return("key_id3")
        expect(encryptor).to receive(:clean_identifier).with("key_id4").and_return("key_id4")

        # key_id1 and key_id3 will be found in the system
        allow(encryptor).to receive(:system_identifiers).and_return(%w[key_id1 key_id3])

        # key_id2 will be imported (key_id returned)
        allow(encryptor).to receive(:user_keys).and_return("key_id2" => "a public key")
        expect(encryptor).to receive(:import_key)
          .with("key_id2", "a public key")
          .and_return("key_id2")

        # key_id4 will not be found in user_keys, so a warning will be logged.
        # This will return nil into the array, which will be compacted out.
        expect(Backup::Logger).to receive(:warn) do |msg|
          expect(msg).to match(%r{'key_id4'})
        end

        encryptor.instance_variable_set(:@user_recipients, nil)
        recipient_list = %w[key_id1 key_id2 key_id3]
        expect(encryptor.send(:user_recipients)).to eq(recipient_list)
        # results are cached (expectations would fail if called twice)
        expect(encryptor.send(:user_recipients)).to eq(recipient_list)
        expect(encryptor.instance_variable_get(:@user_recipients)).to eq(recipient_list)
      end
    end

    context "when :recipients is a single recipient, given as a String" do
      it "should return the cleaned identifier in an Array" do
        expect(encryptor).to receive(:recipients).and_return("key_id")
        # the key will be found in system_identifiers
        allow(encryptor).to receive(:system_identifiers).and_return(["key_id"])
        expect(encryptor).to receive(:clean_identifier).with("key_id").and_return("key_id")

        expect(encryptor.send(:user_recipients)).to eq(["key_id"])
      end
    end

    context "when :recipients is not set" do
      it "should return an empty Array" do
        expect(encryptor).to receive(:recipients).and_return(nil)
        expect(encryptor.send(:user_recipients)).to eq([])
      end
    end
  end # describe '#user_recipients'

  describe "#user_keys" do
    context "when :keys has been set" do
      before do
        expect(encryptor).to receive(:keys).and_return(
          "key1" => :foo, "key2" => :foo, "key3" => :foo
        )
        encryptor.instance_variable_set(:@user_keys, nil)
      end

      it "should return a new Hash of #keys with cleaned identifiers" do
        expect(encryptor).to receive(:clean_identifier).with("key1").and_return("clean_key1")
        expect(encryptor).to receive(:clean_identifier).with("key2").and_return("clean_key2")
        expect(encryptor).to receive(:clean_identifier).with("key3").and_return("clean_key3")

        expect(Backup::Logger).to receive(:warn).never

        cleaned_hash = {
          "clean_key1" => :foo, "clean_key2" => :foo, "clean_key3" => :foo
        }
        expect(encryptor.send(:user_keys)).to eq(cleaned_hash)
        # results are cached (expectations would fail if called twice)
        expect(encryptor.send(:user_keys)).to eq(cleaned_hash)
        expect(encryptor.instance_variable_get(:@user_keys)).to eq(cleaned_hash)
      end

      it "should log a warning if cleaning results in a duplicate identifier" do
        expect(encryptor).to receive(:clean_identifier).with("key1").and_return("clean_key1")
        expect(encryptor).to receive(:clean_identifier).with("key2").and_return("clean_key2")
        # return a duplicate key
        expect(encryptor).to receive(:clean_identifier).with("key3").and_return("clean_key2")

        expect(Backup::Logger).to receive(:warn)

        cleaned_hash = {
          "clean_key1" => :foo, "clean_key2" => :foo
        }
        expect(encryptor.send(:user_keys)).to eq(cleaned_hash)
        # results are cached (expectations would fail if called twice)
        expect(encryptor.send(:user_keys)).to eq(cleaned_hash)
        expect(encryptor.instance_variable_get(:@user_keys)).to eq(cleaned_hash)
      end
    end

    context "when :keys has not be set" do
      before do
        expect(encryptor).to receive(:keys).and_return(nil)
        encryptor.instance_variable_set(:@user_keys, nil)
      end

      it "should return an empty hash" do
        expect(encryptor.send(:user_keys)).to eq({})
      end
    end
  end # describe '#user_keys'

  describe "#clean_identifier" do
    it "should remove all spaces and upcase non-email identifiers" do
      expect(encryptor.send(:clean_identifier, " 9d66 6290 c5f7 ee0f "))
        .to eq("9D666290C5F7EE0F")
    end

    # Even though spaces in an email are technically possible,
    # GPG won't allow anything but /[A-Za-z0-9_\-.]/
    it "should remove all spaces and wrap email addresses in <>" do
      emails = [
        "\t Foo.Bar@example.com ",
        " < Foo-Bar@example.com\t > ",
        "< <Foo_Bar @\texample.com> >"
      ]
      cleaned = [
        "<Foo.Bar@example.com>",
        "<Foo-Bar@example.com>",
        "<Foo_Bar@example.com>"
      ]

      expect(emails.map do |email|
        encryptor.send(:clean_identifier, email)
      end).to eq(cleaned)
    end
  end # describe '#clean_identifier'

  describe "#import_key" do
    let(:gpg_return_ok) do
      <<-EOS.gsub(%r{^ +}, "")
        gpg: keyring `/tmp/.gnupg/secring.gpg' created
        gpg: keyring `/tmp/.gnupg/pubring.gpg' created
        gpg: /tmp/.gnupg/trustdb.gpg: trustdb created
        gpg: key 0x9D666290C5F7EE0F: public key "Backup Test <backup01@foo.com>" imported
        gpg: Total number processed: 1
        gpg:               imported: 1  (RSA: 1)
      EOS
    end
    let(:gpg_return_failed) do
      <<-EOS.gsub(%r{^ +}, "")
        gpg: no valid OpenPGP data found.
        gpg: Total number processed: 0
      EOS
    end
    let(:gpg_key) do
      <<-EOS
        -----BEGIN PGP PUBLIC KEY BLOCK-----
        Version: GnuPG v1.4.12 (GNU/Linux)

        mI0EUAmiNwEEAKpNP4GVKcjJrTtAh0XKk0NQsId6h/1pzEok2bExkNvD6eSjYRFL
        gXY+pNqaEE6cHrg+uQatVQITX8EoVJhQ9Z1mYJB+g62zqOQPe10Spb381O9y4dN/
        /ge/yL+/+R2CUrKeNF9nSA24+V4mTSqgo7sTnevDzGj4Srzs76MmkpU=
        =TU/B
        -----END PGP PUBLIC KEY BLOCK-----
      EOS
    end
    let(:tempfile) { double }

    before do
      allow(Backup::Config).to receive(:tmp_path).and_return("/tmp/path")
      allow(encryptor).to receive(:base_options).and_return("--some 'base options'")
      allow(encryptor).to receive(:utility).and_return("gpg")
      allow(tempfile).to receive(:path).and_return("/tmp/file/path")
    end

    context "when the import is successful" do
      it "should return the long key ID" do
        expect(Tempfile).to receive(:open)
          .with("backup-gpg_import", "/tmp/path").and_return(tempfile)
        expect(tempfile).to receive(:write).with(<<-EOS)
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.12 (GNU/Linux)

mI0EUAmiNwEEAKpNP4GVKcjJrTtAh0XKk0NQsId6h/1pzEok2bExkNvD6eSjYRFL
gXY+pNqaEE6cHrg+uQatVQITX8EoVJhQ9Z1mYJB+g62zqOQPe10Spb381O9y4dN/
/ge/yL+/+R2CUrKeNF9nSA24+V4mTSqgo7sTnevDzGj4Srzs76MmkpU=
=TU/B
-----END PGP PUBLIC KEY BLOCK-----
        EOS

        expect(tempfile).to receive(:close)

        expect(encryptor).to receive(:run).with(
          "gpg --some 'base options' --keyid-format 0xlong " \
          "--import '/tmp/file/path' 2>&1"
        ).and_return(gpg_return_ok)

        expect(tempfile).to receive(:delete)

        expect(Backup::Logger).to receive(:warn).never

        expect(encryptor.send(:import_key, "some_identifier", gpg_key))
          .to eq("9D666290C5F7EE0F")
      end
    end

    context "when the import is unsuccessful" do
      it "should return nil and log a warning" do
        expect(Tempfile).to receive(:open).and_raise("an error")
        expect(Backup::Logger).to receive(:warn) do |err|
          expect(err).to be_an_instance_of(Backup::Encryptor::GPG::Error)
          expect(err.message).to match("Public key import failed for 'some_identifier'")
          expect(err.message).to match("RuntimeError: an error")
        end

        expect(encryptor.send(:import_key, "some_identifier", "foo")).to be_nil
      end
    end
  end # describe '#import_key'

  describe "#system_identifiers" do
    let(:gpg_output) do
      <<-EOS.gsub(%r{^ +}, "")
        tru::1:1343402941:0:3:1:5
        pub:-:1024:1:5EFD157FFF9CFEA6:1342808803:::-:::scESC:
        fpr:::::::::72E56E48E362BB402B3344045EFD157FFF9CFEA6:
        uid:-::::1342808803::3BED8A0A5100FE9028BEB53610247518594B60A8::Backup Test (No Email):
        sub:-:1024:1:E6CF1DC860A82E07:1342808803::::::e:
        pub:-:1024:1:570CE9221E3DA3E8:1342808841:::-:::scESC:
        fpr:::::::::616BBC8409C1AED791F8E6F8570CE9221E3DA3E8:
        uid:-::::1342808875::ECFF419EFE4BD3C7CBCCD58FACAD283A9E98FECD::Backup Test <backup04@foo.com>:
        uid:-::::1342808841::DDFD072C193BB45587EBA9D19A7DA1BB0E5E8A22::Backup Test <backup03@foo.com>:
        sub:-:1024:1:B65C0ADEB804268D:1342808841::::::e:
        pub:-:1024:1:54F81C93A7641A16:1342809011:::-:::scESC:
        fpr:::::::::71335B9B960CF3A3071535F454F81C93A7641A16:
        uid:-::::1342809011::2E5801E9C064C2A165B61EE35D50A5F9B64BF345::Backup Test (other email is <backup06@foo.com>) <backup05@foo.com>:
        sub:-:1024:1:5B57BC34628252C7:1342809011::::::e:
        pub:-:1024:1:0A5B6CC9581A88CF:1342809049:::-:::scESC:
        fpr:::::::::E8C459082544924B8AEA06280A5B6CC9581A88CF:
        uid:-::::1342809470::4A404F9ED6780E7E0E02A7F7607828E648789058::Backup Test <backup08@foo.com>:
        uid:-::::::9785ADEBBBCE94CE0FF25774F610F2B11C839E9B::Backup Test <backup07@foo.com>:
        uid:r::::::4AD074B1857819EFA105DFB6C464600AA451BF18::Backup Test <backup09@foo.com>:
        sub:e:1024:1:60A420E39B979B06:1342809049:1342895611:::::e:
        sub:-:1024:1:A05786E7AD5B8352:1342809166::::::e:
        pub:i:1024:1:4A83569F4E5E8D8A:1342810132:::-:::esca:
        fpr:::::::::FFEAD1DB201FB214873E73994A83569F4E5E8D8A:
        uid:-::::::3D41A10AF2437C8C5BF6050FA80FE20CE30769BF::Backup Test <backup10@foo.com>:
        sub:i:1024:1:662F18DB92C8DFD8:1342810132::::::e:
        pub:r:1024:1:15ECEF9ECA136FFF:1342810387:::-:::sc:
        fpr:::::::::3D1CBF3FEFCE5ABB728922F615ECEF9ECA136FFF:
        uid:r::::1342810387::296434E1662AE0B2FF8E93EC3BF3AFE24514D0E0::Backup Test <backup11@foo.com>:
        sub:r:1024:1:097A79EB1F7D4619:1342810387::::::e:
        sub:r:1024:1:39093E8E9057625E:1342810404::::::e:
        pub:e:1024:1:31920687A8A7941B:1342810629:1342897029::-:::sc:
        fpr:::::::::03B399CBC2F4B61019D14BCD31920687A8A7941B:
        uid:e::::1342810629::ED8151565B25281CB92DD1E534701E660126CB0C::Backup Test <backup12@foo.com>:
        sub:e:1024:1:AEF89BEE95042A0F:1342810629:1342897029:::::e:
        pub:-:1024:1:E3DBAEC3FEEA03E2:1342810728:::-:::scSC:
        fpr:::::::::444B0870D985CF70BBB7F4DCE3DBAEC3FEEA03E2:
        uid:-::::1342810796::4D1B8CC29335BF79232CA71210F75CF80318B06A::Backup Test <backup13@foo.com>:
        uid:-::::1342810728::F1422363E8DC1EC3076906505CE66855BB44CAB7::Backup Test <backup14@foo.com>:
        sub:e:1024:1:C95DED316504D17C:1342810728:1342897218:::::e:
        pub:u:1024:1:027B83DB8A82B9CB:1343402840:::u:::scESC:
        fpr:::::::::A20D90150CE4E5F851AD3A9D027B83DB8A82B9CB:
        uid:u::::1343402840::307F1E025E8BEB7DABCADC353291184AD493A28E::Backup Test <backup01@foo.com>:
        sub:u:1024:1:EF31D36414FD8B2B:1343402840::::::e:
        pub:u:1024:1:4CEA6442A4A57A76:1343402867:::u:::scESC:
        fpr:::::::::5742EAFB4CF38014B474671E4CEA6442A4A57A76:
        uid:u::::1343402932::C220D9FF5C9652AA31D3CE0487D88EFF291FA1ED::Backup Test:
        uid:u::::1343402922::E89778553F703C26517AD8321C17C81F3213A782::Backup Test <backup02@foo.com>:
        sub:u:1024:1:140DDC2E97DA3567:1343402867::::::e:
      EOS
    end

    let(:valid_identifiers) do
      %w[
        FF9CFEA6 5EFD157FFF9CFEA6 72E56E48E362BB402B3344045EFD157FFF9CFEA6
        1E3DA3E8 570CE9221E3DA3E8 616BBC8409C1AED791F8E6F8570CE9221E3DA3E8
        <backup04@foo.com> <backup03@foo.com>
        A7641A16 54F81C93A7641A16 71335B9B960CF3A3071535F454F81C93A7641A16
        <backup05@foo.com>
        581A88CF 0A5B6CC9581A88CF E8C459082544924B8AEA06280A5B6CC9581A88CF
        <backup08@foo.com> <backup07@foo.com>
        FEEA03E2 E3DBAEC3FEEA03E2 444B0870D985CF70BBB7F4DCE3DBAEC3FEEA03E2
        <backup13@foo.com> <backup14@foo.com>
        8A82B9CB 027B83DB8A82B9CB A20D90150CE4E5F851AD3A9D027B83DB8A82B9CB
        <backup01@foo.com>
        A4A57A76 4CEA6442A4A57A76 5742EAFB4CF38014B474671E4CEA6442A4A57A76
        <backup02@foo.com>
      ]
    end

    it "should return an array of all valid identifiers" do
      encryptor.instance_variable_set(:@system_identifiers, nil)

      expect(encryptor).to receive(:utility).with(:gpg).and_return("gpg")
      expect(encryptor).to receive(:base_options).and_return("--base 'options'")
      expect(encryptor).to receive(:run).with(
        "gpg --base 'options' --with-colons --fixed-list-mode --fingerprint"
      ).and_return(gpg_output)

      expect(encryptor.send(:system_identifiers)).to eq(valid_identifiers)
      # results cached
      expect(encryptor.send(:system_identifiers)).to eq(valid_identifiers)
      expect(encryptor.instance_variable_get(:@system_identifiers))
        .to eq(valid_identifiers)
    end
  end # describe '#system_identifiers'
end
