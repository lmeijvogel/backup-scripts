module Backends
  class B2
    def retrieve(files)
      Enumerator.new do |yielder|
        files.each do |filename|
          file_contents, _, _ = Open3.capture3("duplicacy cat #{Shellwords.shellescape(filename)}")

          # Don't use regex match, since that might fail if the file looks enough like unicode.
          if file_contents.include?("found in snapshot")
            # File not found in backup
            yielder.yield [filename, nil]
          else
            output_basename = File.basename(filename)

            IO.binwrite(output_basename, file_contents)

            absolute_download_path = File.expand_path(output_basename)

            yielder.yield [filename, absolute_download_path]
          end
        end
      end
    end
  end
end
