#!/usr/bin/env ruby
require 'securerandom'
require 'digest'
require 'fileutils'
require 'yaml'

require 'shellwords'
require 'open3'
require 'tempfile'

require 'dotenv'
require 'ruby-progressbar'

$LOAD_PATH << __dir__

require 'borg'

Dotenv.load

PHOTOS_DIR = File.join(ENV.fetch('SOURCE_DIR'), 'My Pictures')

SHAS_FILE_NAME = 'shas.yml'.freeze


class TestBackup
  def create_shas_file
    write_files_and_shas_to_file(initial_collection: {}, additions: all_photos)
  end

  def update_shas_file
    existing_files_and_shas = files_and_shas

    new_files = all_photos - existing_files_and_shas.keys

    write_files_and_shas_to_file(initial_collection: existing_files_and_shas, additions: new_files)
  end

  def test_file_selection(files)
    if files.any?
      test_selected_files(files)
    else
      puts 'Testing latest files'
      test_latest_photos

      puts

      puts 'Testing random files'
      test_random_files
    end
  end

  def test_selected_files(files)
    selected_files_and_shas = files_and_shas.select { |key, _| files.include?(key) }

    if selected_files_and_shas.empty?
      puts 'No files exist!'
      exit 1
    elsif selected_files_and_shas.length != files.length
      puts 'Some files do not exist'
      exit 2
    end

    test_files(selected_files_and_shas)
  end

  def test_random_files
    random_files_and_shas = files_and_shas.to_a.sample(10, random: SecureRandom).to_h

    test_files(random_files_and_shas)
  end

  def test_latest_photos
    latest_files_and_shas = Hash[files_and_shas.to_a.reverse.take(10)]

    test_files(latest_files_and_shas)
  end

  private

  def test_files(files_and_shas)
    tmp_path = 'tmp_retrieve'

    in_temp_dir(tmp_path) do
      retrieve_from_borgbackup(files_and_shas.keys) do |file, retrieved_file|
        backed_up_sha = Digest::SHA256.hexdigest(File.read(retrieved_file))

        if backed_up_sha == files_and_shas[file]
          puts "SUCCESS: #{file}"
        else
          puts "ERROR! SHA mismatch for #{file}"
        end
      end
    end
  end

  def write_files_and_shas_to_file(initial_collection:, additions:)
    if additions.length.zero?
      puts 'No new files'
      return
    end

    progress_bar = ProgressBar.create(total: additions.count, format: '|%w>%i| %c/%C (%e)')

    files_and_shas = additions.inject(initial_collection) do |acc, file|
      digest = Digest::SHA256.hexdigest(File.read(file))

      progress_bar.increment

      acc[file] = digest
      acc
    end

    File.open(SHAS_FILE_NAME, 'w') do |file|
      file.write({ 'shas' => files_and_shas }.to_yaml)
    end
  end

  def retrieve_from_b2(files)
    files.each do |filename|
      Open3.popen3("duplicacy cat #{Shellwords.shellescape(filename)}") do |_, stdout, stderr, wait_thread|
        File.open(File.basename(filename), 'w') do |download_file|
          download_file.write(stdout.read)
        end
      end

      download_path = File.expand_path(File.basename(filename))
      yield [filename, download_path]
    end
  end

  def retrieve_from_borgbackup(files)
    input_and_download_paths = Borg.new.extract(files, archive_name: latest_archive)

    inputs_and_absolute_download_paths = input_and_download_paths.to_a.map do |file, download_path|
      [file, File.expand_path(download_path)]
    end.to_h

    inputs_and_absolute_download_paths.each do |input, absolute_download_path|
      yield [input, absolute_download_path]
    end
  end

  def latest_archive
    archive_names = Borg.new.list.each_line.map(&:split).map(&:first)

    archive_names.sort do |a, b|
      if a.end_with?('.checkpoint') && !b.end_with?('.checkpoint') && a.start_with?(b)
        -1
      else
        a <=> b
      end
    end.last
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
    @files_and_shas ||= YAML.safe_load(File.read(SHAS_FILE_NAME))['shas']
  end

  def all_photos
    glob = File.join(PHOTOS_DIR, '**', '*.{JPG,jpg}')
    @all_photos ||= Dir.glob(glob)
  end
end

backup_tester = TestBackup.new

allowed_params = {
  '--create-sha-file' => ->(_) { backup_tester.create_shas_file },
  '--update-sha-file' => ->(_) { backup_tester.update_shas_file },
  '--test'            => ->(files) { backup_tester.update_shas_file ; backup_tester.test_file_selection(files) }
}

action = allowed_params.keys.detect do |key|
  ARGV.include?(key)
end

if action.nil?
  puts 'Allowed actions: '

  allowed_params.each_key do |param|
    puts "  #{param}"
  end

  exit 1
end

allowed_params[action].call(ARGV[1..-1])
