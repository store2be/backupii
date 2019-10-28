# frozen_string_literal: true

require "spec_helper"

describe "Backup::Pipeline" do
  let(:pipeline) { Backup::Pipeline.new }

  it "should include Utilities::Helpers" do
    expect(Backup::Pipeline
      .include?(Backup::Utilities::Helpers)).to eq(true)
  end

  describe "#initialize" do
    it "should create a new pipeline" do
      expect(pipeline.instance_variable_get(:@commands)).to eq([])
      expect(pipeline.instance_variable_get(:@success_codes)).to eq([])
      expect(pipeline.errors).to eq([])
      expect(pipeline.stderr).to eq("")
    end
  end

  describe "#add" do
    it "should add a command with the given successful exit codes" do
      pipeline.add "a command", [0]
      expect(pipeline.instance_variable_get(:@commands)).to eq(["a command"])
      expect(pipeline.instance_variable_get(:@success_codes)).to eq([[0]])

      pipeline.add "another command", [1, 3]
      expect(pipeline.instance_variable_get(:@commands))
        .to eq(["a command", "another command"])
      expect(pipeline.instance_variable_get(:@success_codes))
        .to eq([[0], [1, 3]])
    end
  end

  describe "#<<" do
    it "should add a command with the default successful exit code (0)" do
      expect(pipeline).to receive(:add).with("a command", [0])
      pipeline << "a command"
    end
  end

  describe "#run" do
    let(:stdout) { double }
    let(:stderr) { double }

    before do
      allow_any_instance_of(Backup::Pipeline).to receive(:run).and_call_original
      expect(pipeline).to receive(:pipeline).and_return("foo")
      # stub Utilities::Helpers#command_name so it simply returns what it's passed
      pipeline.class.send(:define_method, :command_name, ->(arg) { arg })
    end

    context "when pipeline command is successfully executed" do
      before do
        expect(Open4).to receive(:popen4).with("foo").and_yield(nil, nil, stdout, stderr)
      end

      context "when all commands within the pipeline are successful" do
        before do
          pipeline.instance_variable_set(:@success_codes, [[0], [0, 3]])
          expect(stdout).to receive(:read).and_return("0|0:1|3:\n")
        end

        context "when commands output no stderr messages" do
          before do
            expect(stderr).to receive(:read).and_return("")
            allow(pipeline).to receive(:stderr_messages).and_return(false)
          end

          it "should process the returned stdout/stderr and report no errors" do
            expect(Backup::Logger).to receive(:warn).never

            pipeline.run
            expect(pipeline.stderr).to eq("")
            expect(pipeline.errors).to eq([])
          end
        end

        context "when successful commands output messages on stderr" do
          before do
            expect(stderr).to receive(:read).and_return("stderr output\n")
            allow(pipeline).to receive(:stderr_messages).and_return("stderr_messages_output")
          end

          it "should log a warning with the stderr messages" do
            expect(Backup::Logger).to receive(:warn).with("stderr_messages_output")

            pipeline.run
            expect(pipeline.stderr).to eq("stderr output")
            expect(pipeline.errors).to eq([])
          end
        end
      end # context 'when all commands within the pipeline are successful'

      context "when commands within the pipeline are not successful" do
        before do
          pipeline.instance_variable_set(:@commands, %w[first second third])
          pipeline.instance_variable_set(:@success_codes, [[0, 1], [0, 3], [0]])
          expect(stderr).to receive(:read).and_return("stderr output\n")
          allow(pipeline).to receive(:stderr_messages).and_return("success? should be false")
        end

        context "when the commands return in sequence" do
          before do
            expect(stdout).to receive(:read).and_return("0|1:1|1:2|0:\n")
          end

          it "should set @errors and @stderr without logging warnings" do
            expect(Backup::Logger).to receive(:warn).never

            pipeline.run
            expect(pipeline.stderr).to eq("stderr output")
            expect(pipeline.errors.count).to be(1)
            expect(pipeline.errors.first).to be_a_kind_of SystemCallError
            expect(pipeline.errors.first.errno).to be(1)
            expect(pipeline.errors.first.message).to match(
              "'second' returned exit code: 1"
            )
          end
        end # context 'when the commands return in sequence'

        context "when the commands return out of sequence" do
          before do
            expect(stdout).to receive(:read).and_return("1|3:2|4:0|1:\n")
          end

          it "should properly associate the exitstatus for each command" do
            expect(Backup::Logger).to receive(:warn).never

            pipeline.run
            expect(pipeline.stderr).to eq("stderr output")
            expect(pipeline.errors.count).to be(1)
            expect(pipeline.errors.first).to be_a_kind_of SystemCallError
            expect(pipeline.errors.first.errno).to be(4)
            expect(pipeline.errors.first.message).to match(
              "'third' returned exit code: 4"
            )
          end
        end # context 'when the commands return out of sequence'

        context "when multiple commands fail (out of sequence)" do
          before do
            expect(stdout).to receive(:read).and_return("1|1:2|0:0|3:\n")
          end

          it "should properly associate the exitstatus for each command" do
            expect(Backup::Logger).to receive(:warn).never

            pipeline.run
            expect(pipeline.stderr).to eq("stderr output")
            expect(pipeline.errors.count).to be(2)
            pipeline.errors.each { |err| expect(err).to be_a_kind_of SystemCallError }
            expect(pipeline.errors[0].errno).to be(3)
            expect(pipeline.errors[0].message).to match(
              "'first' returned exit code: 3"
            )
            expect(pipeline.errors[1].errno).to be(1)
            expect(pipeline.errors[1].message).to match(
              "'second' returned exit code: 1"
            )
          end
        end # context 'when the commands return (out of sequence)'
      end # context 'when commands within the pipeline are not successful'
    end # context 'when pipeline command is successfully executed'

    context "when pipeline command fails to execute" do
      before do
        expect(Open4).to receive(:popen4).with("foo").and_raise("exec failed")
      end

      it "should raise an error" do
        expect do
          pipeline.run
        end.to raise_error(Backup::Pipeline::Error) { |err|
          expect(err.message).to eq(
            "Pipeline::Error: Pipeline failed to execute\n" \
            "--- Wrapped Exception ---\n" \
            "RuntimeError: exec failed"
          )
        }
      end
    end # context 'when pipeline command fails to execute'
  end # describe '#run'

  describe "#success?" do
    it "returns true when @errors is empty" do
      expect(pipeline.success?).to eq(true)
    end

    it "returns false when @errors is not empty" do
      pipeline.instance_variable_set(:@errors, ["foo"])
      expect(pipeline.success?).to eq(false)
    end
  end # describe '#success?'

  describe "#error_messages" do
    let(:sys_err) { RUBY_VERSION < "1.9" ? "SystemCallError" : "Errno::NOERROR" }

    before do
      # use 0 since others may be platform-dependent
      pipeline.instance_variable_set(
        :@errors, [
          SystemCallError.new("first error", 0),
          SystemCallError.new("second error", 0)
        ]
      )
    end

    context "when #stderr_messages has messages" do
      before do
        expect(pipeline).to receive(:stderr_messages).and_return("stderr messages\n")
      end

      it "should output #stderr_messages and formatted system error messages" do
        expect(pipeline.error_messages).to match(%r{
          stderr\smessages\n
          The\sfollowing\ssystem\serrors\swere\sreturned:\n
          #{sys_err}:\s(.*?)\sfirst\serror\n
          #{sys_err}:\s(.*?)\ssecond\serror
        }x)
      end
    end

    context "when #stderr_messages has no messages" do
      before do
        expect(pipeline).to receive(:stderr_messages).and_return("stderr messages\n")
      end

      it "should only output the formatted system error messages" do
        expect(pipeline.error_messages).to match(%r{
          stderr\smessages\n
          The\sfollowing\ssystem\serrors\swere\sreturned:\n
          #{sys_err}:\s(.*?)\sfirst\serror\n
          #{sys_err}:\s(.*?)\ssecond\serror
        }x)
      end
    end
  end # describe '#error_messages'

  describe "#pipeline" do
    context "when there are multiple system commands to execute" do
      before do
        pipeline.instance_variable_set(:@commands, %w[one two three])
      end

      it "should build a pipeline with redirected/collected exit codes" do
        expect(pipeline.send(:pipeline)).to eq(
          '{ { one 2>&4 ; echo "0|$?:" >&3 ; } | ' \
          '{ two 2>&4 ; echo "1|$?:" >&3 ; } | ' \
          '{ three 2>&4 ; echo "2|$?:" >&3 ; } } 3>&1 1>&2 4>&2'
        )
      end
    end

    context "when there is only one system command to execute" do
      before do
        pipeline.instance_variable_set(:@commands, ["foo"])
      end

      it "should build the command line in the same manner, but without pipes" do
        expect(pipeline.send(:pipeline)).to eq(
          '{ { foo 2>&4 ; echo "0|$?:" >&3 ; } } 3>&1 1>&2 4>&2'
        )
      end
    end
  end # describe '#pipeline'

  describe "#stderr_message" do
    context "when @stderr has messages" do
      before do
        pipeline.instance_variable_set(:@stderr, "stderr message\n output")
      end

      it "should return a formatted message with the @stderr messages" do
        expect(pipeline.send(:stderr_messages)).to eq(
          "  Pipeline STDERR Messages:\n" \
          "  (Note: may be interleaved if multiple commands returned error messages)\n" \
          "\n" \
          "  stderr message\n" \
          "  output\n"
        )
      end
    end

    context "when @stderr is empty" do
      it "should return false" do
        expect(pipeline.send(:stderr_messages)).to eq(false)
      end
    end
  end # describe '#stderr_message'
end # describe 'Backup::Pipeline'
