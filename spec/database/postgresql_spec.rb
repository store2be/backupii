# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Database::PostgreSQL do
    let(:model) { Model.new(:test_trigger, "test label") }
    let(:db) { Database::PostgreSQL.new(model) }
    let(:s) { sequence "" }

    before do
      allow(Utilities).to receive(:utility).with(:pg_dump).and_return("pg_dump")
      allow(Utilities).to receive(:utility).with(:pg_dumpall).and_return("pg_dumpall")
      allow(Utilities).to receive(:utility).with(:cat).and_return("cat")
      allow(Utilities).to receive(:utility).with(:sudo).and_return("sudo")
    end

    it_behaves_like "a class that includes Config::Helpers"
    it_behaves_like "a subclass of Database::Base"

    describe "#initialize" do
      it "provides default values" do
        expect(db.database_id).to be_nil
        expect(db.name).to eq :all
        expect(db.username).to be_nil
        expect(db.password).to be_nil
        expect(db.sudo_user).to be_nil
        expect(db.host).to be_nil
        expect(db.port).to be_nil
        expect(db.socket).to be_nil
        expect(db.skip_tables).to be_nil
        expect(db.only_tables).to be_nil
        expect(db.additional_options).to be_nil
      end

      it "configures the database" do
        db = Database::PostgreSQL.new(model, :my_id) do |pgsql|
          pgsql.name               = "my_name"
          pgsql.username           = "my_username"
          pgsql.password           = "my_password"
          pgsql.sudo_user          = "my_sudo_user"
          pgsql.host               = "my_host"
          pgsql.port               = "my_port"
          pgsql.socket             = "my_socket"
          pgsql.skip_tables        = "my_skip_tables"
          pgsql.only_tables        = "my_only_tables"
          pgsql.additional_options = "my_additional_options"
        end

        expect(db.database_id).to eq "my_id"
        expect(db.name).to eq "my_name"
        expect(db.username).to eq "my_username"
        expect(db.password).to eq "my_password"
        expect(db.sudo_user).to eq "my_sudo_user"
        expect(db.host).to eq "my_host"
        expect(db.port).to eq "my_port"
        expect(db.socket).to eq "my_socket"
        expect(db.skip_tables).to eq "my_skip_tables"
        expect(db.only_tables).to eq "my_only_tables"
        expect(db.additional_options).to eq "my_additional_options"
      end
    end # describe '#initialize'

    describe "#perform!" do
      let(:pipeline) { double }
      let(:compressor) { double }

      before do
        allow(db).to receive(:pgdump).and_return("pgdump_command")
        allow(db).to receive(:pgdumpall).and_return("pgdumpall_command")
        allow(db).to receive(:dump_path).and_return("/tmp/trigger/databases")

        expect(db).to receive(:log!).ordered.with(:started)
        expect(db).to receive(:prepare!).ordered
      end

      context "without a compressor" do
        it "packages the dump without compression" do
          expect(Pipeline).to receive(:new).ordered.and_return(pipeline)

          expect(pipeline).to receive(:<<).ordered.with("pgdumpall_command")

          expect(pipeline).to receive(:<<).ordered.with(
            "cat > '/tmp/trigger/databases/PostgreSQL.sql'"
          )

          expect(pipeline).to receive(:run).ordered
          expect(pipeline).to receive(:success?).ordered.and_return(true)

          expect(db).to receive(:log!).ordered.with(:finished)

          db.perform!
        end
      end # context 'without a compressor'

      context "with a compressor" do
        before do
          allow(model).to receive(:compressor).and_return(compressor)
          allow(compressor).to receive(:compress_with).and_yield("cmp_cmd", ".cmp_ext")
        end

        it "packages the dump with compression" do
          expect(Pipeline).to receive(:new).ordered.and_return(pipeline)

          expect(pipeline).to receive(:<<).ordered.with("pgdumpall_command")

          expect(pipeline).to receive(:<<).ordered.with("cmp_cmd")

          expect(pipeline).to receive(:<<).ordered.with(
            "cat > '/tmp/trigger/databases/PostgreSQL.sql.cmp_ext'"
          )

          expect(pipeline).to receive(:run).ordered
          expect(pipeline).to receive(:success?).ordered.and_return(true)

          expect(db).to receive(:log!).ordered.with(:finished)

          db.perform!
        end
      end # context 'without a compressor'

      context "when #name is set" do
        before do
          db.name = "my_db"
        end

        it "uses the pg_dump command" do
          expect(Pipeline).to receive(:new).ordered.and_return(pipeline)

          expect(pipeline).to receive(:<<).ordered.with("pgdump_command")

          expect(pipeline).to receive(:<<).ordered.with(
            "cat > '/tmp/trigger/databases/PostgreSQL.sql'"
          )

          expect(pipeline).to receive(:run).ordered
          expect(pipeline).to receive(:success?).ordered.and_return(true)

          expect(db).to receive(:log!).ordered.with(:finished)

          db.perform!
        end
      end # context 'without a compressor'

      context "when the pipeline fails" do
        before do
          allow_any_instance_of(Pipeline).to receive(:success?).and_return(false)
          allow_any_instance_of(Pipeline).to receive(:error_messages).and_return("error messages")
        end

        it "raises an error" do
          expect do
            db.perform!
          end.to raise_error(Database::PostgreSQL::Error) { |err|
            expect(err.message).to eq(
              "Database::PostgreSQL::Error: Dump Failed!\n  error messages"
            )
          }
        end
      end # context 'when the pipeline fails'
    end # describe '#perform!'

    describe "#pgdump" do
      let(:option_methods) do
        %w[
          username_option connectivity_options
          user_options tables_to_dump tables_to_skip name
        ]
      end
      # password_option and sudo_option leave no leading space if it's not used

      it "returns full pg_dump command built from all options" do
        option_methods.each { |name| allow(db).to receive(name).and_return(name) }
        allow(db).to receive(:password_option).and_return("password_option")
        allow(db).to receive(:sudo_option).and_return("sudo_option")
        expect(db.send(:pgdump)).to eq(
          "password_optionsudo_optionpg_dump #{option_methods.join(" ")}"
        )
      end

      it "handles nil values from option methods" do
        option_methods.each { |name| allow(db).to receive(name).and_return(nil) }
        allow(db).to receive(:password_option).and_return(nil)
        allow(db).to receive(:sudo_option).and_return(nil)
        expect(db.send(:pgdump)).to eq(
          "pg_dump #{" " * (option_methods.count - 1)}"
        )
      end
    end # describe '#pgdump'

    describe "#pgdumpall" do
      let(:option_methods) do
        %w[
          username_option connectivity_options user_options
        ]
      end
      # password_option and sudo_option leave no leading space if it's not used

      it "returns full pg_dump command built from all options" do
        option_methods.each { |name| allow(db).to receive(name).and_return(name) }
        allow(db).to receive(:password_option).and_return("password_option")
        allow(db).to receive(:sudo_option).and_return("sudo_option")
        expect(db.send(:pgdumpall)).to eq(
          "password_optionsudo_optionpg_dumpall #{option_methods.join(" ")}"
        )
      end

      it "handles nil values from option methods" do
        option_methods.each { |name| allow(db).to receive(name).and_return(nil) }
        allow(db).to receive(:password_option).and_return(nil)
        allow(db).to receive(:sudo_option).and_return(nil)
        expect(db.send(:pgdumpall)).to eq(
          "pg_dumpall #{" " * (option_methods.count - 1)}"
        )
      end
    end # describe '#pgdumpall'

    describe "pgdump option methods" do
      describe "#password_option" do
        it "returns syntax to set environment variable" do
          expect(db.send(:password_option)).to be_nil

          db.password = "my_password"
          expect(db.send(:password_option)).to eq "PGPASSWORD=my_password "
        end

        it "handles special characters" do
          db.password = "my_password'\""
          expect(db.send(:password_option)).to eq(
            "PGPASSWORD=my_password\\'\\\" "
          )
        end
      end # describe '#password_option'

      describe "#sudo_option" do
        it "returns argument if specified" do
          expect(db.send(:sudo_option)).to be_nil

          db.sudo_user = "my_sudo_user"
          expect(db.send(:sudo_option)).to eq "sudo -n -H -u my_sudo_user "
        end
      end # describe '#sudo_option'

      describe "#username_option" do
        it "returns argument if specified" do
          expect(db.send(:username_option)).to be_nil

          db.username = "my_username"
          expect(db.send(:username_option)).to eq "--username=my_username"
        end

        it "handles special characters" do
          db.username = "my_user'\""
          expect(db.send(:username_option)).to eq(
            "--username=my_user\\'\\\""
          )
        end
      end # describe '#username_option'

      describe "#connectivity_options" do
        it "returns only the socket argument if #socket specified" do
          db.host = "my_host"
          db.port = "my_port"
          db.socket = "my_socket"
          # pgdump uses --host to specify a socket
          expect(db.send(:connectivity_options)).to eq(
            "--host='my_socket'"
          )
        end

        it "returns host and port arguments if specified" do
          expect(db.send(:connectivity_options)).to eq ""

          db.host = "my_host"
          expect(db.send(:connectivity_options)).to eq(
            "--host='my_host'"
          )

          db.port = "my_port"
          expect(db.send(:connectivity_options)).to eq(
            "--host='my_host' --port='my_port'"
          )

          db.host = nil
          expect(db.send(:connectivity_options)).to eq(
            "--port='my_port'"
          )
        end
      end # describe '#connectivity_options'

      describe "#user_options" do
        it "returns arguments for any #additional_options specified" do
          expect(db.send(:user_options)).to eq ""

          db.additional_options = ["--opt1", "--opt2"]
          expect(db.send(:user_options)).to eq "--opt1 --opt2"

          db.additional_options = "--opta --optb"
          expect(db.send(:user_options)).to eq "--opta --optb"
        end
      end # describe '#user_options'

      describe "#tables_to_dump" do
        it "returns arguments for only_tables" do
          expect(db.send(:tables_to_dump)).to eq ""

          db.only_tables = %w[one two]
          expect(db.send(:tables_to_dump)).to eq(
            "--table='one' --table='two'"
          )

          db.only_tables = "three four"
          expect(db.send(:tables_to_dump)).to eq(
            "--table='three four'"
          )
        end
      end # describe '#tables_to_dump'

      describe "#tables_to_skip" do
        it "returns arguments for skip_tables" do
          expect(db.send(:tables_to_skip)).to eq ""

          db.skip_tables = %w[one two]
          expect(db.send(:tables_to_skip)).to eq(
            "--exclude-table='one' --exclude-table='two'"
          )

          db.skip_tables = "three four"
          expect(db.send(:tables_to_skip)).to eq(
            "--exclude-table='three four'"
          )
        end
      end # describe '#tables_to_dump'
    end # describe 'pgdump option methods'
  end
end
