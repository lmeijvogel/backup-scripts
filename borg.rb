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

  def extract(paths, archive_name:)
    paths_as_parameters = paths.map { |path| %("#{path}") }.join(' ')
    command = %(#{borg} extract #{ENV.fetch('BORG_REPO')}::#{archive_name} #{paths_as_parameters})

    system(ENV, command)

    Hash[paths.zip(paths)]
  end

  def borg
    '/usr/local/bin/borg'
  end
end
