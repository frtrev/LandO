#!/bin/sh
set -eu
# Flutter 3.47 regenerates the plugin package with its default iOS 15 target.
# Keep that generated app package aligned with Runner after framework prepare.
# Do not modify dependency packages or lower a vendor's minimum requirement.
ios_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
/usr/bin/ruby - "$ios_dir/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift" "$ios_dir/Runner.xcodeproj/project.pbxproj" <<'RUBY'
require 'rubygems'
manifest, project = ARGV
exit 0 unless File.exist?(manifest)
minimums = File.read(project).scan(/IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);/).flatten.uniq
abort 'Keep all Runner deployment targets aligned before building.' unless minimums.length == 1
minimum = minimums.first
text = File.read(manifest)
updated = text.sub(/\.iOS\("([0-9.]+)"\)/) do |match|
  Gem::Version.new($1) < Gem::Version.new(minimum) ? ".iOS(\"#{minimum}\")" : match
end
File.write(manifest, updated) if updated != text
RUBY
