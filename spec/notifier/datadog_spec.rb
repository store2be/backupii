# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Notifier::DataDog do
    let(:model) { Model.new(:test_trigger, "test label") }
    let(:notifier) { Notifier::DataDog.new(model) }
    let(:s) { sequence "" }

    it_behaves_like "a class that includes Config::Helpers"
    it_behaves_like "a subclass of Notifier::Base"

    describe "#initialize" do
      it "provides default values" do
        expect(notifier.api_key).to be_nil
        expect(notifier.title).to eq "Backup test label"
        expect(notifier.date_happened).to be_nil
        expect(notifier.priority).to be_nil
        expect(notifier.host).to be_nil
        expect(notifier.tags).to be_nil
        expect(notifier.alert_type).to be_nil
        expect(notifier.aggregation_key).to be_nil
        expect(notifier.source_type_name).to be_nil
        expect(notifier.on_success).to be(true)
        expect(notifier.on_warning).to be(true)
        expect(notifier.on_failure).to be(true)
        expect(notifier.max_retries).to be(10)
        expect(notifier.retry_waitsec).to be(30)
      end

      it "configures the notifier" do
        notifier = Notifier::DataDog.new(model) do |datadog|
          datadog.api_key          = "my_key"
          datadog.title            = "Backup!"
          datadog.date_happened    = 12_345
          datadog.priority         = "low"
          datadog.host             = "local"
          datadog.tags             = %w[tag1 tag2]
          datadog.alert_type       = "error"
          datadog.aggregation_key  = "key"
          datadog.source_type_name = "my apps"
          datadog.on_success       = false
          datadog.on_warning       = false
          datadog.on_failure       = false
          datadog.max_retries      = 5
          datadog.retry_waitsec    = 10
        end

        expect(notifier.api_key).to eq "my_key"
        expect(notifier.title).to eq "Backup!"
        expect(notifier.date_happened).to eq 12_345
        expect(notifier.priority).to eq "low"
        expect(notifier.host).to eq "local"
        expect(notifier.tags.first).to eq "tag1"
        expect(notifier.alert_type).to eq "error"
        expect(notifier.aggregation_key).to eq "key"
        expect(notifier.source_type_name).to eq "my apps"
        expect(notifier.on_success).to be(false)
        expect(notifier.on_warning).to be(false)
        expect(notifier.on_failure).to be(false)
        expect(notifier.max_retries).to be(5)
        expect(notifier.retry_waitsec).to be(10)
      end
    end # describe '#initialize'

    describe "#notify!" do
      let(:notifier) do
        Notifier::DataDog.new(model) do |datadog|
          datadog.api_key = "my_token"
        end
      end
      let(:client) { double }
      let(:event) { double }

      context "when status is :success" do
        it "sends a success message" do
          expect(Dogapi::Client).to receive(:new).ordered
            .with("my_token")
            .and_return(client)
          expect(Dogapi::Event).to receive(:new).ordered.with(
            "[Backup::Success] test label (test_trigger)",
            msg_title: "Backup test label",
            alert_type: "success"
          ).and_return(event)
          expect(client).to receive(:emit_event).ordered.with(event)

          notifier.send(:notify!, :success)
        end
      end

      context "when status is :warning" do
        it "sends a warning message" do
          expect(Dogapi::Client).to receive(:new).ordered
            .with("my_token")
            .and_return(client)
          expect(Dogapi::Event).to receive(:new).ordered.with(
            "[Backup::Warning] test label (test_trigger)",
            msg_title: "Backup test label",
            alert_type: "warning"
          ).and_return(event)
          expect(client).to receive(:emit_event).ordered.with(event)

          notifier.send(:notify!, :warning)
        end
      end

      context "when status is :failure" do
        it "sends an error message" do
          expect(Dogapi::Client).to receive(:new).ordered
            .with("my_token")
            .and_return(client)
          expect(Dogapi::Event).to receive(:new).ordered.with(
            "[Backup::Failure] test label (test_trigger)",
            msg_title: "Backup test label",
            alert_type: "error"
          ).and_return(event)
          expect(client).to receive(:emit_event).ordered.with(event)

          notifier.send(:notify!, :failure)
        end
      end
    end
  end # describe '#notify!'
end
