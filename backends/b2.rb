require 'shellwords'

module Backends
  class B2
    def retrieve(files)
      Enumerator.new do |yielder|
        files.each do |filename|
          output_basename = File.basename(filename)
          Open3.popen3("duplicacy cat #{Shellwords.shellescape(filename)}") do |_, stdout, _, _|
            IO.binwrite(output_basename, stdout.read)
          end

          absolute_download_path = File.expand_path(output_basename)

          yielder.yield [filename, absolute_download_path]
        end
      end
    end
  end
end
