# frozen_string_literal: true

require File.expand_path("lib/backup/version")

Gem::Specification.new do |gem|
  gem.name        = "backupii"
  gem.version     = Backup::VERSION
  gem.authors     = ["Michael van Rooijen"]
  gem.email       = "contact@lta.io"
  gem.metadata    = {
    "homepage_uri" => "https://backupii.github.io/backupii/",
    "documentation_uri" => "https://backupii.github.io/backupii/",
    "bug_tracker_uri" => "https://github.com/backupii/backupii/issues",
    "source_code_uri" => "https://github.com/backupii/backupii"
  }
  gem.license     = "MIT"
  gem.summary     = "Provides an elegant DSL in Ruby for performing backups "\
    "on UNIX-like systems."
  gem.description = <<-EOS.gsub(%r{\s+}, " ").strip
    BackupII is a RubyGem, written for UNIX-like operating systems, that allows
    you to easily perform backup operations on both your remote and local
    environments. It provides you with an elegant DSL in Ruby for modeling your
    backups. BackupII has built-in support for various databases, storage
    protocols/services, syncers, compressors, encryptors and notifiers which
    you can mix and match. It was built with modularity, extensibility and
    simplicity in mind.
  EOS

  gem.files = `git ls-files -- lib bin templates README.md LICENSE`.split("\n")
  gem.require_path  = "lib"
  gem.executables   = ["backupii"]

  gem.required_ruby_version = ">= 2.0"

  gem.add_dependency "aws-sdk", "~> 2"
  gem.add_dependency "dogapi", "1.11.0"
  gem.add_dependency "dropbox-sdk", "1.6.5"
  gem.add_dependency "excon", "~> 0.44"
  gem.add_dependency "flowdock", "0.4.0"
  gem.add_dependency "fog", "~> 1.28"
  gem.add_dependency "hipchat", "1.0.1"
  gem.add_dependency "mail", "~> 2.6", ">= 2.6.6"
  gem.add_dependency "net-scp", "1.2.1"
  gem.add_dependency "net-sftp", "2.1.2"
  gem.add_dependency "net-ssh", "4.2.0"
  gem.add_dependency "nokogiri", "~> 1.8", ">= 1.8.1"
  gem.add_dependency "open4", "1.3.0"
  gem.add_dependency "pagerduty", "2.0.0"
  gem.add_dependency "qiniu", "~> 6.5"
  gem.add_dependency "thor", "~> 0.18", ">= 0.18.1"
  gem.add_dependency "twitter", "~> 5.16.0"
  gem.add_dependency "unf", "0.1.3" # for fog/AWS

  gem.add_development_dependency "rake", "~> 13.0.0"
  gem.add_development_dependency "rspec", "3.8.0"
  gem.add_development_dependency "rubocop", "0.75.1"
  gem.add_development_dependency "timecop", "0.9.1"
end
