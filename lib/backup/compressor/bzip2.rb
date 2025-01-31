# frozen_string_literal: true

module Backup
  module Compressor
    class Bzip2 < Base
      ##
      # Specify the level of compression to use.
      #
      # Values should be a single digit from 1 to 9.
      # Note that setting the level to either extreme may or may not
      # give the desired result. Be sure to check the documentation
      # for the compressor being used.
      #
      # The default `level` is 9.
      attr_accessor :level

      ##
      # Creates a new instance of Backup::Compressor::Bzip2
      def initialize(&block)
        load_defaults!

        @level ||= false

        instance_eval(&block) if block_given?

        @cmd = "#{utility(:bzip2)}#{options}"
        @ext = ".bz2"
      end

      private

      def options
        " -#{@level}" if @level
      end
    end
  end
end
