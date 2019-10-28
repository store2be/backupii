# frozen_string_literal: true

require "spec_helper"

module Backup
  describe Logger::FogAdapter do
    it "replaces STDOUT fog warning channel" do
      expect(Fog::Logger[:warning]).to be Logger::FogAdapter
    end

    describe "#tty?" do
      it "returns false" do
        expect(Logger::FogAdapter.tty?).to be(false)
      end
    end

    describe "#write" do
      it "logs fog warnings as info messages" do
        expect(Logger).to receive(:info).with("[fog][WARNING] some message")
        Fog::Logger.warning "some message"
      end
    end
  end
end
