require 'sequel'
require 'logging'
require 'fileutils'

$log = '-log' if ARGV[0] == '-log'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db', :max_connections => 4)

if $log
  $log_img = Logging.logger['image']
  $log_img.add_appenders(
    Logging.appenders.rolling_file('../log/images.log', :age => 'daily', :keep => 3)
  )
  $log_img.level = :info
end

Sequel.default_timezone = :utc

class Genie
  def initialize
    @graphs = []
  end

  def plot
    th_num = 4
    @th_arr = []
    (0...th_num).each {|i| @th_arr[i] = []}
    cook = 0
    while @graphs.size > 0
      @th_arr[cook] << @graphs.shift
      cook < th_num - 1 ? cook += 1 : cook = 0
    end
    ths = []
    (0...th_num).each do |number|
      ths << Thread.new {
        while @th_arr[number].size > 0
          titan = nil
          gr = @th_arr[number].shift#.pop#
          next unless $db.table_exists? gr[:table]
          t = Time.now #("gen_image_#{gr[:type]} gr")
          if gr[:table].to_s.index('se_meas')
            nnn = gr[:key].to_s.tr('^0-9', '').to_i
            retr = $db[:channels_name].where(:code => "#{gr[:table]}")
            title = retr.where(:channel_num => nnn + 1).first
            titan = title[:channel_name_eng].gsub('~','=') unless title.nil?
            title = retr.where(:channel_num => (nnn + 1) - retr.count).first if title.nil?
            titan = title[:channel_name_eng] if titan.nil?
            gr[:path] = "../temp/#{titan}-#{gr[:days]}.png"
          end
          system("ruby gnuplot.rb '#{gr}' #{$log}")
          $log_img.info "#{gr[:path]} - generate!" if $log
          gr[:path] = "../temp/test-#{titan}-#{gr[:days]}.png" if gr[:type] == :line_hms_large_average
          gr[:path] = "../temp/event-#{titan}-#{gr[:days]}.png" if gr[:type] == :line_hms_large_event
          tries = 0
          big_problem = nil
          while !File.exists? gr[:path]
            tries += 1
            sleep 0.1 if tries < 50
            ($log_img.error "#{gr[:path]} - dead generate!"; big_problem = true; break) if tries >= 50
          end
          if big_problem.nil?
            begin
              new_path = gr[:path].dup
              new_path[0..6] = "../web/public/images_ruby"
              new_path['/images_ruby'] = "/images_ruby/radiation" if gr[:table] == :radiation_belt
              new_path['/images_ruby'] = "/images_ruby/gu1_bo1" if gr[:table] == :gu1 || gr[:table] == :bo1
              new_path['/images_ruby'] = "/images_ruby/test" if gr[:path].index('test')
              new_path['/images_ruby'] = "/images_ruby/event" if gr[:path].index('event')
              FileUtils.mv gr[:path], new_path
              $log_img.info "#{gr[:path]} - moved!" if $log
            rescue Errno::EACCES => ex
              $log_img.error [$0, ex.class, ex.message].join(" | ")
              $log_img.error ex.backtrace.join("\n" + ' ' * 15)
            end
          end
          #puts "#{gr[:path]} - #{Time.now - t}"
        end
      }
    end
    ths.each { |aThread|  aThread.join }
  end

  def add graph
    path = "../temp/"
    gra = graph.dup
    gra.each do |k, v|
      next unless v
      if v.class == Array
        v.each {|cc| path += "#{cc}-"} unless k == :type
      else
        path += "#{v}-" unless k == :type
      end
    end
    path[-1] = '.png'
    gra[:path] = path
    @graphs << gra
  end
end

gogo = eval(ARGV[1])
tables = []
#(tables << 'test') if gogo.index('se_measurements_desp')
gogo.each {|k| tables << k}

tables.each do |table|
  tij = $db[table.to_sym].select(:date).order(Sequel.desc(:date)).limit(1).first
  tij = tij[:date] if tij
  $log_img.info "#{table} last date -> #{tij}" if $log
end

lamp = Genie.new
[2, 30].each do |days|
  tables.each do |table|
    graph = {}
    graph[:table] = table.to_sym
    case
      when table == 'gu1' && days == 30
        graph[:type] = 'hist'
        graph[:days] = days
        [:coeffs_4_5, :coeffs_5_6, :coeffs_6_7].each do |coef|
          graph[:key] = coef
          lamp.add graph
        end
      when table == 'bo1' && days == 30
        graph[:type] = 'hist'
        graph[:days] = days
        [:coeffs_4_5, :coeffs_5_6, :coeffs_6_7].each do |coef|
          graph[:key] = coef
          lamp.add graph
        end
      when table == 'earth_usgs'
        graph[:type] = 'impulse_triple'
        graph[:key] = :magnitude
        graph[:days] = days
        lamp.add graph
      when table == 'earth_kam'
        graph[:type] = 'impulse_up_down'
        graph[:key] = :magnitude
        graph[:days] = days
        lamp.add graph
      when table == 'geomagn_ap'
        graph[:type] = 'line_dm'
        ['middle_latitude', 'high_latitude', 'estimated'].each do |key|
          graph[:key] = key.to_sym
          graph[:days] = days
          lamp.add graph
        end
      when table == 'hemispheric_power_polar'
        graph[:type] = 'line_hms'
        graph[:key] = :power
        ['south!1', 'south!0'].each do |kv_select|
          graph[:kv_select] = kv_select
          graph[:days] = days
          lamp.add graph
        end
      when table == 'radiation_belt'
        graph[:type] = 'line_radiation'
        ['total_belt_index', 'inner_belt_index', 'outer_belt_index'].each do |key|
          graph[:key] = key.to_sym
          ['M02', 'N15', 'N16', 'N18', 'N19'].each do |src|
            graph[:days] = days
            (0..21).each do |sensor|
              graph[:kv_select] = ["source!#{src}", "sensor!#{sensor}"]
              lamp.add graph
            end
          end
        end
      when table == 'sunspot'
        graph[:type] = :line_dm
        ['radio_flux', 'sunspot_number'].each do |key|
          graph[:key] = key.to_sym
          graph[:days] = days
          lamp.add graph
        end
      when table.index('se_measurements_')
        graph[:type] = :line_hms_large
        max_ch = $db[:channels_name].where(:code => table).count * 2
        (0...max_ch).each do |nnn|
          graph[:key] = "v#{nnn}".to_sym
          graph[:days] = days
          lamp.add graph
        end
        #se_measurements with event
        # if days == 2
          # graph[:type] = :line_hms_large_event
          # (0...max_ch).each do |nnn|
            # graph[:key] = "v#{nnn}".to_sym
            # graph[:days] = 33
            # lamp.add graph
          # end
        # end
      when table.index('test')
        graph[:table] = 'se_measurements_desp'.to_sym
        graph[:type] = :line_hms_large_average
        max_ch = $db[:channels_name].where(:code => graph[:table].to_s).count * 2
        (0...max_ch).each do |nnn|
          graph[:key] = "v#{nnn}".to_sym
          graph[:days] = days
          lamp.add graph
        end
    end
  end
end

t1 = Time.now
lamp.plot
$log_img.info "Time to generate images: #{Time.now - t1}"