# frozen_string_literal: true

module Backup
  module Encryptor
    class Base
      include Utilities::Helpers
      include Config::Helpers

      def initialize
        load_defaults!
      end

      private

      ##
      # Return the encryptor name, with Backup namespace removed
      def encryptor_name
        self.class.to_s.sub("Backup::", "")
      end

      ##
      # Logs a message to the console and log file to inform
      # the client that Backup is encrypting the archive
      def log!
        Logger.info "Using #{encryptor_name} to encrypt the archive."
      end
    end
  end
end
