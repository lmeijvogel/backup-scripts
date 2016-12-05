require 'open3'

class Borg
  def list
    list_backups_command = "/usr/local/bin/borg list #{ENV.fetch('BORG_REPO')}"

    stdout, _, _ = Open3.capture3(ENV, list_backups_command)

    return stdout
  end

  def backup(backup_name, source:)

    command = "/usr/local/bin/borg create -v --progress --stats #{ENV.fetch('BORG_REPO')}::#{backup_name} #{Shellwords.shellescape(source)}"
    pid = spawn(ENV, command)

    Process.wait(pid)
  end

  def extract(paths, archive_name:)
    relative_paths = paths.map { |path| path[1..-1] }

    paths_as_parameters = relative_paths.map { |path| %|"#{path}"| }.join(" ")
    command = %|/usr/local/bin/borg extract #{ENV.fetch("BORG_REPO")}::#{archive_name} #{paths_as_parameters}|
    system(ENV, command)

    Hash[paths.zip(relative_paths)]
  end
end
