# frozen_string_literal: true

shared_examples "a subclass of Database::Base" do
  describe "#initialize" do
    it "sets a reference to the model" do
      expect(db.model).to be(model)
    end

    it "cleans database_id for filename use" do
      block = respond_to?(:required_config) ? required_config : proc {}

      db = described_class.new(model, :my_id, &block)
      expect(db.database_id).to eq "my_id"

      db = described_class.new(model, "My #1 ID", &block)
      expect(db.database_id).to eq "My__1_ID"
    end

    it "sets the dump_path" do
      expect(db.dump_path).to eq(
        File.join(Backup::Config.tmp_path, "test_trigger", "databases")
      )
    end
  end # describe '#initialize'

  describe "#prepare!" do
    it "creates the dump_path" do
      expect(FileUtils).to receive(:mkdir_p).with(db.dump_path)
      db.send(:prepare!)
    end
  end

  describe "#dump_filename" do
    let(:klass_name) { described_class.name.split("::").last }

    before do
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    it "logs warning when model is created if database_id is needed" do
      expect(Backup::Logger).to receive(:warn) do |err|
        expect(err)
          .to be_an_instance_of Backup::Database::Error
      end

      klass = described_class
      block = respond_to?(:required_config) ? required_config : proc {}
      Backup::Model.new(:test_model, "test model") do
        database klass, nil, &block
        database klass, :my_id, &block
      end
    end

    it "auto-generates a database_id if needed" do
      klass = described_class
      block = respond_to?(:required_config) ? required_config : proc {}
      test_model = Backup::Model.new(:test_model, "test model") do
        database klass, nil, &block
        database klass, :my_id, &block
      end
      db1, db2 = test_model.databases

      expect(db1.send(:dump_filename)).to match(%r{#{klass_name}-\d{5}})
      expect(db2.send(:dump_filename)).to eq "#{klass_name}-my_id"
    end

    it "does not warn or auto-generate database_id if only one class defined" do
      expect(Backup::Logger).to receive(:warn).never

      klass = described_class
      block = respond_to?(:required_config) ? required_config : proc {}
      test_model = Backup::Model.new(:test_model, "test model") do
        database klass, nil, &block
      end
      db = test_model.databases.first

      expect(db.send(:dump_filename)).to eq klass_name
    end
  end # describe '#dump_filename'

  describe "log!" do
    let(:klass_name) { described_class.name.to_s.sub("Backup::", "") }

    specify "with a database_id" do
      block = respond_to?(:required_config) ? required_config : proc {}
      db = described_class.new(model, :my_id, &block)

      expect(Backup::Logger).to receive(:info).with("#{klass_name} (my_id) Started...")
      db.send(:log!, :started)

      expect(Backup::Logger).to receive(:info).with("#{klass_name} (my_id) Finished!")
      db.send(:log!, :finished)
    end

    specify "without a database_id" do
      expect(Backup::Logger).to receive(:info).with("#{klass_name} Started...")
      db.send(:log!, :started)

      expect(Backup::Logger).to receive(:info).with("#{klass_name} Finished!")
      db.send(:log!, :finished)
    end
  end # describe 'log!'
end
