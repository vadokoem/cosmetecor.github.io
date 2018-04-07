require 'sequel'
require 'logging'
require 'fileutils'
require 'dropbox'

Dir.chdir '/srv/ruby-www/content' if $0.index('/')

$log = '-log'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db', :max_connections => 4)

if $log
  $log_img = Logging.logger['image']
  $log_img.add_appenders(
    Logging.appenders.rolling_file('images.log')
  )
  $log_img.level = :info
end

Sequel.default_timezone = :utc

class Genie
  def initialize
    @graphs = []
    th_num = 4
    @th_arr = []
    (0...th_num).each {|i| @th_arr[i] = []}
  end

  def plot
    date_now = Time.now
    cook = 0
    th_num = 4
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
            gr[:path] = "../test/#{titan}-#{gr[:days]}.png"
          end
          #p "ruby gnuplot_desp.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}'"
          if gr[:type] == :line_hms_large
            #system("echo \"gnuplot_desp_new2017.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[5]}' '#{ARGV[6]}'\" > 1.log")
            if ARGV[6].index("eq")
              system("ruby gnuplot_desp_new2017.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[5]}' '#{ARGV[6]}' '#{ARGV[7]}' '#{ARGV[8]}'")
            else
              system("ruby gnuplot_desp_new2017.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[5]}' '#{ARGV[6]}'")
            end
          elsif gr[:type] == :google_maps
            p "zzzzzzzzzzz"
            #p "ruby gnuplot_desp.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[4]}' '#{ARGV[5]}'"
            wget = 'https://maps.googleapis.com/maps/api/staticmap?center=0,0&zoom=1&size=640x600&scale=2&markers=icon:http://cosmetecor.org/dot16.png%7CLAT,LNG&key=AIzaSyC8D0kvn3wadBOgdRvii28EPXf8-yM7-ZQ&language=en'
            getto = wget.sub('LAT', gr[:latitude].to_s).sub('LNG', gr[:longitude].to_s)
            gr[:path] = "../test/#{gr[:date].strftime("%Y-%m-%d_%H-%M-%S")}-Mg_#{gr[:magnitude]}.png"
            system("wget '#{getto}' -O #{gr[:path]}")
          elsif gr[:table] == :earth_usgs
            #p "ruby gnuplot_desp.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[4]}' '#{ARGV[5]}'"
            system("ruby gnuplot_desp.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[4]}' '#{ARGV[5]}'")
          else
            #p "ruby gnuplot_desp.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[4]}'"
            system("ruby gnuplot_desp.rb '#{gr}' #{$log} '#{ARGV[2]}' '#{ARGV[3]}' '#{ARGV[4]}'")
          end
          $log_img.info "#{gr[:path]} - generate!" if $log
          gr[:path] = "../test/test-#{titan}-#{gr[:days]}.png" if gr[:type] == :line_hms_large_average
          tries = 0
          big_problem = nil
          while !File.exists? gr[:path]
            tries += 1
            sleep 0.1 if tries < 50
            ($log_img.error "#{gr[:path]} - dead generate!"; big_problem = true; break) if tries >= 50
          end
          if big_problem.nil?
            begin
              client = Dropbox::Client.new("MUvd7gv_XoAAAAAAAAAAKzIPVjDCl0wkuqo9V1sZLmlTvs56mqumyChr_EmpDzed")

              file = open(gr[:path])
              #File.open("/srv/ftp/upload/111.txt", "a") {|f| f.write(gr[:path] + "\n")}              
              
              new_path = gr[:path].dup
              dropbox_path = gr[:path].dup
              ppp = "/srv/ftp/test/#{date_now.strftime("%Y.%m.%d")}"
              if gr[:table] == :gu1 || gr[:table] == :bo1
                ppp['/test/'] = "/test/gu1_bo1/"
                dropbox_path['../test'] = "/gu1_bo1/#{date_now.strftime("%Y.%m.%d")}/#{date_now.strftime("%H-%M-%S")}"
                response = client.upload(dropbox_path, File.open(file, 'r', &:read))
              elsif gr[:type] == :google_maps
                ppp['/test/'] = "/test/#{gr[:type]}/"
                dropbox_path['../test'] = "/#{gr[:type]}/#{date_now.strftime("%Y.%m.%d")}/#{date_now.strftime("%H-%M-%S")}"
                response = client.upload(dropbox_path, File.open(file, 'r', &:read))
              else
                ppp['/test/'] = "/test/#{gr[:table]}/"
                dropbox_path['../test'] = "/#{gr[:table]}/#{date_now.strftime("%Y.%m.%d")}/#{date_now.strftime("%H-%M-%S")}"
                response = client.upload(dropbox_path, File.open(file, 'r', &:read))
              end
              FileUtils.mkdir_p(ppp) unless Dir.exists?(ppp)
              ppp += "/#{date_now.strftime("%H.%M.%S")}"
              FileUtils.mkdir(ppp) unless Dir.exists?(ppp)
              new_path[0..6] = ppp
              #p [gr[:path], new_path]
              FileUtils.cp gr[:path], "/srv/ruby-www/web/public/usgs/usgs.png" if gr[:table] == :earth_usgs && gr[:type] != "google_maps"
              FileUtils.mv gr[:path], new_path
              #p "#{gr[:path]} - moved!"
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
    path = "../test/"
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
    gra[:type] = gra[:type].to_sym
    @graphs << gra
  end
end

gogo = eval(ARGV[1])
tables = []
gogo.each {|k| tables << (k == "gu1" ||
                          k == "bo1" ||
                          k == "earth_usgs" ||
                          k == "earth_kam" ||
                          k == "geomagn_ap"||
                          k == "radiation_belt"||
                          k == "sunspot" ||
                          k == "earthquakes" ||
                          k == "hemispheric_power_polar" ? k : "se_measurements_#{k}")}

lamp = Genie.new
['XX'].each do |days|
  tables.each do |table|
    graph = {}
    graph[:table] = table.to_sym
    case
      when table == 'earthquakes'
        $log_img.info "#{ARGV}"
        graph[:table] = "earth_usgs".to_sym
        graph[:type] = 'google_maps'.to_sym
        mg = eval(ARGV[4])
        eq = $db[graph[:table]].select(:date, :magnitude, :latitude, :longitude).where('magnitude >= ?', mg[0]).
              where('magnitude < ?', mg[1]).where('date >= ?', ARGV[2]).where('date < ?', ARGV[3]).all
        eq.each do |e|
          graph[:date] = e[:date]
          graph[:magnitude] = e[:magnitude]
          graph[:latitude] = e[:latitude]
          graph[:longitude] = e[:longitude]
          lamp.add graph
        end
      when table == 'gu1'
        graph[:type] = 'hist'
        graph[:days] = days
        [:coeffs_4_5, :coeffs_5_6, :coeffs_6_7].each do |coef|
          graph[:key] = coef
          lamp.add graph
        end
      when table == 'bo1'
        graph[:type] = 'hist'
        graph[:days] = days
        [:coeffs_4_5, :coeffs_5_6, :coeffs_6_7].each do |coef|
          graph[:key] = coef
          lamp.add graph
        end
      when table == 'earth_usgs'
        if ARGV[5] == "true"
          graph[:type] = 'impulse_up_down'
        else
          graph[:type] = 'impulse'
        end
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
          ['M02', 'N15', 'N16', 'N18', 'N19'].each_with_index do |src, ik|
            next unless ARGV[4].to_i == ik
            graph[:days] = days
            (0..21).each do |sensor|
              graph[:kv_select] = ["source!#{src}", "sensor!#{sensor}"]
              lamp.add graph
            end
          end
        end
      when table == 'sunspot'
        graph[:type] = 'line_dm'
        ['radio_flux', 'sunspot_number'].each do |key|
          graph[:key] = key.to_sym
          graph[:days] = days
          lamp.add graph
        end
      when table.index('se_measurements_')
        graph[:type] = :line_hms_large
        nc = $db[:channels_name].where(:code => table).count
        max_ch = nc * 2
        (0...max_ch).each do |nnn|
          next unless ARGV[4] == "-1" || ARGV[4] == "#{nnn + 1}" || (ARGV[4].to_i + nc) == nnn + 1
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