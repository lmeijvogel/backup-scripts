require 'open3'

class Borg
  def list
    list_backups_command = "/usr/local/bin/borg list #{ENV.fetch('BORG_REPO')}"

    stdout, = Open3.capture3(ENV, list_backups_command)

    stdout
  end

  def backup(backup_name, source:)
    backup_path = "#{ENV.fetch('BORG_REPO')}::#{backup_name}"

    command = "#{borg} create -v --progress --stats #{backup_path} #{Shellwords.shellescape(source)}"

    pid = spawn(ENV, command)

    Process.wait(pid)
  end

  def retrieve(files)
    Enumerator.new do |yielder|
      input_and_download_paths = extract(files, archive_name: latest_archive)

      inputs_and_absolute_download_paths = input_and_download_paths.to_a.map do |file, download_path|
        [file, File.expand_path(download_path)]
      end

      inputs_and_absolute_download_paths.each do |filename, absolute_download_path|
        yielder.yield [filename, absolute_download_path]
      end
    end
  end

  private

  def extract(paths, archive_name:)
    paths_as_parameters = paths.map { |path| %("#{path}") }.join(' ')
    command = %(#{borg} extract #{ENV.fetch('BORG_REPO')}::#{archive_name} #{paths_as_parameters})

    system(ENV, command)

    Hash[paths.zip(paths)].each
  end

  def latest_archive
    archive_names = list.each_line.map(&:split).map(&:first)

    archive_names.sort do |a, b|
      if a.end_with?('.checkpoint') && !b.end_with?('.checkpoint') && a.start_with?(b)
        -1
      else
        a <=> b
      end
    end.last
  end

  def borg
    '/usr/local/bin/borg'
  end
end
