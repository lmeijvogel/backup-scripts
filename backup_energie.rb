#!/usr/bin/env ruby

require 'bundler'

Bundler.load

require 'dotenv'
require 'tempfile'
require 'fileutils'
require 'net/ssh'

Dotenv.load(File.join(__dir__, '.energie-backup.env'))

def main
  host, user, id_rsa = ENV.to_h.fetch_values('SSH_HOST',
                                             'SSH_USER',
                                             'SSH_KEYFILE')

  puts id_rsa
  Net::SSH.start(host, user, keys: [id_rsa]) do |ssh|
    save_db_dump(ssh, ENV.fetch('BACKUP_FILE'))
  end
end

def connection_params
  {
    user: ENV.fetch('DB_USER'),
    password: ENV.fetch('DB_PASS'),
    db: ENV.fetch('DB_NAME')
  }
end

def save_db_dump(ssh, filename)
  retrieve_db_dump(ssh) do |backup_temp_file|
    FileUtils.cp(backup_temp_file.path, filename)
  end

  puts
  puts 'Done'
end

def retrieve_db_dump(ssh)
  filled_in_command = format(command, connection_params)

  Tempfile.open('energie_backup') do |backup_temp_file|
    ssh.exec!(filled_in_command) do |_channel, stream, data|
      case stream
      when :stdout
        backup_temp_file.write(data)
        $stdout.write('.')
      when :stderr
        puts "ERROR: #{data}"
      else
        raise "Unknown stream #{stream}"
      end
    end

    backup_temp_file.flush
    backup_temp_file.rewind

    yield backup_temp_file
  end
end

def command
  'mysqldump --lock-tables=false -u %<user>s --password=%<password>s %<db>s'
end

main
