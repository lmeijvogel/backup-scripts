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

require 'backends/borg'
require 'backends/b2'

Dotenv.load

PHOTOS_DIR = File.join(ENV.fetch('SOURCE_DIR'), 'My Pictures')

SHAS_FILE_NAME = 'shas.yml'.freeze

class BackupError < StandardError; end

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
    unless ENV.key?('BACKEND')
      puts 'Please specify BACKEND=borg or BACKEND=b2 in ENV.'
      exit 1
    end

    tmp_path = 'tmp_retrieve'

    all_successful = true
    in_temp_dir(tmp_path) do
      retrieve_from_backup(files_and_shas.keys, backend: ENV['BACKEND']).each do |file, retrieved_file|
        file_contents = File.read(retrieved_file)
        backed_up_sha = Digest::SHA256.hexdigest(file_contents)

        if backed_up_sha == files_and_shas[file]
          puts "SUCCESS: #{file}"
        else
          if file_contents =~ /not found in snapshot/
            puts "ERROR! File #{file} not in backup!"
          else
            puts "ERROR! SHA mismatch for #{file} => #{retrieved_file}"
            FileUtils.mkdir_p("/tmp/failed_files")

            FileUtils.mv(retrieved_file, File.join("/tmp/failed_files", File.basename(retrieved_file)))
          end

          all_successful = false
        end
      end
    end

    raise BackupError unless all_successful
  end

  def write_files_and_shas_to_file(initial_collection:, additions:)
    if additions.length.zero?
      puts 'No new files'
      return
    end

    progress_bar = ProgressBar.create(total: additions.count, format: '|%w>%i| %c/%C (%e)')

    files_and_shas = additions.each_with_object(initial_collection) do |file, result|
      digest = Digest::SHA256.hexdigest(File.read(file))

      progress_bar.increment

      result[file] = digest
    end

    File.open(SHAS_FILE_NAME, 'w') do |file|
      file.write({ 'shas' => files_and_shas }.to_yaml)
    end
  end

  def retrieve_from_backup(files, backend:)
    engine = if backend == 'b2'
               Backends::B2.new
             elsif backend == 'borg'
               Backends::Borg.new
             else
               raise "Unknown backend '#{backend}'"
             end

    engine.retrieve(files)
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

begin
  allowed_params[action].call(ARGV[1..-1])
rescue BackupError
  exit 1
rescue StandardError => e
  puts "!! ERROR: Exception raised: #{e.message}"
  puts e.backtrace

  exit 2
end
