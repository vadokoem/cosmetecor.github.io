require 'sequel'
require 'gnuplot'
require 'logging'
require 'fileutils'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db', :max_connections => 4)

Sequel.default_timezone = :utc

LINES_SIZE_WIDTH = 1600
LINES_SIZE_HEIGHT = 1200

LINES_SIZE_WIDTH_DPI300 = 1300
LINES_SIZE_HEIGHT_DPI300 = 975

BAR_SIZE_WIDTH = 1536
BAR_SIZE_HEIGHT = 384
DOT_SIZE_WIDTH = 1536
DOT_SIZE_HEIGHT = 384

TH_SIZE_WIDTH = 640
TH_SIZE_HEIGHT = 128

MY_LIMIT = 512000


module Gnuplot
  class Plot
    def cheat(quo)
      QUOTED.replace quo
    end
  end
end

class Plotter

  def gen_image_line_hms_large loc
    ###########
    # start_time = Time.now
    ###########
    moon_e = d_left = d_right = db = image = sun_e = count = orb_e = nil; mm = {};
    eq_e = nil;
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:id, loc[:key])
      else
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      #p d_left, d_right
      d_left = Time.parse(ARGV[2])
      d_right = Time.parse(ARGV[3])
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      mm[:min] = db.min(loc[:key].to_sym)
      mm[:max] = db.max(loc[:key].to_sym)
      sun_e = $db[:sun_events].where{(date >= d_left) & (date < d_right)}.all
      moon_e = $db[:moon_events].where{(date >= d_left) & (date < d_right)}.all
      orb_e = $db[:orobiton_events].where{(date_event >= d_left) & (date_event < d_right)}.all
      if ARGV.index("eq")
        eq_e = $db[:earth_usgs].where{(date >= d_left) & (date < d_right)}.where("magnitude #{ARGV[6]}").where("magnitude #{ARGV[7]}").all
      else
        eq_e = $db[:earth_usgs].where{(date >= d_left) & (date < d_right)}.where('magnitude >= 7').all
      end
    end
    srand(Time.now.to_f + rand(10 ** 10))
    random = rand(10 ** 10)
    random_time = Time.now.to_i
    FileUtils.mkdir_p("/srv/ruby-www/temp/mysql", :mode => 777)
    FileUtils.chown 'mysql', 'mysql', "/srv/ruby-www/temp/mysql"
    file_csv = "/srv/ruby-www/temp/mysql/gnuplot_#{random_time}_#{random}.csv"
    db_to_file = db.sql + " INTO OUTFILE '#{file_csv}' FIELDS TERMINATED BY '\\t' ENCLOSED BY '' LINES TERMINATED BY '\\n'"
    db_to_file.sub!("`date`", "date_format(date, '%Y.%m.%dT%H:%i:%S' )")
    #p db_to_file
    #----------------------
    # db_time1 = Time.now
    #----------------------
    $db.fetch(db_to_file).all
    tries = 0
    while !File.exist? file_csv
      tries += 1
      sleep 5 if tries < 120
      break if tries >= 120
    end
    #----------------------
    # db_time2 = Time.now
    #----------------------
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    freq = ((mm[:max]-mm[:min]) / 5).to_i
    freq = 1 if freq <= 0
    nnn = loc[:key].to_s.tr('^0-9', '').to_i
    retr = $db[:channels_name].where(:code => "#{loc[:table]}")
    title = retr.where(:channel_num => nnn + 1).first
    titan = title[:channel_name_eng].gsub('~','=') unless title.nil?
    title = retr.where(:channel_num => (nnn + 1) - retr.count).first if title.nil?
    titan = title[:channel_name_eng] if titan.nil?
    loc[:path] = "../test/#{titan}-#{loc[:days]}.png" if loc[:days].to_s != "XX" && loc[:days].to_i < 40
    loc[:days] = d_right.to_date - d_left.to_date if loc[:days].to_s == "XX"
    cafka = titan.index('~')
    titan.gsub!('~','-')
    titan += " | #{d_left.strftime("%Y.%m.%d")} - #{d_right.strftime("%Y.%m.%d")}"
    moon_type = {:'Full Moon' => ["[0:360]", "[0:0]"],
                 :'First Quarter' => ["[270:90]", "[90:270]"],
                 :'New Moon' => ["[0:0]", "[0:360]"],
                 :'Last Quarter' => ["[90:270]", "[270:90]"]}
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.cheat ["output", "clabel", "cblabel", "zlabel" ]
        plot.terminal "png enhanced nocrop transparent font \"arial,20\" fontscale 1.0 size #{LINES_SIZE_WIDTH_DPI300}, #{LINES_SIZE_HEIGHT_DPI300}"
        plot.output loc[:path]
        #plot.label '1 \'mV\' at graph -0.005, graph 1.01 font \"arialbd,12\" center'
        plot.style 'rectangle fillstyle noborder'
        plot.rmargin '5'
        plot.tmargin '3'
        plot.lmargin '9'
        plot.border 'lw 2'
        #plot.label '2 \'Date\' at graph 0.5, graph 0.01 font \"arialbd,12\" center'
        plot.key 'left top'
        plot.timefmt '"%Y.%m.%dT%H:%M:%S"'
        plot.xdata 'time'
        #plot.xrange "['#{arr_x[0]}':'#{arr_x[-1]}']"
        plot.ytics "autofreq #{freq}"
        plot.tics 'scale 2'
        plot.format 'x "%Y.%m.%d"'
        plot.autoscale 'xfix'
        plot.key 'off'
        #plot.ylabel ''
        #plot.unset 'box'
        cafka = cafka.nil? ? 'direct EMF, [mV]' : 'alternative EMF, [mV]'
        plot.ylabel "\"#{cafka}\" font \"arialbd,22\""
        if loc[:days] <= 3
          plot.format 'x "%H:%M:%S"'
          plot.label "287 '#{d_left.strftime("%Y.%m.%d %H:%M:%S")}' at '#{d_left}', graph -0.1 center"
          plot.label "288 '#{d_right.strftime("%Y.%m.%d %H:%M:%S")}' at '#{d_right}', graph -0.1 center"
          plot.bmargin '5'
		      plot.xtics "#{ARGV[4]}" if ARGV[4]
          plot.mxtics '4'
        else
          plot.format 'x "%Y.%m.%d"'
        end
        if loc[:days] >= 15
          plot.xtics "#{3600 * 24 * 7}"# * loc[:days]
          plot.mxtics '7'
        elsif loc[:days] >= 35
          plot.xtics "#{3600 * 24 * 10}"# * loc[:days]
          plot.mxtics '10'
        end
        # plot.format 'x "%m.%d"'
        plot.grid 'xtics ytics lw 1 linecolor rgb \'black\''
        brezent = 3
        # sun_e.each do |sun|
          # x = sun[:date].strftime("%Y.%m.%d.%H:%M:%S")
          # #plot.arrow "from \"#{x}\",graph 0.95 to \"#{x}\",graph 1.0 nohead"
          # plot.label "#{brezent} '#{sun[:type]}' at '#{x}', graph 1.0525 font \"arialbd,22\" center"
          # brezent += 1
        # end
        if ARGV.index("eq")
          eq_e.each do |eq|
            x = eq[:date].strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 1.0 to \"#{x}\",graph 0.5 lw 3 linecolor rgb 'black'"
            plot.label "#{brezent} 'M#{eq[:magnitude]}' at '#{x}', graph 1.0525 font \"arialbd,22\" center"
            brezent += 1
          end
        end
        plot.data << Gnuplot::DataSet.new( '"' + file_csv + '"') do |ds|
          ds.with = "lines"
          ds.linewidth = 2
          ds.linecolor = "rgb 'black'"
          ds.using = '1:2'
        end
        plot.cheat [ "title", "output", "xlabel", "x2label", "ylabel", "y2label", "clabel", "cblabel", "zlabel" ]
      end
      $stderr.reopen $std if $silence_gnuplot
    end
    FileUtils.rm file_csv
    ###########
    # end_time = Time.now
    # File.open("/srv/ftp/upload/tttime.txt", "w") do |f|
      # f.write("#{start_time}\n")
      # f.write("#{end_time}\n")
      # f.write("#{end_time-start_time}\n")
      # f.write("---------------\n")
      # f.write("#{db_time1}\n")
      # f.write("#{db_time2}\n")
      # f.write("#{db_time2-db_time1}\n")
    # end
    ###########
  end

  def gen_image_line_radiation loc
    image = nil; count = nil; db = nil; mm = {}; sensor = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select][0].split('!')
        sensor = loc[:kv_select][1].split('!')[1].to_i
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        # d = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        # d = (d[:date] - loc[:days]*3600*24).to_date + 1
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      db = db.where(:sensor => sensor) if sensor
      loc[:days] = d_right.to_date - d_left.to_date
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      mm[:min] = db.min(loc[:key])
      mm[:max] = db.max(loc[:key])
      db = db.all
    end
    arr_x = []
    arr_y = []
    db.each do |line|
      next if line[loc[:key]] == -1
      arr_x << line[:date].strftime("%Y/%m/%d")#h
      arr_y << line[loc[:key]]
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    name = $db[:radiation_sensors].where(:id => sensor + 1).first[:name]
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH / 2}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.title  "#{name}"
        plot.ylabel "Belt Index"
        plot.xlabel "Date"
        plot.timefmt '"%Y/%m/%d"'
        plot.xdata 'time'
        plot.rmargin '5'
        #plot.ytics "autofreq #{freq}"
        plot.format 'x "%Y/%m/%d"'
        plot.tics 'scale 2'
        plot.grid 'xtics ytics'
        plot.autoscale 'xfix'
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "lines"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_hist loc
    d_left = d_right = image = sun_e = orb_e = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        #d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        #d_left = (d_right[:date].to_date - loc[:days]).to_date + 1
        #d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        #d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        #d_left = (d_right[:date].to_date - loc[:days]).to_date + 1
        #d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      loc[:days] = d_right.to_date - d_left.to_date
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      max = db.max(loc[:key])
      db = db.all
      orb_e = $db[:orobiton_events].where{(date_event >= d_left) & (date_event <= d_right)}.all
      sun_e = $db[:sun_events].where{(date >= d_left) & (date <= d_right)}.all
    end
    arr_x = []
    arr_y = []
    db.each do |line|
      arr_x << line[:date].strftime("%Y.%m.%d")
      arr_y << line[loc[:key]]
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    t_name = loc[:key].to_s.tr("^0-9", '')
    t_name = "Magnitude [#{t_name[0]}, #{t_name[1]})"
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{BAR_SIZE_WIDTH}, #{BAR_SIZE_HEIGHT}"
        plot.output loc[:path]
        #plot.rmargin '5'
        plot.tmargin '5'
        #plot.lmargin '6'
        #plot.yrange "[#{-(max + 1).to_i}:#{(max + 1).to_i}]"
        plot.label "1 '#{t_name}' at graph 0.5, graph 1.25"
        plot.ylabel "#{loc[:table]}"
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d"'
        plot.xdata 'time'
        #if loc[:days] > 7
          plot.format 'x "%Y.%m.%d"'
          #plot.xtics "#{3600 * 48}"# * loc[:days]
        #else
          #plot.format 'x "%m.%d"'
          #plot.xtics "14400"
        #end
        brezent = 3
        sun_e.each do |sun|
          x = sun[:date].strftime("%Y.%m.%d")
          plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1.0 nohead"
          plot.label "#{brezent} '#{sun[:type]}' at '#{x}', graph 1.175 center"
          brezent += 1
        end
        unless orb_e == []
          orb_e.each do |orb|
            x = orb[:date_event]
            x = x.strftime("%Y.%m.%d")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.label "#{brezent} '#{orb[:type]}' at '#{x}', graph 1.10 center"
            brezent += 1
          end
        end
        #plot.ytics "autofreq 1"
        plot.grid 'xtics ytics'
        #plot.xrange "['#{d_left.strftime("%Y.%m.%d")}':'#{d_right.strftime("%Y.%m.%d.%H:%M:%S")}']"
        plot.tics 'scale 2'
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "boxes"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_impulse loc
    loc[:mg] = [[4, 5], [5, 6], [6, 7], [7, 8], [6, 11], [7, 11], [8, 11]]
    d_left = d_right = image = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      loc[:days] = d_right.to_date - d_left.to_date
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      max = db.max(loc[:key])
    end
    arr_x = []
    arr_y = []
    mgn = ARGV[4].split("<").map{|a| a.gsub(",", ".").to_f}
    db.where{(magnitude >= mgn[0]) &
             (magnitude < mgn[1])}.all.each do |line|
      arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
      arr_y << line[loc[:key]]
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{BAR_SIZE_WIDTH}, #{BAR_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.yrange "[0:#{(max + 1).to_i}]"
        plot.title  "#{loc[:key]}"
        plot.ylabel "#{mgn[0]} <= M < #{mgn[1]}"
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.format 'x "%Y.%m.%d"'
        plot.ytics "autofreq 1"
        plot.grid 'xtics ytics'
        plot.xrange "['#{d_left.strftime("%Y.%m.%d.%H:%M:%S")}':'#{d_right.strftime("%Y.%m.%d.%H:%M:%S")}']"
        plot.tics 'scale 2'
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "impulses"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_impulse_up_down loc
    loc[:mg] = [[4, 5], [5, 6], [6, 7], [7, 8], [6, 11], [7, 11], [8, 11]]
    d_left = d_right = image = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        db = $db[loc[:table]].select(:date, :depth, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      loc[:days] = d_right.to_date - d_left.to_date
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      max = db.max(loc[:key])
      #db = db.all
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    arr_x = []
    arr_y = []
    mgn = ARGV[4].split("<").map{|a| a.gsub(",", ".").to_f}
    if ARGV[5] == "true"
      db.where{(magnitude >= mgn[0]) &
               (magnitude < mgn[1])}.all.each do |line|
        arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
        arr_y << (line[:depth] < 100 ? line[loc[:key]] : -line[loc[:key]])
      end
    else
      db.where{magnitude >= 4}.all.each do |line|
        arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
        arr_y << (line[:depth] < 100 ? line[loc[:key]] : -line[loc[:key]])
      end
    end
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{BAR_SIZE_WIDTH}, #{BAR_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.yrange "[#{-(max + 1).to_i}:#{(max + 1).to_i}]"
        plot.bmargin '4'
        plot.title  "Kamchatka earthquakes"
        if ARGV[5] == "true"
          plot.ylabel "#{mgn[0]} <= M < #{mgn[1]}"
        else
          plot.ylabel "M >= 4"
        end
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.format 'x "%Y.%m.%d"'
        plot.ytics "autofreq 1"
        plot.grid 'xtics ytics'
        plot.xrange "['#{d_left.strftime("%Y.%m.%d.%H:%M:%S")}':'#{d_right.strftime("%Y.%m.%d.%H:%M:%S")}']"
        plot.tics 'scale 2'
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "impulses"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_impulse_triple loc
    d_left = d_right = image = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        db = $db[loc[:table]].select(:date, :depth, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      loc[:days] = d_right.to_date - d_left.to_date
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      max = db.max(loc[:key])
      #db = db.all
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    arr_x_1 = []
    arr_y_1 = []
    db.where{magnitude < 5}.all.each do |line|
      arr_x_1 << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
      arr_y_1 << (line[:depth] < 300 ? line[loc[:key]] : -line[loc[:key]])
    end
    arr_x_2 = []
    arr_y_2 = []
    db.where{(magnitude < 6) & (magnitude >= 5)}.all.each do |line|
      arr_x_2 << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
      arr_y_2 << (line[:depth] < 300 ? line[loc[:key]] : -line[loc[:key]])
    end
    arr_x_3 = []
    arr_y_3 = []
    db.where('magnitude >= 6').all.each do |line|
      arr_x_3 << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
      arr_y_3 << (line[:depth] < 300 ? line[loc[:key]] : -line[loc[:key]])
    end
    #p arr_x_3, arr_x_2, arr_x_1
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.tmargin '1.5'
        plot.bmargin '0'
        plot.lmargin '5'
        plot.rmargin '5'
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{BAR_SIZE_WIDTH}, #{BAR_SIZE_HEIGHT * 3}"
        plot.output loc[:path]
        plot.label '2 \'Date\' at graph 1.007, graph 0.01'
        plot.multiplot "layout 4,1 title 'Earth USGS'"
        plot.label '1 \'M >= 4\' at graph -0.005, graph 1.05'
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.yrange "[-5:5]"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.xrange "['#{d_left.strftime("%Y.%m.%d.%H:%M:%S")}':'#{d_right.strftime("%Y.%m.%d.%H:%M:%S")}']"
        plot.size '1,0.15'
        plot.origin '0,0.8375'
        plot.ytics "autofreq 2"
        plot.format 'x ""'
        plot.grid 'xtics ytics'
        plot.tics 'scale 2'
        plot.data << Gnuplot::DataSet.new( [arr_x_1, arr_y_1] ) do |ds|
          ds.with = "impulses"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      Gnuplot::Plot.new( gp ) do |plot|
        plot.nothing
        plot.label '1 \'M >= 5\' at graph -0.005, graph 1.05'
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.yrange "[-6:6]"
        plot.xrange "['#{d_left.strftime("%Y.%m.%d.%H:%M:%S")}':'#{d_right.strftime("%Y.%m.%d.%H:%M:%S")}']"
        plot.size '1,0.3'
        plot.origin '0,0.5375'
        plot.ytics "autofreq 1"
        plot.format 'x ""'
        plot.tics 'scale 2'
        plot.grid 'xtics ytics'
        plot.data << Gnuplot::DataSet.new( [arr_x_2, arr_y_2] ) do |ds|
          ds.with = "impulses"
          ds.linewidth = 2
          ds.notitle
          ds.using = '1:2'
        end
      end
      magn = (max + 1).to_i > 7 ? (max + 1).to_i : 7
      Gnuplot::Plot.new( gp ) do |plot|
        plot.nothing
        plot.label '1 \'M >= 6\' at graph -0.005, graph 1.05'
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.ytics "autofreq 1"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.yrange "[#{-magn}:#{magn}]"
        plot.xrange "['#{d_left.strftime("%Y.%m.%d.%H:%M:%S")}':'#{d_right.strftime("%Y.%m.%d.%H:%M:%S")}']"
        plot.size '1,0.475'
        plot.origin '0,0.05'
        plot.tics 'scale 2'
        # if loc[:days] > 7
          plot.format 'x "%Y.%m.%d"'
          # plot.xtics "#{3600 * 48}"# * loc[:days]
        # else
          # plot.format 'x "%m.%d %H:%M"'
          # plot.xtics "14400"
        # end
        plot.grid 'xtics ytics'
        # if arr_x_3.size == 0
          # arr_x_3 << arr_x[0]
          # arr_y_3 << 6.5
        # end
        plot.data << Gnuplot::DataSet.new( [arr_x_3, arr_y_3] ) do |ds|
          ds.with = "impulses"
          ds.linewidth = 3
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_line_hms loc
    image = nil; count = nil; db = nil; mm = {}; d = nil;
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      mm[:min] = db.min(loc[:key])
      mm[:max] = db.max(loc[:key])
      db = db.all
    end
    arr_x = []
    arr_y = []
    db.each do |line|
      arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
      arr_y << line[loc[:key]]
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    freq = ((mm[:max]-mm[:min]) / 5).to_i
    freq = 1 if freq <= 0
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.title  "#{loc[:key]}"
        plot.ylabel "GigaWatts"
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.ytics "autofreq #{freq}"
        plot.tics 'scale 2'
        #if loc[:days] > 7
          plot.format 'x "%Y.%m.%d"'
          # plot.xtics "#{3600 * 48}"# * loc[:days]
        # else
          # plot.format 'x "%m.%d %H:%M"'
          # plot.xtics "14400"
        # end
        plot.grid 'xtics ytics'
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "lines"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_line_dm loc
    image = nil; count = nil; db = nil; mm = {}
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      d_left = Date.parse(ARGV[2])
      d_right = Date.parse(ARGV[3])
      loc[:days] = d_right.to_date - d_left.to_date
      db = db.order(:date).where{(date >= d_left) & (date < d_right)}
      count = db.count
      mm[:min] = db.min(loc[:key])
      mm[:max] = db.max(loc[:key])
    end
    arr_x = []
    arr_y = []
    db.each do |line|
      arr_x << line[:date].strftime("%Y.%m.%d")
      arr_y << line[loc[:key]]
    end
    if $silence_gnuplot
      $std = $stderr.dup
      if RUBY_PLATFORM.downcase.index("x86_64-linux")
        $stderr.reopen '/dev/null'
      else
        $stderr.reopen 'NUL'
      end
      $stderr.sync = true
    end
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.title  "#{loc[:key]}"
        plot.ylabel "Number"
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d"'
        plot.xdata 'time'
        #plot.xtics "#{3600 * 24}"
        #plot.ytics "autofreq 1"
        plot.format 'x "%Y.%m.%d"'
        plot.grid 'xtics ytics'
        plot.tics 'scale 2'
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "lines"
          ds.linewidth = 1
          ds.notitle
          ds.using = '1:2'
        end
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

end

gr = eval(ARGV[0])

p ARGV

$silence_gnuplot = nil
#$silence_gnuplot = true unless ARGV.index '-log'
$logger = Logging.logger['gnuplot']
$logger.add_appenders(
  Logging.appenders.rolling_file('../log/gnuplot.log', :age => 'daily', :keep => 3)
)
$logger.level = :info

if $db.table_exists? gr[:table]
  begin
    pl = Plotter.new
    method = pl.method("gen_image_#{gr[:type]}".to_sym)
    method.call(gr)
  rescue Exception => ex
    $logger.error [$0, ex.class, ex.message].join(" | ")
    $logger.error ex.backtrace.join("\n" + ' ' * 17)
  end
end