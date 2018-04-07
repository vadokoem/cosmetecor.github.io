require 'sequel'
require 'logging'

Dir.chdir $0[0...$0.rindex('/')] if $0.index('/')

if RUBY_PLATFORM.downcase.index("x86_64-linux")
  require 'daemon'
  Daemon.daemonize('daemon.pid', '../log/log_daemon_content.log') if (ARGV.index('-d') || ARGV.index('-dc'))
end

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db', :max_connections => 4)

Sequel.default_timezone = :utc

class Generator
  
  def initialize
    @info = Logging.logger['content']
    @info.add_appenders(
      Logging.appenders.rolling_file('../log/info_content.log', :age => 'daily', :keep => 3)
    )
    @info.level = :info
    
    @error = Logging.logger['content_error']
    @error.add_appenders(
      Logging.appenders.rolling_file('../log/error_content.log', :age => 'daily', :keep => 3)
    )
    @error.level = :error
    @info.info "START #{Time.now}"
  end
  
  def start
    @threads = []
    @threads << Thread.new{
      count2 = get_count
      first = ARGV.index('-fd') ? 1 : 0
      while true
        count = count2
        count2 = get_count
        upd = []
        count.each do |k, v|
          (upd << k.to_s) unless count2[k] - v == 0 && first > 0
        end
        first += 1
        yes = Thread.new{
          system("ruby gen_image.rb -log '#{upd.inspect}'") if upd.size > 0
        }
        yes.join
        @info.info "Generate images in #{Time.now.strftime("%Y.%m.%d %H:%M:%S")}: #{upd}"
        sleep(360)
      end
    }
    @threads << Thread.new{
      count = 0
      while true
        count2 = $db[:lightning].count
        unless count2 == count
          count = count2
          t1 = Time.now
          system("ruby gen_kml_lightning.rb")
          @info.info "Time to generate lightnings: #{Time.now - t1}"
        end
        sleep(360)
      end
    }
    @threads << Thread.new{
      count = 0
      while true
        count2 = $db[:earth_usgs].count
        unless count2 == count
          count = count2
          t1 = Time.now            
          system("ruby gen_earth_quake_kml.rb")
          system("ruby select_magnitude_7.rb")
          @info.info "Time to generate quakes: #{Time.now - t1}"
        end
        sleep(360)
      end
    }
    @threads.each {|th| th.join}
  end
  
  def get_count
    count = {}
    tables = ['gu1', 'bo1', 'earth_kam', 'earth_usgs', 'geomagn_ap',
            'hemispheric_power_polar', 'radiation_belt',
            'sunspot']
    ['desp', 'desp-uz', 's1-elisovo',
     'ifpet', 's3-okean', 's4-esso',
     's5-altai', 's6-chieti', 's7-okean', 's8-imfset',
     's9-imfset', 's12-imfset-fiji'].each do |gg|
      tables << "se_measurements_#{gg}"
    end
    tables.each do |table|
      count[table.to_sym] = $db[table.to_sym].count if $db.table_exists? table.to_sym
    end
    count
  end
end

generator = Generator.new
generator.start