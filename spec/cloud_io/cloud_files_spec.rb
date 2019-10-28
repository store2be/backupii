# frozen_string_literal: true

require "spec_helper"
require "backup/cloud_io/cloud_files"

module Backup
  describe CloudIO::CloudFiles do
    let(:connection) { double }

    describe "#upload" do
      before do
        expect_any_instance_of(described_class).to receive(:create_containers)
      end

      context "with SLO support" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            container: "my_container",
            segments_container: "my_segments_container",
            segment_size: 5
          )
        end
        let(:segments) { double }

        context "when src file is larger than segment_size" do
          before do
            expect(File).to receive(:size).with("/src/file").and_return(10 * 1024**2)
          end

          it "uploads as a SLO" do
            expect(cloud_io).to receive(:upload_segments).with(
              "/src/file", "dest/file", 5 * 1024**2, 10 * 1024**2
            ).and_return(segments)
            expect(cloud_io).to receive(:upload_manifest).with("dest/file", segments)
            expect(cloud_io).to receive(:put_object).never

            cloud_io.upload("/src/file", "dest/file")
          end
        end

        context "when src file is not larger than segment_size" do
          before do
            expect(File).to receive(:size).with("/src/file").and_return(5 * 1024**2)
          end

          it "uploads as a non-SLO" do
            expect(cloud_io).to receive(:put_object).with("/src/file", "dest/file")
            expect(cloud_io).to receive(:upload_segments).never
            expect(cloud_io).to receive(:upload_manifest).never

            cloud_io.upload("/src/file", "dest/file")
          end
        end

        context "when segment_size is too small for the src file" do
          before do
            expect(File).to receive(:size).with("/src/file").and_return((5000 * 1024**2) + 1)
          end

          it "warns and adjusts the segment_size" do
            expect(cloud_io).to receive(:upload_segments).with(
              "/src/file", "dest/file", 6 * 1024**2, (5000 * 1024**2) + 1
            ).and_return(segments)
            expect(cloud_io).to receive(:upload_manifest).with("dest/file", segments)
            expect(cloud_io).to receive(:put_object).never

            expect(Logger).to receive(:warn) do |err|
              expect(err.message).to include(
                "#segment_size of 5 MiB has been adjusted\n  to 6 MiB"
              )
            end

            cloud_io.upload("/src/file", "dest/file")
          end
        end

        context "when src file is too large" do
          before do
            expect(File).to receive(:size).with("/src/file")
              .and_return(described_class::MAX_SLO_SIZE + 1)
          end

          it "raises an error" do
            expect(cloud_io).to receive(:upload_segments).never
            expect(cloud_io).to receive(:upload_manifest).never
            expect(cloud_io).to receive(:put_object).never

            expect do
              cloud_io.upload("/src/file", "dest/file")
            end.to raise_error(CloudIO::FileSizeError)
          end
        end
      end # context 'with SLO support'

      context "without SLO support" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            container: "my_container",
            segment_size: 0
          )
        end

        before do
          expect(cloud_io).to receive(:upload_segments).never
        end

        context "when src file size is ok" do
          before do
            expect(File).to receive(:size).with("/src/file")
              .and_return(described_class::MAX_FILE_SIZE)
          end

          it "uploads as non-SLO" do
            expect(cloud_io).to receive(:put_object).with("/src/file", "dest/file")

            cloud_io.upload("/src/file", "dest/file")
          end
        end

        context "when src file is too large" do
          before do
            expect(File).to receive(:size).with("/src/file")
              .and_return(described_class::MAX_FILE_SIZE + 1)
          end

          it "raises an error" do
            expect(cloud_io).to receive(:put_object).never

            expect do
              cloud_io.upload("/src/file", "dest/file")
            end.to raise_error(CloudIO::FileSizeError)
          end
        end
      end # context 'without SLO support'
    end # describe '#upload'

    describe "#objects" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
        expect(cloud_io).to receive(:create_containers)
      end

      it "ensures prefix ends with /" do
        expect(connection).to receive(:get_container)
          .with("my_container", prefix: "foo/bar/")
          .and_return(double("response", body: []))
        expect(cloud_io.objects("foo/bar")).to eq []
      end

      it "returns an empty array when no objects are found" do
        expect(connection).to receive(:get_container)
          .with("my_container", prefix: "foo/bar/")
          .and_return(double("response", body: []))
        expect(cloud_io.objects("foo/bar/")).to eq []
      end

      context "when less than 10,000 objects are available" do
        let(:resp_body) do
          Array.new(10) { |n| { "name" => "name_#{n}", "hash" => "hash_#{n}" } }
        end

        it "returns all objects" do
          expect(cloud_io).to receive(:with_retries)
            .with("GET 'my_container/foo/bar/*'").and_yield
          expect(connection).to receive(:get_container)
            .with("my_container", prefix: "foo/bar/")
            .and_return(double("response", body: resp_body))

          objects = cloud_io.objects("foo/bar/")
          expect(objects.count).to be 10
          objects.each_with_index do |object, n|
            expect(object.name).to eq("name_#{n}")
            expect(object.hash).to eq("hash_#{n}")
          end
        end
      end

      context "when more than 10,000 objects are available" do
        let(:resp_body_a) do
          Array.new(10_000) { |n| { "name" => "name_#{n}", "hash" => "hash_#{n}" } }
        end
        let(:resp_body_b) do
          Array.new(10) do |n|
            n += 10_000
            { "name" => "name_#{n}", "hash" => "hash_#{n}" }
          end
        end

        it "returns all objects" do
          expect(cloud_io).to receive(:with_retries).twice
            .with("GET 'my_container/foo/bar/*'").and_yield
          expect(connection).to receive(:get_container)
            .with("my_container", prefix: "foo/bar/")
            .and_return(double("response", body: resp_body_a))
          expect(connection).to receive(:get_container)
            .with("my_container", prefix: "foo/bar/", marker: "name_9999")
            .and_return(double("response", body: resp_body_b))

          objects = cloud_io.objects("foo/bar/")
          expect(objects.count).to be 10_010
        end

        it "retries on errors" do
          expect(connection).to receive(:get_container).once
            .with("my_container", prefix: "foo/bar/")
            .and_raise("error")
          expect(connection).to receive(:get_container).once
            .with("my_container", prefix: "foo/bar/")
            .and_return(double("response", body: resp_body_a))
          expect(connection).to receive(:get_container).once
            .with("my_container", prefix: "foo/bar/", marker: "name_9999")
            .and_raise("error")
          expect(connection).to receive(:get_container).once
            .with("my_container", prefix: "foo/bar/", marker: "name_9999")
            .and_return(double("response", body: resp_body_b))

          objects = cloud_io.objects("foo/bar/")
          expect(objects.count).to be 10_010
        end
      end
    end # describe '#objects'

    describe "#head_object" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
      end

      it "returns head_object response with retries" do
        object = double("response", name: "obj_name")
        expect(connection).to receive(:head_object).once
          .with("my_container", "obj_name")
          .and_raise("error")
        expect(connection).to receive(:head_object).once
          .with("my_container", "obj_name")
          .and_return(:response)
        expect(cloud_io.head_object(object)).to eq :response
      end
    end # describe '#head_object'

    describe "#delete" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end
      let(:resp_ok) { double("response", body: { "Response Status" => "200 OK" }) }
      let(:resp_bad) { double("response", body: { "Response Status" => "400 Bad Request" }) }

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
      end

      it "accepts a single Object" do
        object = described_class::Object.new(
          :foo, "name" => "obj_name", "hash" => "obj_hash"
        )
        expect(cloud_io).to receive(:with_retries).with("DELETE Multiple Objects").and_yield
        expect(connection).to receive(:delete_multiple_objects)
          .with("my_container", ["obj_name"]).and_return(resp_ok)
        cloud_io.delete(object)
      end

      it "accepts a multiple Objects" do
        object_a = described_class::Object.new(
          :foo, "name" => "obj_a_name", "hash" => "obj_a_hash"
        )
        object_b = described_class::Object.new(
          :foo, "name" => "obj_b_name", "hash" => "obj_b_hash"
        )
        expect(cloud_io).to receive(:with_retries).with("DELETE Multiple Objects").and_yield
        expect(connection).to receive(:delete_multiple_objects)
          .with("my_container", %w[obj_a_name obj_b_name]).and_return(resp_ok)

        objects = [object_a, object_b]
        expect { cloud_io.delete(objects) }.not_to change { objects.map(&:inspect) }
      end

      it "accepts a single name" do
        expect(cloud_io).to receive(:with_retries).with("DELETE Multiple Objects").and_yield
        expect(connection).to receive(:delete_multiple_objects)
          .with("my_container", ["obj_name"]).and_return(resp_ok)
        cloud_io.delete("obj_name")
      end

      it "accepts multiple names" do
        expect(cloud_io).to receive(:with_retries).with("DELETE Multiple Objects").and_yield
        expect(connection).to receive(:delete_multiple_objects)
          .with("my_container", %w[obj_a_name obj_b_name]).and_return(resp_ok)

        names = %w[obj_a_name obj_b_name]
        expect { cloud_io.delete(names) }.not_to change { names }
      end

      it "does nothing if empty array passed" do
        expect(connection).to receive(:delete_multiple_objects).never
        cloud_io.delete([])
      end

      it "deletes 10,000 objects per request" do
        max_names = ["name"] * 10_000
        names_remaining = ["name"] * 10
        names_all = max_names + names_remaining

        expect(cloud_io).to receive(:with_retries).twice.with("DELETE Multiple Objects").and_yield
        expect(connection).to receive(:delete_multiple_objects)
          .with("my_container", max_names).and_return(resp_ok)
        expect(connection).to receive(:delete_multiple_objects)
          .with("my_container", names_remaining).and_return(resp_ok)

        expect { cloud_io.delete(names_all) }.not_to change { names_all }
      end

      it "retries on raised errors" do
        expect(connection).to receive(:delete_multiple_objects).once
          .with("my_container", ["obj_name"])
          .and_raise("error")
        expect(connection).to receive(:delete_multiple_objects).once
          .with("my_container", ["obj_name"])
          .and_return(resp_ok)
        cloud_io.delete("obj_name")
      end

      it "retries on returned errors" do
        expect(connection).to receive(:delete_multiple_objects).twice
          .with("my_container", ["obj_name"])
          .and_return(resp_bad, resp_ok)
        cloud_io.delete("obj_name")
      end

      it "fails after retries exceeded" do
        expect(connection).to receive(:delete_multiple_objects).once
          .with("my_container", ["obj_name"])
          .and_raise("error message")
        expect(connection).to receive(:delete_multiple_objects).once
          .with("my_container", ["obj_name"])
          .and_return(resp_bad)

        expect do
          cloud_io.delete("obj_name")
        end.to raise_error(CloudIO::Error) { |err|
          expect(err.message).to eq(
            "CloudIO::Error: Max Retries (1) Exceeded!\n" \
            "  Operation: DELETE Multiple Objects\n" \
            "  Be sure to check the log messages for each retry attempt.\n" \
            "--- Wrapped Exception ---\n" \
            "CloudIO::CloudFiles::Error: 400 Bad Request\n" \
            "  The server returned the following:\n" \
            "  {\"Response Status\"=>\"400 Bad Request\"}"
          )
        }
        expect(Logger.messages.map(&:lines).join("\n")).to eq(
          "CloudIO::Error: Retry #1 of 1\n" \
          "  Operation: DELETE Multiple Objects\n" \
          "--- Wrapped Exception ---\n" \
          "RuntimeError: error message"
        )
      end
    end # describe '#delete'

    describe "#delete_slo" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end
      let(:object_a) do
        described_class::Object.new(
          :foo, "name" => "obj_a_name", "hash" => "obj_a_hash"
        )
      end
      let(:object_b) do
        described_class::Object.new(
          :foo, "name" => "obj_b_name", "hash" => "obj_b_hash"
        )
      end
      let(:resp_ok) { double("response", body: { "Response Status" => "200 OK" }) }
      let(:resp_bad) { double("response", body: { "Response Status" => "400 Bad Request" }) }

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
      end

      it "deletes a single SLO" do
        expect(connection).to receive(:delete_static_large_object)
          .with("my_container", "obj_a_name").and_return(resp_ok)
        cloud_io.delete_slo(object_a)
      end

      it "deletes a multiple SLOs" do
        expect(connection).to receive(:delete_static_large_object)
          .with("my_container", "obj_a_name").and_return(resp_ok)
        expect(connection).to receive(:delete_static_large_object)
          .with("my_container", "obj_b_name").and_return(resp_ok)
        cloud_io.delete_slo([object_a, object_b])
      end

      it "retries on raised and returned errors" do
        expect(connection).to receive(:delete_static_large_object).once
          .with("my_container", "obj_a_name")
          .and_raise("error")
        expect(connection).to receive(:delete_static_large_object).once
          .with("my_container", "obj_a_name")
          .and_return(resp_ok)
        expect(connection).to receive(:delete_static_large_object).twice
          .with("my_container", "obj_b_name")
          .and_return(resp_bad, resp_ok)
        cloud_io.delete_slo([object_a, object_b])
      end

      it "fails after retries exceeded" do
        expect(connection).to receive(:delete_static_large_object).once
          .with("my_container", "obj_a_name")
          .and_raise("error message")
        expect(connection).to receive(:delete_static_large_object).once
          .with("my_container", "obj_a_name")
          .and_return(resp_ok)
        expect(connection).to receive(:delete_static_large_object).once
          .with("my_container", "obj_b_name")
          .and_return(resp_bad)
        expect(connection).to receive(:delete_static_large_object).once
          .with("my_container", "obj_b_name")
          .and_raise("failure")

        expect do
          cloud_io.delete_slo([object_a, object_b])
        end.to raise_error(CloudIO::Error) { |err|
          expect(err.message).to eq(
            "CloudIO::Error: Max Retries (1) Exceeded!\n" \
            "  Operation: DELETE SLO Manifest 'my_container/obj_b_name'\n" \
            "  Be sure to check the log messages for each retry attempt.\n" \
            "--- Wrapped Exception ---\n" \
            "RuntimeError: failure"
          )
        }
        expect(Logger.messages.map(&:lines).join("\n")).to eq(
          "CloudIO::Error: Retry #1 of 1\n" \
          "  Operation: DELETE SLO Manifest 'my_container/obj_a_name'\n" \
          "--- Wrapped Exception ---\n" \
          "RuntimeError: error message\n" \
          "CloudIO::Error: Retry #1 of 1\n" \
          "  Operation: DELETE SLO Manifest 'my_container/obj_b_name'\n" \
          "--- Wrapped Exception ---\n" \
          "CloudIO::CloudFiles::Error: 400 Bad Request\n" \
          "  The server returned the following:\n" \
          "  {\"Response Status\"=>\"400 Bad Request\"}"
        )
      end
    end # describe '#delete_slo'

    describe "#connection" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          username: "my_username",
          api_key: "my_api_key",
          auth_url: "my_auth_url",
          region: "my_region",
          servicenet: false
        )
      end

      it "caches a connection" do
        expect(Fog::Storage).to receive(:new).once.with(
          provider: "Rackspace",
          rackspace_username: "my_username",
          rackspace_api_key: "my_api_key",
          rackspace_auth_url: "my_auth_url",
          rackspace_region: "my_region",
          rackspace_servicenet: false
        ).and_return(connection)

        expect(cloud_io.send(:connection)).to be connection
        expect(cloud_io.send(:connection)).to be connection
      end

      it "passes along fog_options" do
        expect(Fog::Storage).to receive(:new).with(provider: "Rackspace",
                                          rackspace_username: "my_user",
                                          rackspace_api_key: "my_key",
                                          rackspace_auth_url: nil,
                                          rackspace_region: nil,
                                          rackspace_servicenet: nil,
                                          connection_options: { opt_key: "opt_value" },
                                          my_key: "my_value")
        CloudIO::CloudFiles.new(
          username: "my_user",
          api_key: "my_key",
          fog_options: {
            connection_options: { opt_key: "opt_value" },
            my_key: "my_value"
          }
        ).send(:connection)
      end
    end # describe '#connection'

    describe "#create_containers" do
      context "with SLO support" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            container: "my_container",
            segments_container: "my_segments_container",
            max_retries: 1,
            retry_waitsec: 0
          )
        end
        before do
          allow(cloud_io).to receive(:connection).and_return(connection)
        end

        it "creates containers once with retries" do
          expect(connection).to receive(:put_container).twice
            .with("my_container")
          expect(connection).to receive(:put_container).once
            .with("my_segments_container")
            .and_raise("error")
          expect(connection).to receive(:put_container).once
            .with("my_segments_container")
            .and_return(nil)

          cloud_io.send(:create_containers)
          cloud_io.send(:create_containers)
        end
      end

      context "without SLO support" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            container: "my_container",
            max_retries: 1,
            retry_waitsec: 0
          )
        end
        before do
          allow(cloud_io).to receive(:connection).and_return(connection)
        end

        it "creates containers once with retries" do
          expect(connection).to receive(:put_container).once
            .with("my_container")
            .and_raise("error")
          expect(connection).to receive(:put_container).once
            .with("my_container")
            .and_return(nil)

          cloud_io.send(:create_containers)
          cloud_io.send(:create_containers)
        end
      end
    end # describe '#create_containers'

    describe "#put_object" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end
      let(:file) { double }

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
        md5_file = double
        expect(Digest::MD5).to receive(:file).with("/src/file").and_return(md5_file)
        expect(md5_file).to receive(:hexdigest).and_return("abc123")
      end

      it "calls put_object with ETag" do
        expect(File).to receive(:open).with("/src/file", "r").and_yield(file)
        expect(connection).to receive(:put_object)
          .with("my_container", "dest/file", file, "ETag" => "abc123")
        cloud_io.send(:put_object, "/src/file", "dest/file")
      end

      it "fails after retries" do
        expect(File).to receive(:open).twice.with("/src/file", "r").and_yield(file)
        expect(connection).to receive(:put_object).once
          .with("my_container", "dest/file", file, "ETag" => "abc123")
          .and_raise("error1")
        expect(connection).to receive(:put_object).once
          .with("my_container", "dest/file", file, "ETag" => "abc123")
          .and_raise("error2")

        expect do
          cloud_io.send(:put_object, "/src/file", "dest/file")
        end.to raise_error(CloudIO::Error) { |err|
          expect(err.message).to eq(
            "CloudIO::Error: Max Retries (1) Exceeded!\n" \
            "  Operation: PUT 'my_container/dest/file'\n" \
            "  Be sure to check the log messages for each retry attempt.\n" \
            "--- Wrapped Exception ---\n" \
            "RuntimeError: error2"
          )
        }
        expect(Logger.messages.map(&:lines).join("\n")).to eq(
          "CloudIO::Error: Retry #1 of 1\n" \
          "  Operation: PUT 'my_container/dest/file'\n" \
          "--- Wrapped Exception ---\n" \
          "RuntimeError: error1"
        )
      end

      context "with #days_to_keep set" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            container: "my_container",
            days_to_keep: 1,
            max_retries: 1,
            retry_waitsec: 0
          )
        end
        let(:delete_at) { cloud_io.send(:delete_at) }

        it "call put_object with X-Delete-At" do
          expect(File).to receive(:open).with("/src/file", "r").and_yield(file)
          expect(connection).to receive(:put_object).with(
            "my_container", "dest/file", file,
            "ETag" => "abc123", "X-Delete-At" => delete_at
          )
          cloud_io.send(:put_object, "/src/file", "dest/file")
        end
      end
    end # describe '#put_object'

    describe "#upload_segments" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          segments_container: "my_segments_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end
      let(:segment_bytes) { 1024**2 * 2 }
      let(:file_size) { segment_bytes + 250 }
      let(:digest_a) { "de89461b64701958984c95d1bfb0065a" }
      let(:digest_b) { "382b6d2c391ad6871a9878241ef64cc9" }
      let(:file) { StringIO.new(("a" * segment_bytes) + ("b" * 250)) }

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
      end

      it "uploads segments with ETags" do
        expect(File).to receive(:open).with("/src/file", "r").and_yield(file)

        expect(cloud_io).to receive(:with_retries)
          .with("PUT 'my_segments_container/dest/file/0001'").and_yield
        expect(connection).to receive(:put_object).with(
          "my_segments_container", "dest/file/0001", nil,
          "ETag" => digest_a
        ).and_yield.and_yield.and_yield # twice to read 2 MiB, third should not read

        expect(cloud_io).to receive(:with_retries)
          .with("PUT 'my_segments_container/dest/file/0002'").and_yield
        expect(connection).to receive(:put_object).with(
          "my_segments_container", "dest/file/0002", nil,
          "ETag" => digest_b
        ).and_yield.and_yield # once to read 250 B, second should not read

        expected = [
          { path: "my_segments_container/dest/file/0001",
            etag: digest_a,
            size_bytes: segment_bytes },
          { path: "my_segments_container/dest/file/0002",
            etag: digest_b,
            size_bytes: 250 }
        ]
        expect(
          cloud_io.send(:upload_segments,
            "/src/file", "dest/file", segment_bytes, file_size)
        ).to eq expected
        expect(Logger.messages.map(&:lines).join("\n")).to eq(
          "  Uploading 2 SLO Segments...\n" \
          "  ...90% Complete..."
        )
      end

      it "logs progress" do
        segment_bytes = 1024**2 * 1
        file_size = segment_bytes * 100
        file = StringIO.new("x" * file_size)
        expect(File).to receive(:open).with("/src/file", "r").and_yield(file)
        allow(cloud_io).to receive(:segment_md5)
        allow(connection).to receive(:put_object).and_yield

        cloud_io.send(:upload_segments,
          "/src/file", "dest/file", segment_bytes, file_size)
        expect(Logger.messages.map(&:lines).join("\n")).to eq(
          "  Uploading 100 SLO Segments...\n" \
          "  ...10% Complete...\n" \
          "  ...20% Complete...\n" \
          "  ...30% Complete...\n" \
          "  ...40% Complete...\n" \
          "  ...50% Complete...\n" \
          "  ...60% Complete...\n" \
          "  ...70% Complete...\n" \
          "  ...80% Complete...\n" \
          "  ...90% Complete..."
        )
      end

      context "when #days_to_keep is set" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            segments_container: "my_segments_container",
            days_to_keep: 1,
            max_retries: 1,
            retry_waitsec: 0
          )
        end
        let(:delete_at) { cloud_io.send(:delete_at) }

        it "uploads segments with X-Delete-At" do
          expect(File).to receive(:open).with("/src/file", "r").and_yield(file)

          expect(connection).to receive(:put_object).with(
            "my_segments_container", "dest/file/0001", nil,
            "ETag" => digest_a, "X-Delete-At" => delete_at
          ).and_yield.and_yield # twice to read 2 MiB

          expect(connection).to receive(:put_object).with(
            "my_segments_container", "dest/file/0002", nil,
            "ETag" => digest_b, "X-Delete-At" => delete_at
          ).and_yield # once to read 250 B

          expected = [
            { path: "my_segments_container/dest/file/0001",
              etag: digest_a,
              size_bytes: segment_bytes },
            { path: "my_segments_container/dest/file/0002",
              etag: digest_b,
              size_bytes: 250 }
          ]
          expect(
            cloud_io.send(:upload_segments,
              "/src/file", "dest/file", segment_bytes, file_size)
          ).to eq expected
        end
      end
    end # describe '#upload_segments'

    describe "#upload_manifest" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end
      let(:segments) { double }

      before do
        allow(cloud_io).to receive(:connection).and_return(connection)
      end

      it "uploads manifest with retries" do
        expect(connection).to receive(:put_static_obj_manifest).once
          .with("my_container", "dest/file", segments, {})
          .and_raise("error")
        expect(connection).to receive(:put_static_obj_manifest).once
          .with("my_container", "dest/file", segments, {})
          .and_return(nil)

        cloud_io.send(:upload_manifest, "dest/file", segments)
      end

      it "fails when retries exceeded" do
        expect(connection).to receive(:put_static_obj_manifest).once
          .with("my_container", "dest/file", segments, {})
          .and_raise("error1")
        expect(connection).to receive(:put_static_obj_manifest).once
          .with("my_container", "dest/file", segments, {})
          .and_raise("error2")

        expect do
          cloud_io.send(:upload_manifest, "dest/file", segments)
        end.to raise_error(CloudIO::Error) { |err|
          expect(err.message).to eq(
            "CloudIO::Error: Max Retries (1) Exceeded!\n" \
            "  Operation: PUT SLO Manifest 'my_container/dest/file'\n" \
            "  Be sure to check the log messages for each retry attempt.\n" \
            "--- Wrapped Exception ---\n" \
            "RuntimeError: error2"
          )
        }
        expect(Logger.messages.map(&:lines).join("\n")).to eq(
          "  Storing SLO Manifest 'my_container/dest/file'\n" \
          "CloudIO::Error: Retry #1 of 1\n" \
          "  Operation: PUT SLO Manifest 'my_container/dest/file'\n" \
          "--- Wrapped Exception ---\n" \
          "RuntimeError: error1"
        )
      end

      context "with #days_to_keep set" do
        let(:cloud_io) do
          CloudIO::CloudFiles.new(
            container: "my_container",
            days_to_keep: 1,
            max_retries: 1,
            retry_waitsec: 0
          )
        end
        let(:delete_at) { cloud_io.send(:delete_at) }

        it "uploads manifest with X-Delete-At" do
          expect(connection).to receive(:put_static_obj_manifest)
            .with("my_container", "dest/file", segments, "X-Delete-At" => delete_at)

          cloud_io.send(:upload_manifest, "dest/file", segments)
        end
      end
    end # describe '#upload_manifest'

    describe "#headers" do
      let(:cloud_io) do
        CloudIO::CloudFiles.new(
          container: "my_container",
          max_retries: 1,
          retry_waitsec: 0
        )
      end

      it "returns empty headers" do
        expect(cloud_io.send(:headers)).to eq({})
      end

      context "with #days_to_keep set" do
        let(:cloud_io) { CloudIO::CloudFiles.new(days_to_keep: 30) }

        it "returns X-Delete-At header" do
          Timecop.freeze do
            expected = (Time.now.utc + 30 * 60**2 * 24).to_i
            headers = cloud_io.send(:headers)
            expect(headers["X-Delete-At"]).to eq expected
          end
        end

        it "returns the same headers for subsequent calls" do
          headers = cloud_io.send(:headers)
          expect(cloud_io.send(:headers)).to eq headers
        end
      end
    end # describe '#headers'

    describe "Object" do
      let(:cloud_io) { CloudIO::CloudFiles.new }
      let(:obj_data) { { "name" => "obj_name", "hash" => "obj_hash" } }
      let(:object) { CloudIO::CloudFiles::Object.new(cloud_io, obj_data) }

      describe "#initialize" do
        it "creates Object from data" do
          expect(object.name).to eq "obj_name"
          expect(object.hash).to eq "obj_hash"
        end
      end

      describe "#slo?" do
        it "returns true when object is an SLO" do
          expect(cloud_io).to receive(:head_object).once
            .with(object)
            .and_return(double("response",
              headers: { "X-Static-Large-Object" => "True" }))

          expect(object.slo?).to be(true)
          expect(object.slo?).to be(true)
        end

        it "returns false when object is not an SLO" do
          expect(cloud_io).to receive(:head_object)
            .with(object)
            .and_return(double("response", headers: {}))
          expect(object.slo?).to be(false)
        end
      end

      describe "#marked_for_deletion?" do
        it "returns true when object has X-Delete-At set" do
          expect(cloud_io).to receive(:head_object).once
            .with(object)
            .and_return(double("response",
              headers: { "X-Delete-At" => "12345" }))

          expect(object.marked_for_deletion?).to be(true)
          expect(object.marked_for_deletion?).to be(true)
        end

        it "returns false when object does not have X-Delete-At set" do
          expect(cloud_io).to receive(:head_object)
            .with(object)
            .and_return(double("response", headers: {}))
          expect(object.marked_for_deletion?).to be(false)
        end
      end
    end
  end
end
