# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Notifier::FlowDock do
    let(:model) { Model.new(:test_trigger, "test label") }
    let(:notifier) { Notifier::FlowDock.new(model) }
    let(:s) { sequence "" }

    it_behaves_like "a class that includes Config::Helpers"
    it_behaves_like "a subclass of Notifier::Base"

    describe "#initialize" do
      it "provides default values" do
        expect(notifier.token).to be_nil
        expect(notifier.from_name).to be_nil
        expect(notifier.from_email).to be_nil
        expect(notifier.subject).to eql "Backup Notification"
        expect(notifier.source).to  eql "Backup test label"

        expect(notifier.on_success).to be(true)
        expect(notifier.on_warning).to be(true)
        expect(notifier.on_failure).to be(true)
        expect(notifier.max_retries).to be(10)
        expect(notifier.retry_waitsec).to be(30)
      end

      it "configures the notifier" do
        notifier = Notifier::FlowDock.new(model) do |flowdock|
          flowdock.token           = "my_token"
          flowdock.from_name       = "my_name"
          flowdock.from_email      = "email@example.com"
          flowdock.subject         = "My Daily Backup"

          flowdock.on_success    = false
          flowdock.on_warning    = false
          flowdock.on_failure    = false
          flowdock.max_retries   = 5
          flowdock.retry_waitsec = 10
        end

        expect(notifier.token).to eq "my_token"
        expect(notifier.from_name).to eq "my_name"
        expect(notifier.from_email).to eq "email@example.com"
        expect(notifier.subject).to eq "My Daily Backup"

        expect(notifier.on_success).to be(false)
        expect(notifier.on_warning).to be(false)
        expect(notifier.on_failure).to be(false)
        expect(notifier.max_retries).to be(5)
        expect(notifier.retry_waitsec).to be(10)
      end
    end # describe '#initialize'

    describe "#notify!" do
      let(:notifier) do
        Notifier::FlowDock.new(model) do |flowdock|
          flowdock.token           = "my_token"
          flowdock.from_name       = "my_name"
          flowdock.from_email      = "email@example.com"
          flowdock.subject         = "My Daily Backup"
          flowdock.tags            = ["prod"]
          flowdock.link            = "www.example.com"
        end
      end
      let(:client) { double }
      let(:push_to_team_inbox) { double }
      let(:message) { "[Backup::%s] test label (test_trigger)" }

      context "when status is :success" do
        it "sends a success message" do
          expect(Flowdock::Flow).to receive(:new).ordered.with(
            api_token: "my_token", source: "Backup test label",
            from: { name: "my_name", address: "email@example.com" }
          ).and_return(client)
          expect(client).to receive(:push_to_team_inbox).ordered.with(
            subject: "My Daily Backup",
            content: message % "Success",
            tags: ["prod", "#BackupSuccess"],
            link: "www.example.com"
          )

          notifier.send(:notify!, :success)
        end
      end

      context "when status is :warning" do
        it "sends a warning message" do
          expect(Flowdock::Flow).to receive(:new).ordered.with(
            api_token: "my_token", source: "Backup test label",
            from: { name: "my_name", address: "email@example.com" }
          ).and_return(client)
          expect(client).to receive(:push_to_team_inbox).ordered.with(
            subject: "My Daily Backup",
            content: message % "Warning",
            tags: ["prod", "#BackupWarning"],
            link: "www.example.com"
          )

          notifier.send(:notify!, :warning)
        end
      end

      context "when status is :failure" do
        it "sends a failure message" do
          expect(Flowdock::Flow).to receive(:new).ordered.with(
            api_token: "my_token", source: "Backup test label",
            from: { name: "my_name", address: "email@example.com" }
          ).and_return(client)
          expect(client).to receive(:push_to_team_inbox).ordered.with(
            subject: "My Daily Backup",
            content: message % "Failure",
            tags: ["prod", "#BackupFailure"],
            link: "www.example.com"
          )

          notifier.send(:notify!, :failure)
        end
      end
    end
  end
end
