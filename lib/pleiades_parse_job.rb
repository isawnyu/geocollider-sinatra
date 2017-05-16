require 'sucker_punch'

class PleiadesParseJob
  include SuckerPunch::Job
  workers 1
  @@semaphore = Mutex.new

  def perform(parses, pleiades, filenames, string_normalizer, normalizations)
    @@semaphore.synchronize {
      unless parses.has_key?(normalizations)
        $stderr.puts "No existing parse for normalizations: #{normalizations.join(' ')}\nParsing..."
        parses[normalizations] = pleiades.parse(filenames, string_normalizer)
        $stderr.puts "Parsing done for normalizations: #{normalizations.join(' ')}"
      end
    }
  end
end
