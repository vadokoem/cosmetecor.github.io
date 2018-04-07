require 'sequel'
require 'gnuplot'
require 'logging'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db', :max_connections => 4)

Sequel.default_timezone = :utc

LINES_SIZE_WIDTH = 1536
LINES_SIZE_HEIGHT = 384
BAR_SIZE_WIDTH = 1536
BAR_SIZE_HEIGHT = 384
DOT_SIZE_WIDTH = 1536
DOT_SIZE_HEIGHT = 384

TH_SIZE_WIDTH = 640
TH_SIZE_HEIGHT = 128

MY_LIMIT = 512000

class Plotter

  def gen_image_line_hms_large loc
    moon_e = d_left = d_right = db = image = sun_e = count = orb_e = nil; mm = {};
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:id, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      #p d_left, d_right
      db = db.order(:date).where{date >= d_left}
      count = db.count
      mm[:min] = db.min(loc[:key])
      mm[:max] = db.max(loc[:key])
      sun_e = $db[:sun_events].where{(date >= d_left) & (date <= d_right)}.all
      moon_e = $db[:moon_events].where{(date >= d_left) & (date <= d_right)}.all
      orb_e = $db[:orobiton_events].where{(date_event >= d_left) & (date_event <= d_right)}.all
    end
    i = 0
    arr_x = []
    arr_y = []
    seek = 0
    while seek < count
      db_seek = db.limit(MY_LIMIT, seek)
      db_seek = db_seek.all
      seek += MY_LIMIT
      db_seek.each do |line|
        arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
        arr_y << line[loc[:key]]
      end
    end
    arr_x.pop
    arr_y.pop
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
    loc[:path] = "../temp/#{titan}-#{loc[:days]}.png"
    titan.gsub!('~','-')
    moon_type = {:'Full Moon' => ["[0:360]", "[0:0]"],
                 :'First Quarter' => ["[270:90]", "[90:270]"],
                 :'New Moon' => ["[0:0]", "[0:360]"],
                 :'Last Quarter' => ["[90:270]", "[270:90]"]}
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png enhanced nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.label '1 \'mV\' at graph -0.005, graph 1.1'
        plot.rmargin '5'
        plot.tmargin '4'
        plot.lmargin '6'
        plot.label '2 \'Date\' at graph 1.007, graph 0.01'
        plot.key 'left top'
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        plot.xrange "['#{arr_x[0]}':'#{arr_x[-1]}']"
        plot.ytics "autofreq #{freq}"
        plot.tics 'scale 2'
        if loc[:days] > 7
          plot.xtics "#{3600 * 48}"# * loc[:days]
          plot.format 'x "%m.%d"'
        else
          plot.xtics "14400"
          plot.format 'x "%m.%d %Hh"'
        end
        plot.grid 'xtics ytics'
        brezent = 3
        sun_e.each do |sun|
          x = sun[:date].strftime("%Y.%m.%d.%H:%M:%S")
          plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1.0 nohead"
          plot.label "#{brezent} '#{sun[:type]}' at '#{x}', graph 1.20 center"
          brezent += 1
        end
        unless moon_e == []
          moon_e.each do |moon|
            x_moon = moon[:date]# - loc[:days] * 480
            x = moon[:date]
            x = x.strftime("%Y.%m.%d.%H:%M:%S")
            x_moon = x_moon.strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.style 'fill empty'
            plot.obj "#{brezent} circle arc #{moon_type[moon[:type].to_sym][0]} fc rgb 'black' noclip"
            plot.obj "#{brezent} circle at '#{x_moon}', graph 1.06 size screen 0.007  front"
            brezent += 1
            plot.style 'fill solid 1.0 border -1'
            plot.obj "#{brezent} circle arc #{moon_type[moon[:type].to_sym][1]} fc rgb 'black' noclip"
            plot.obj "#{brezent} circle at '#{x_moon}', graph 1.06 size screen 0.007  front"
            brezent += 1
          end
        end
        unless orb_e == []
          orb_e.each do |orb|
            x = orb[:date_event]
            x = x.strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.label "#{brezent} '#{orb[:type]}' at '#{x}', graph 1.15 center"
            brezent += 1
          end
        end
        plot.data << Gnuplot::DataSet.new( [arr_x, arr_y] ) do |ds|
          ds.with = "lines"
          ds.linewidth = 1
          ds.title = titan
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
        d = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d = (d[:date] - loc[:days]*3600*24).to_date + 1
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d = (d[:date] - loc[:days]*3600*24).to_date + 1
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.order(:date).where{date >= d}
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
        if loc[:days] > 7
          plot.format 'x "%m.%d"'
          plot.xtics "#{3600 * 48}"# * loc[:days]
        else
          plot.format 'x "%m.%d %H:%M"'
          plot.xtics "14400"
        end
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

  def gen_image_line_radiation loc
    image = nil; count = nil; db = nil; mm = {}; sensor = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select][0].split('!')
        sensor = loc[:kv_select][1].split('!')[1].to_i
        d = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d = (d[:date] - loc[:days]*3600*24).to_date + 1
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d = (d[:date] - loc[:days]*3600*24).to_date + 1
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.where(:sensor => sensor) if sensor
      db = db.order(:date).where{date >= d}
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
    freq = ((mm[:max]-mm[:min]) / 5).to_i
    freq = 1 if freq <= 0
    name = $db[:radiation_sensors].where(:id => sensor + 1).first[:name]
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH / 2}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.title  "#{name}"
        plot.tmargin '5'
        plot.rmargin '5'
        plot.bmargin '5'
        plot.lmargin '5'
        plot.ylabel "Belt Index"
        plot.xlabel "Date"
        plot.timefmt '"%Y/%m/%d"'
        plot.xdata 'time'
        plot.rmargin '5'
        plot.ytics "autofreq #{freq}"
        plot.format 'x "%Y/%m/%d"'
        plot.tics 'scale 2'
        if loc[:days] > 7
          plot.xtics "#{3600 * 24 * 7}"# * loc[:days]
        else
          plot.xtics "#{3600 * 24}"
        end
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
        d = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d = d[:date] - loc[:days]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d = d[:date] - loc[:days]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.order(:date).where{date >= d}
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
        plot.xtics "#{3600 * 24}"
        #plot.ytics "autofreq 1"
        plot.format 'x "%m.%d"'
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

  def gen_image_impulse loc
    d_left = d_right = image = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.order(:date).where{date >= d_left}
      count = db.count
      max = db.max(loc[:key])
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
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{BAR_SIZE_WIDTH}, #{BAR_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.yrange "[#{-(max + 1).to_i}:#{(max + 1).to_i}]"
        plot.title  "#{loc[:key]}"
        plot.ylabel "M >= 4"
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        if loc[:days] > 7
          plot.format 'x "%m.%d"'
          plot.xtics "#{3600 * 48}"# * loc[:days]
        else
          plot.format 'x "%m.%d %H:%M"'
          plot.xtics "14400"
        end
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

  def gen_image_hist loc
    d_left = d_right = image = sun_e = orb_e = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date].to_date - loc[:days]).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date].to_date - loc[:days]).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.order(:date).where{date >= d_left}
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
        #plot.yrange "[#{-(max + 1).to_i}:#{(max + 1).to_i}]"
        plot.title  "#{t_name}"
        plot.ylabel "#{loc[:table]}"
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d"'
        plot.xdata 'time'
        if loc[:days] > 7
          plot.format 'x "%m.%d"'
          plot.xtics "#{3600 * 48}"# * loc[:days]
        else
          plot.format 'x "%m.%d"'
          plot.xtics "14400"
        end
        brezent = 3
        sun_e.each do |sun|
          x = sun[:date].strftime("%Y.%m.%d")
          plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1.0 nohead"
          plot.label "#{brezent} '#{sun[:type]}' at '#{x}', graph 1.15 center"
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

  def gen_image_impulse_up_down loc
    d_left = d_right = image = nil; count = nil; db = nil; max = nil
    $db.transaction do
      if loc[:kv_select]
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, :depth, loc[:key])
      end
      db = db.order(:date).where{date >= d_left}
      count = db.count
      max = db.max(loc[:key])
      #db = db.all
    end
    ##############
    d_right = Time.now.utc
    ##############
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
    db.where{magnitude >= 4}.all.each do |line|
      arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S")
      arr_y << (line[:depth] < 100 ? line[loc[:key]] : -line[loc[:key]])
    end
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{BAR_SIZE_WIDTH}, #{BAR_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.yrange "[#{-(max + 1).to_i}:#{(max + 1).to_i}]"
        plot.bmargin '4'
        plot.title  "Kamchatka earthquakes"
        plot.ylabel "M >= 4"
        plot.arrow '5 from graph 0,first 0 to graph 1,first 0 nohead '
        plot.xlabel "Date"
        plot.timefmt '"%Y.%m.%d.%H:%M:%S"'
        plot.xdata 'time'
        if loc[:days] > 7
          plot.format 'x "%m.%d"'
          plot.xtics "#{3600 * 48}"# * loc[:days]
        else
          plot.format 'x "%m.%d %H:%M"'
          plot.xtics "14400"
        end
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
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date + 1
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, :depth, loc[:key])
      end
      db = db.order(:date).where{date >= d_left}
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
    db.where{magnitude >= 6}.all.each do |line|
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
        if loc[:days] > 7
          plot.xtics "#{3600 * 48}"
        else
          plot.xtics "14400"
        end
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
        if loc[:days] > 7
          plot.xtics "#{3600 * 48}"# * loc[:days]
        else
          plot.xtics "14400"
        end
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
        if loc[:days] > 7
          plot.format 'x "%m.%d"'
          plot.xtics "#{3600 * 48}"# * loc[:days]
        else
          plot.format 'x "%m.%d %H:%M"'
          plot.xtics "14400"
        end
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

  def gen_image_line_hms_large_average loc
    moon_e = d_left = d_right = db = image = sun_e = count = orb_e = nil; mm = {};
    $db.transaction do
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:id, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - loc[:days]*3600*24).to_date
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.order(:date).where{date >= d_left}
      count = db.count
      mm[:min] = db.min(loc[:key])
      mm[:max] = db.max(loc[:key])
      sun_e = $db[:sun_events].where{(date >= d_left) & (date <= d_right)}.all
      moon_e = $db[:moon_events].where{(date >= d_left) & (date <= d_right)}.all
      orb_e = $db[:orobiton_events].where{(date_event >= d_left) & (date_event <= d_right)}.all
    end
    points = []
    dates = []
    seek = 0
    while seek < count
      db_seek = db.limit(MY_LIMIT, seek)
      db_seek = db_seek.all
      seek += MY_LIMIT
      db_seek.each do |line|
        points << line[loc[:key]]
        dates << line[:date].strftime("%Y.%m.%d.%H:%M:%S ")
      end
    end
    points.pop; dates.pop;

    gogo = [dates, points]

    gah, goh = average gogo[0], gogo[1], 1000
    arr_y = smooth7 goh
    arr_x = gah
    #p arr_x.size
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
    loc[:path] = "../temp/test-#{titan}-#{loc[:days]}.png"
    titan.gsub!('~','-')
    #p titan
    moon_type = {:'Full Moon' => ["[0:360]", "[0:0]"],
                 :'First Quarter' => ["[270:90]", "[90:270]"],
                 :'New Moon' => ["[0:0]", "[0:360]"],
                 :'Last Quarter' => ["[90:270]", "[270:90]"]}
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png enhanced nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.label '1 \'mV\' at graph -0.005, graph 1.1'
        plot.rmargin '5'
        plot.tmargin '2'
        plot.lmargin '6'
        plot.label '2 \'Date\' at graph 1.007, graph 0.01'
        plot.key 'left top'
        plot.timefmt '"%Y.%m.%d.%H:%M:%S "'
        plot.xdata 'time'
        plot.xrange "['#{arr_x[0]}':'#{arr_x[-1]}']"
        plot.ytics "autofreq #{freq}"
        plot.tics 'scale 2'
        if loc[:days] > 7
          plot.xtics "#{3600 * 48}"# * loc[:days]
          plot.format 'x "%m.%d"'
        else
          plot.xtics "14400"
          plot.format 'x "%m.%d %Hh"'
        end
        plot.grid 'xtics ytics'
        brezent = 3
        sun_e.each do |sun|
          x = sun[:date].strftime("%Y.%m.%d.%H:%M:%S")
          plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
          plot.label "#{brezent} '#{sun[:type]}' at '#{x}', graph 1.05"
          brezent += 1
        end
        unless moon_e == []
          moon_e.each do |moon|
            x_moon = moon[:date]# - loc[:days] * 480
            x = moon[:date]
            x = x.strftime("%Y.%m.%d.%H:%M:%S")
            x_moon = x_moon.strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.style 'fill empty'
            plot.obj "#{brezent} circle arc #{moon_type[moon[:type].to_sym][0]} fc rgb 'black' noclip"
            plot.obj "#{brezent} circle at '#{x_moon}', graph 1.06 size screen 0.007  front"
            brezent += 1
            plot.style 'fill solid 1.0 border -1'
            plot.obj "#{brezent} circle arc #{moon_type[moon[:type].to_sym][1]} fc rgb 'black' noclip"
            plot.obj "#{brezent} circle at '#{x_moon}', graph 1.06 size screen 0.007  front"
            brezent += 1
          end
        end
        unless orb_e == []
          orb_e.each do |orb|
            x = orb[:date_event]
            x = x.strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.label "#{brezent} '#{orb[:type]}' at '#{x}', graph 1.05"
            brezent += 1
          end
        end
        plot.data = [Gnuplot::DataSet.new( [gogo[0], gogo[1]] ) {|ds|
                     ds.with = "lines"
                     ds.linewidth = 1
                     ds.title = 'no-smooth'
                     ds.using = '1:2'},
                     Gnuplot::DataSet.new( [arr_x, arr_y] ) {|ds|
                     ds.with = "lines"
                     ds.linewidth = 1
                     ds.title = 'smooth ' + titan
                     ds.using = '1:2'}]
      end
      $stderr.reopen $std if $silence_gnuplot
    end
  end

  def gen_image_line_hms_large_event loc
    moon_e = d_left = d_right = db = image = sun_e = count = orb_e = nil; mm = {};
    event_time = event = nil
    $db.transaction do
      event_time = Time.parse('2014-10-09 02:14:32 UTC')
      event = $db[:earth_usgs].where(:date => event_time).first
      if loc[:kv_select]
        a = loc[:kv_select].split('!')
        d_right = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date).
                  where{date <= event_time + 3*24*3600}.order(Sequel.desc(:date)).limit(1).first
        d_left = (d_right[:date] - 33*3600*24).to_date
        d_right = d_right[:date]
        db = $db[loc[:table]].filter(a[0].to_sym => a[1]).select(:date, loc[:key])
      else
        d_right = $db[loc[:table]].select(:date).where{date <= event_time + 3*24*3600}.order(Sequel.desc(:date)).limit(1).first
        d_right = event_time + 3*24*3600 unless d_right
        d_left = (d_right[:date] - 33*3600*24).to_date
        d_right = d_right[:date]
        db = $db[loc[:table]].select(:date, loc[:key])
      end
      db = db.order(:date).where("date >= ?", d_left).where{date <= d_right}
      count = db.count
      mm[:min] = db.min(loc[:key])
      mm[:max] = db.max(loc[:key])
      sun_e = $db[:sun_events].where{(date >= d_left) & (date <= d_right)}.all
      moon_e = $db[:moon_events].where{(date >= d_left) & (date <= d_right)}.all
      orb_e = $db[:orobiton_events].where{(date_event >= d_left) & (date_event <= d_right)}.all
    end
    seek = 0
    arr_x = []; arr_y = []
    while seek < count
      db_seek = db.limit(MY_LIMIT, seek)
      db_seek = db_seek.all
      seek += MY_LIMIT
      db_seek.each do |line|
        arr_y << line[loc[:key]]
        arr_x << line[:date].strftime("%Y.%m.%d.%H:%M:%S ")
      end
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
    nnn = loc[:key].to_s.tr('^0-9', '').to_i
    retr = $db[:channels_name].where(:code => "#{loc[:table]}")
    title = retr.where(:channel_num => nnn + 1).first
    titan = title[:channel_name_eng].gsub('~','=') unless title.nil?
    title = retr.where(:channel_num => (nnn + 1) - retr.count).first if title.nil?
    titan = title[:channel_name_eng] if titan.nil?
    loc[:path] = "../temp/event-#{titan}-#{loc[:days]}.png"
    titan.gsub!('~','-')
    #p titan
    moon_type = {:'Full Moon' => ["[0:360]", "[0:0]"],
                 :'First Quarter' => ["[270:90]", "[90:270]"],
                 :'New Moon' => ["[0:0]", "[0:360]"],
                 :'Last Quarter' => ["[90:270]", "[270:90]"]}
    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        plot.terminal "png enhanced nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH}, #{LINES_SIZE_HEIGHT}"
        plot.output loc[:path]
        plot.label '1 \'mV\' at graph -0.005, graph 1.1'
        plot.rmargin '5'
        plot.tmargin '2'
        plot.lmargin '6'
        plot.label '2 \'Date\' at graph 1.007, graph 0.01'
        plot.key 'left top'
        plot.timefmt '"%Y.%m.%d.%H:%M:%S "'
        plot.xdata 'time'
        plot.xrange "['#{arr_x[0]}':'#{arr_x[-1]}']"
        plot.ytics "autofreq #{freq}"
        plot.tics 'scale 2'
        if loc[:days] > 7
          plot.xtics "#{3600 * 48}"# * loc[:days]
          plot.format 'x "%m.%d"'
        else
          plot.xtics "14400"
          plot.format 'x "%m.%d %Hh"'
        end
        plot.grid 'xtics ytics'
        brezent = 3
        sun_e.each do |sun|
          x = sun[:date].strftime("%Y.%m.%d.%H:%M:%S")
          plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
          plot.label "#{brezent} '#{sun[:type]}' at '#{x}', graph 1.05"
          brezent += 1
        end
        unless moon_e == []
          moon_e.each do |moon|
            x_moon = moon[:date]# - loc[:days] * 480
            x = moon[:date]
            x = x.strftime("%Y.%m.%d.%H:%M:%S")
            x_moon = x_moon.strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.style 'fill empty'
            plot.obj "#{brezent} circle arc #{moon_type[moon[:type].to_sym][0]} fc rgb 'black' noclip"
            plot.obj "#{brezent} circle at '#{x_moon}', graph 1.06 size screen 0.007  front"
            brezent += 1
            plot.style 'fill solid 1.0 border -1'
            plot.obj "#{brezent} circle arc #{moon_type[moon[:type].to_sym][1]} fc rgb 'black' noclip"
            plot.obj "#{brezent} circle at '#{x_moon}', graph 1.06 size screen 0.007  front"
            brezent += 1
          end
        end
        unless orb_e == []
          orb_e.each do |orb|
            x = orb[:date_event]
            x = x.strftime("%Y.%m.%d.%H:%M:%S")
            plot.arrow "from \"#{x}\",graph 0 to \"#{x}\",graph 1 nohead"
            plot.label "#{brezent} '#{orb[:type]}' at '#{x}', graph 1.05"
            brezent += 1
          end
        end
        x = event_time.strftime("%Y.%m.%d.%H:%M:%S")
        plot.arrow "from \"#{x}\",graph 1 to \"#{x}\",graph 0 head"
        plot.label "#{brezent} 'EQ-M #{event[:magnitude]}' at '#{x}', graph 1.05"
        brezent += 1
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

  def smooth3 ys
    y = []
    y.push((5*ys[0] + 2*ys[1] - ys[2])/6)
    (1...ys.size - 1).each do |i|
      y << ((ys[i - 1] + ys[i] + ys[i + 1])/(3))
    end
    y.push((5*ys[-1] + 2*ys[-2] - ys[-3])/6)
    y
  end

  def smooth7 ys
    y = []
    y << ((39*ys[0] + 8*ys[1] - 4 * (ys[2] + ys[3] - ys[4]) + ys[5] - 2*ys[6])/42)
    y << ((8*ys[0] + 19*ys[1] + 16*ys[2] + 6*ys[3] - 4*ys[4] - 7*ys[5] + 4*ys[6])/42)
    y << ((-4*ys[0] + 16*ys[1] + 19*ys[2] + 12*ys[3] + 2*ys[4] - 4*ys[5] + ys[6])/42)
    (3...ys.size - 3).each do |i|
      y << ((7*ys[i] + 6*(ys[i + 1] + ys[i - 1]) + 3*(ys[i + 2] + ys[i - 2]) - 2*(ys[i + 3] + ys[i - 3]))/21)
    end
    y << ((-4*ys[-1] + 16*ys[-2] + 19*ys[-3] + 12*ys[-4] + 2*ys[-5] - 4*ys[-6] + ys[-7])/42)
    y << ((8*ys[-1] + 19*ys[-2] + 16*ys[-3] + 6*ys[-4] - 4*ys[-5] - 7*ys[-6] + 4*ys[-7])/42)
    y << ((39*ys[-1] + 8*ys[-2] - 4 * ys[-3] - 4*ys[-4] + ys[-5] + 4*ys[-6] - 2*ys[-7])/42)
    y
  end

  def average x, y, n
    ys = []; xx = []
    i = 0
    while i < y.size
      ly = y[i...i + n].reduce(:+)
      ys.push (i + n >= y.size ? (ly/(y.size - i)) : (ly / n))
      lx = x[i + n/2] ? x[i + n/2] : x[i]
      xx << lx
      i += n
    end
    [xx, ys]
  end

end

gr = eval(ARGV[0])

$silence_gnuplot = nil
$silence_gnuplot = true unless ARGV.index '-log'
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