# frozen_string_literal: true

module Backup
  module Syncer
    module RSync
      class Local < Base
        def perform!
          log!(:started)

          create_dest_path!
          run("#{rsync_command} #{paths_to_push} '#{dest_path}'")

          log!(:finished)
        end

        private

        # Expand path, since this is local and shell-quoted.
        def dest_path
          @dest_path ||= File.expand_path(path)
        end

        def create_dest_path!
          FileUtils.mkdir_p dest_path
        end
      end
    end
  end
end
