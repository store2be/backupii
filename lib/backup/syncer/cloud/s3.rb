# frozen_string_literal: true

require "backup/cloud_io/s3"

module Backup
  module Syncer
    module Cloud
      class S3 < Base
        class Error < Backup::Error; end

        ##
        # Amazon Simple Storage Service (S3) Credentials
        attr_accessor :access_key_id, :secret_access_key, :use_iam_profile

        ##
        # Amazon S3 bucket name
        attr_accessor :bucket

        ##
        # Region of the specified S3 bucket
        attr_accessor :region

        ##
        # Encryption algorithm to use for Amazon Server-Side Encryption
        #
        # Supported values:
        #
        # - :aes256
        #
        # Default: nil
        attr_accessor :encryption

        ##
        # Storage class to use for the S3 objects uploaded
        #
        # Supported values:
        #
        # - :standard (default)
        # - :reduced_redundancy
        #
        # Default: :standard
        attr_accessor :storage_class

        ##
        # Additional options to pass along to fog.
        # e.g. Fog::Storage.new({ :provider => 'AWS' }.merge(fog_options))
        attr_accessor :fog_options

        def initialize(syncer_id = nil)
          super

          @storage_class ||= :standard

          check_configuration
        end

        private

        def cloud_io
          @cloud_io ||= CloudIO::S3.new(
            access_key_id: access_key_id,
            secret_access_key: secret_access_key,
            use_iam_profile: use_iam_profile,
            bucket: bucket,
            region: region,
            encryption: encryption,
            storage_class: storage_class,
            max_retries: max_retries,
            retry_waitsec: retry_waitsec,
            # Syncer can not use multipart upload.
            chunk_size: 0,
            fog_options: fog_options
          )
        end

        def get_remote_files(remote_base)
          hash = {}
          cloud_io.objects(remote_base).each do |object|
            relative_path = object.key.sub(remote_base + "/", "")
            hash[relative_path] = object.etag
          end
          hash
        end

        def check_configuration
          required =
            if use_iam_profile
              %w[bucket]
            else
              %w[access_key_id secret_access_key bucket]
            end

          if required.map { |name| send(name) }.any?(&:nil?)
            raise Error, <<-EOS
              Configuration Error
              #{required.map { |name| "##{name}" }.join(", ")} are all required
            EOS
          end

          if encryption && encryption.to_s.upcase != "AES256"
            raise Error, <<-EOS
              Configuration Error
              #encryption must be :aes256 or nil
            EOS
          end
          classes = %w[STANDARD REDUCED_REDUNDANCY]

          unless classes.include?(storage_class.to_s.upcase)
            raise Error, <<-EOS
              Configuration Error
              #storage_class must be :standard or :reduced_redundancy
            EOS
          end
        end
      end # Class S3 < Base
    end # module Cloud
  end
end
