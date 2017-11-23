require 'shellwords'

module Backends
  class B2
    def retrieve(files)
      Enumerator.new do |yielder|
        files.each do |filename|
          Open3.popen3("duplicacy cat #{Shellwords.shellescape(filename)}") do |_, stdout, _, _|
            File.open(File.basename(filename), 'w') do |download_file|
              download_file.write(stdout.read)
            end
          end

          absolute_download_path = File.expand_path(File.basename(filename))

          yielder.yield [filename, absolute_download_path]
        end
      end
    end
  end
end
