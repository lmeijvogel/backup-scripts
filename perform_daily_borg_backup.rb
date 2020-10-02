#!/usr/bin/env ruby

require 'date'
require 'open3'
require 'shellwords'
require 'fileutils'

require 'bundler'

Bundler.load

require 'dotenv'

# This is necessary for running the script with `bash -c` from Scheduled Tasks
FileUtils.cd(__dir__)

$LOAD_PATH << __dir__

require 'backends/borg'

Dotenv.load

def get_backup_list
  return @names if @_names_set

  @names = Backends::Borg.new.list.each_line.map(&:split).map(&:first)

  @_names_set = true

  @names
end

def unique_backup_name
  puts "Finding unique name"
  basename = "desktop-#{Date.today.strftime("%Y-%m-%d")}"

  alternatives = (1..99).map do |n|
    sprintf("#{basename}_%02d", n)
  end

  ([basename]+alternatives).find do |name|
    !get_backup_list.include?(name)
  end.tap do |name|
    puts "... Found: #{name}"
  end
end

def perform_backup
  backup_name = unique_backup_name

  puts "Backing up to '#{backup_name}'"

  Backends::Borg.new.backup(backup_name, source: ENV.fetch("SOURCE_DIR"))
end

perform_backup
