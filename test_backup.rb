#!/usr/bin/env ruby
require 'securerandom'
require 'digest'
require 'fileutils'
require 'yaml'

require 'dotenv'
require 'ruby-progressbar'

$LOAD_PATH << __dir__
require 'borg'

Dotenv.load

PHOTOS_DIR = File.join(ENV.fetch("SOURCE_DIR"), "My Pictures")

SHAS_FILE_NAME="shas.yml"


class TestBackup
  def create_shas_file
    write_files_and_shas_to_file(initial_collection: {}, additions: all_photos)
  end

  def update_shas_file
    existing_files_and_shas = files_and_shas

    new_files = all_photos - existing_files_and_shas.keys

    write_files_and_shas_to_file(initial_collection: existing_files_and_shas, additions: new_files)
  end

  def test_random_files
    random_files_and_shas = files_and_shas.to_a.sample(10, random: SecureRandom).to_h

    retrieve_from_backup(random_files_and_shas.keys) do |files_and_retrieved_files|
      files_and_retrieved_files.each do |file, retrieved_file|
        backed_up_sha = Digest::SHA256.hexdigest(File.read(retrieved_file))

        if backed_up_sha == random_files_and_shas[file]
          puts "SUCCESS: #{file}"
        else
          puts "ERROR! SHA mismatch for #{file}"
        end
      end
    end
  end

  private
  def write_files_and_shas_to_file(initial_collection:, additions:)
    if additions.length.zero?
      puts "No files to add"
      return
    end

    progress_bar = ProgressBar.create(total: additions.count, format: "|%w>%i| %c/%C (%e)")

    files_and_shas = additions.inject(initial_collection) do |acc, file|
      digest = Digest::SHA256.hexdigest(File.read(file))

      progress_bar.increment

      acc[file] = digest
      acc
    end

    File.open(SHAS_FILE_NAME, "w") do |file|
      file.write({"shas" => files_and_shas}.to_yaml)
    end
  end

  def retrieve_from_backup(files)
    tmp_path = "tmp_retrieve"

    in_temp_dir(tmp_path) do
      input_and_download_paths = Borg.new.extract(files, archive_name: latest_archive)

      inputs_and_absolute_download_paths = input_and_download_paths.to_a.map do |file, download_path|
        [file, File.expand_path(download_path)]
      end.to_h

      yield inputs_and_absolute_download_paths
    end
  end

  def latest_archive
    archive_names = Borg.new.list.each_line.map(&:split).map(&:first)

    archive_names.sort.last
  end

  def in_temp_dir(path)
    FileUtils.mkdir_p(path)

    current_path = Dir.pwd
    FileUtils.cd(path)

    yield
  ensure
    FileUtils.cd(current_path)
    FileUtils.rm_rf(path)
  end

  def files_and_shas
    @files_and_shas ||= YAML.load(File.read(SHAS_FILE_NAME))["shas"]
  end

  def all_photos
    @all_photos ||= Dir.glob(File.join(PHOTOS_DIR, "**", "*.{JPG,jpg}"))
  end
end

allowed_params = {
  "--create-sha-file" => ->() { TestBackup.new.create_shas_file },
  "--update-sha-file" => ->() { TestBackup.new.update_shas_file },
  "--test"            => ->() { TestBackup.new.test_random_files }
}

action = allowed_params.keys.detect do |key|
  ARGV.include?(key)
end

if action.nil?
  puts "Allowed actions: "

  allowed_params.keys.each do |param|
    puts "  #{param}"
  end

  exit 1
end

allowed_params[action].call
