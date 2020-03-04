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
require 'slop'

$LOAD_PATH << __dir__

require 'backends/borg'
require 'backends/b2'

Dotenv.load

PHOTOS_DIR = File.join(ENV.fetch('SOURCE_DIR'), 'My Pictures')

SHAS_FILE_NAME = 'shas.yml'.freeze

class BackupError < StandardError; end

class TestBackup
  attr_accessor :show_progress_bar

  def initialize
    @show_progress_bar = true
  end

  def create_shas_file
    write_files_and_shas_to_file(initial_collection: {}, additions: all_photos)
  end

  def update_shas_file
    existing_files_and_shas = files_and_shas

    new_files = all_photos - existing_files_and_shas.keys

    write_files_and_shas_to_file(initial_collection: existing_files_and_shas, additions: new_files)
  end

  def test_file_selection(files: nil, seed: random_seed)
    if files && files.any?
      puts 'Testing selected files'
      test_selected_files(files)
    else
      puts 'Testing latest files'
      test_latest_photos

      puts

      random = if (seed != :random_seed)
                 Random.new(seed)
               else
                 Random.new
               end

      puts "Testing random files (random seed: #{random.seed})"

      test_random_files(random: random)
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

  def test_random_files(random: SecureRandom)
    random_files_and_shas = files_and_shas.to_a.sample(10, random: random).to_h

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

    all_successful = in_temp_dir(tmp_path) do
      retrieve_from_backup(files_and_shas.keys, backend: ENV['BACKEND']).all? do |file, retrieved_file|
        test_backup_file(file,retrieved_file)
      end
    end

    raise BackupError unless all_successful
  end

  def test_backup_file(file, retrieved_file)
    file_successful = true

    $stdout.write("#{file}: ")
    $stdout.flush

    unless retrieved_file
      puts "ERROR! File not in backup!"

      return false
    end

    backed_up_sha = Digest::SHA256.file(retrieved_file).hexdigest
    stored_sha = files_and_shas[file]

    if backed_up_sha == stored_sha
      puts "SUCCESS"
    else
      puts "ERROR! SHA mismatch for #{file} => #{retrieved_file}"
      puts "SHA: backed up '#{backed_up_sha}' != stored '#{stored_sha}'"
      FileUtils.mkdir_p("/tmp/failed_files")

      FileUtils.mv(retrieved_file, File.join("/tmp/failed_files", File.basename(retrieved_file)))

      file_successful = false
    end

    file_successful
  rescue StandardError => e
    $stdout.puts("ERROR: Exception occurred! #{e.message}")

    file_successful = false

    raise
  end

  def write_files_and_shas_to_file(initial_collection:, additions:)
    if additions.length.zero?
      puts 'No new files to index'
      return
    end

    if @show_progress_bar
      progress_bar = ProgressBar.create(total: additions.count, format: '|%w>%i| %c/%C (%e)')
    end

    files_and_shas = additions.each_with_object(initial_collection) do |file, result|
      digest = Digest::SHA256.file(file).hexdigest

      if @show_progress_bar
        progress_bar.increment
      end

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

options = Slop.parse do |o|
  o.banner = "usage: ./test_backup.rb [options] [files]"

  o.bool '--no-progress-bar', "Do not show progress bar"
  o.bool '--create-sha-file', "Create a new SHA file"
  o.bool '--update-sha-file', "Add new entries to the SHA file"
  o.bool '--test', "Test backed up files against the SHA file database"
  o.integer '--seed', "Seed the RNG for random files"
end

seed = options[:seed] || :random_seed
files = options.arguments

if options[:no_progress_bar]
  backup_tester.show_progress_bar = false
end

action = if options["create-sha-file"]
           ->() { backup_tester.create_shas_file }
         elsif options["update-sha-file"]
           ->() { backup_tester.update_shas_file }
         elsif options.test?
           ->() { backup_tester.update_shas_file ; backup_tester.test_file_selection(files: files, seed: seed) }
         end

if action.nil?
  puts options
  exit 1
end

begin
  action.call
rescue BackupError
  exit 1
rescue StandardError => e
  puts "!! ERROR: Exception raised: #{e.message}"
  puts e.backtrace

  exit 2
end
