# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Notifier::Nagios do
    let(:model) { Model.new(:test_trigger, "test model") }
    let(:notifier) { Notifier::Nagios.new(model) }

    before do
      allow(Utilities).to receive(:utility).with(:send_nsca).and_return("send_nsca")
      allow(Config).to receive(:hostname).and_return("my.hostname")
    end

    it_behaves_like "a class that includes Config::Helpers"
    it_behaves_like "a subclass of Notifier::Base"

    describe "#initialize" do
      it "provides default values" do
        expect(notifier.nagios_host).to eq "my.hostname"
        expect(notifier.nagios_port).to be 5667
        expect(notifier.send_nsca_cfg).to eq "/etc/nagios/send_nsca.cfg"
        expect(notifier.service_name).to eq "Backup test_trigger"
        expect(notifier.service_host).to eq "my.hostname"

        expect(notifier.on_success).to be(true)
        expect(notifier.on_warning).to be(true)
        expect(notifier.on_failure).to be(true)
        expect(notifier.max_retries).to be(10)
        expect(notifier.retry_waitsec).to be(30)
      end

      it "configures the notifier" do
        notifier = Notifier::Nagios.new(model) do |nagios|
          nagios.nagios_host  = "my_nagios_host"
          nagios.nagios_port  = 1234
          nagios.send_nsca_cfg = "my_send_nsca_cfg"
          nagios.service_name = "my_service_name"
          nagios.service_host = "my_service_host"

          nagios.on_success    = false
          nagios.on_warning    = false
          nagios.on_failure    = false
          nagios.max_retries   = 5
          nagios.retry_waitsec = 10
        end

        expect(notifier.nagios_host).to eq "my_nagios_host"
        expect(notifier.nagios_port).to be 1234
        expect(notifier.send_nsca_cfg).to eq "my_send_nsca_cfg"
        expect(notifier.service_name).to eq "my_service_name"
        expect(notifier.service_host).to eq "my_service_host"

        expect(notifier.on_success).to be(false)
        expect(notifier.on_warning).to be(false)
        expect(notifier.on_failure).to be(false)
        expect(notifier.max_retries).to be(5)
        expect(notifier.retry_waitsec).to be(10)
      end
    end # describe '#initialize'

    describe "#notify!" do
      let(:nagios_cmd) { "send_nsca -H 'my.hostname' -p '5667' -c '/etc/nagios/send_nsca.cfg'" }

      before do
        notifier.service_host = "my.service.host"
        allow(model).to receive(:duration).and_return("12:34:56")
      end

      context "when status is :success" do
        let(:nagios_msg) do
          "my.service.host\tBackup test_trigger\t0\t"\
          "[Backup::Success] test model (test_trigger)"
        end
        before { allow(model).to receive(:exit_status).and_return(0) }

        it "sends a Success message" do
          expect(Utilities).to receive(:run).with("echo '#{nagios_msg}' | #{nagios_cmd}")

          notifier.send(:notify!, :success)
        end
      end

      context "when status is :warning" do
        let(:nagios_msg) do
          "my.service.host\tBackup test_trigger\t1\t"\
          "[Backup::Warning] test model (test_trigger)"
        end
        before { allow(model).to receive(:exit_status).and_return(1) }

        it "sends a Success message" do
          expect(Utilities).to receive(:run).with("echo '#{nagios_msg}' | #{nagios_cmd}")

          notifier.send(:notify!, :warning)
        end
      end

      context "when status is :failure" do
        let(:nagios_msg) do
          "my.service.host\tBackup test_trigger\t2\t"\
          "[Backup::Failure] test model (test_trigger)"
        end
        before { allow(model).to receive(:exit_status).and_return(2) }

        it "sends a Success message" do
          expect(Utilities).to receive(:run).with("echo '#{nagios_msg}' | #{nagios_cmd}")

          notifier.send(:notify!, :failure)
        end
      end
    end # describe '#notify!'
  end
end
