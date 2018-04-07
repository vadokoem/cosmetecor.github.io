require 'sequel'
require 'logging'
require 'gnuplot'
require 'fileutils'

LINES_SIZE_WIDTH = 1536*1.5
LINES_SIZE_HEIGHT = 384*2
BOX_SIZE_WIDTH = BOX_SIZE_HEIGHT = 1024

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db', :max_connections => 4)

Sequel.default_timezone = :utc

def solar_time_diff longitude
  t = (longitude/15.0).divmod 1
  s = (t[1] * 60).divmod 1
  h = (s[1] * 60).divmod 1
  goal = t[0] * 3600 + s[0] * 60 + h[0]
  #p [longitude, goal, goal/3600.0]
  goal
end

def gen_image_line quakes
  image = nil; count = nil; db = nil; mm = {}; sensor = nil
  arr_x = []
  arr_y = []
  quakes.each do |line|
    arr_x << line[:date]
    arr_y << line[:magnitude]
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
  #freq = ((mm[:max]-mm[:min]) / 5).to_i
  freq = 0.2 #if freq <= 0
  # y1 = $db[$table].order(Sequel.asc(:date)).limit(1).first[:date].strftime("%Y/%m/%d")
  # y2 = $db[$table].order(Sequel.desc(:date)).limit(1).first[:date].strftime("%Y/%m/%d")
  name = "Magnitude >= 7. -25 <= Latitude <= 25"
  Gnuplot.open do |gp|
    Gnuplot::Plot.new( gp ) do |plot|
      plot.terminal "png nocrop font \"arial,12\" fontscale 1.0 size #{LINES_SIZE_WIDTH / 2}, #{LINES_SIZE_HEIGHT}"
      plot.output "mgn.png"
      plot.title  "#{name}"
      plot.ylabel "Mg"
      plot.xlabel "Date"
      plot.timefmt '"%H:%M:%S"'
      plot.xdata 'time'
      plot.rmargin '5'
      plot.ytics "autofreq #{freq}"
      plot.format 'x "%Hh"'
      plot.xrange '["0:0:0":"24:0:0"]'
      plot.tics 'scale 2'
      plot.xtics "#{3600}"
      plot.grid 'xtics ytics'
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

def gen_image_circle quakes, name, titul, mg
  txt_name = "../web/public/mgn_circle/mgn_circle_sum-#{mg[0]}-#{mg[1]}.txt"
  filename = "../web/public/mgn_circle/mgn_circle_#{name}-#{mg[0]}-#{mg[1]}.png"
  image = nil; count = nil; db = nil; mm = {}; sensor = nil
  arr_x = []
  arr_y = []
  max = mg[1]
  max = quakes.max{|a, b| a[:magnitude] <=> b[:magnitude]}[:magnitude].ceil if quakes && quakes.size > 0
  quakes.each do |line|
    a = line[:date].split(':')
    a = (a[0].to_i * 3600 + a[1].to_i * 60 + a[2].to_i) / 240.0
    #a = 360 - a
    #p [line[:date], a]
    arr_x << a
    arr_y << line[:magnitude]
  end

  #---------------------------
  circle_table_hours = []
  circle_table_summa = {}
  (0..23).each{|x| circle_table_hours << x}
  circle_table_hours << (23.59)
  gh = 0
  while gh < circle_table_hours.size - 1
    #p [gh, circle_table_hours[gh + 1]]
    circle_table_summa[:"t#{gh}"] = quakes.select { |s|
      tyty = s[:solar_time].strftime("%H").to_f + s[:solar_time].strftime("%M").to_f/100
    #p [, circle_table_hours[gh], circle_table_hours[gh + 1]];
      s[:solar_time].strftime("%H").to_f >= circle_table_hours[gh] &&
      s[:solar_time].strftime("%H").to_f < circle_table_hours[gh + 1]
    }.count
    #p circle_table_summa[:"t#{gh}"]
    gh += 1
  end
  #p quakes[0]
  File.open(txt_name, "a") do |e|
    e.write("[#{name}]\n")
    circle_table_summa.each_value { |re| e.write("#{re}\n")}
  end
  #---------------------------

  if $silence_gnuplot
    $std = $stderr.dup
    if RUBY_PLATFORM.downcase.index("x86_64-linux")
      $stderr.reopen '/dev/null'
    else
      $stderr.reopen 'NUL'
    end
    $stderr.sync = true
  end
  #freq = ((mm[:max]-mm[:min]) / 5).to_i
  freq = 0.2 #if freq <= 0
  # y1 = $db[$table].order(Sequel.asc(:date)).limit(1).first[:date].strftime("%Y/%m/%d")
  # y2 = $db[$table].order(Sequel.desc(:date)).limit(1).first[:date].strftime("%Y/%m/%d")
  name = "Magnitude: #{mg[0]} <= Mg < #{mg[1]}. " + titul
  brezent = 1
  Gnuplot.open do |gp|
    Gnuplot::Plot.new( gp ) do |plot|
      plot.terminal "png nocrop font \"arial,22\" fontscale 1.0 size #{BOX_SIZE_WIDTH}, #{BOX_SIZE_HEIGHT}"
      plot.output "#{filename}"
      plot.title  "#{name}"
      plot.noylabel
      plot.noxlabel
      plot.nogrid
      plot.noborder
      plot.noxaxis
      plot.noyaxis
      plot.noxtics
      plot.noytics
      plot.obj "#{brezent} circle at graph 0.5, graph 0.5 size screen 0.25 "
      brezent += 1
      arr_x.each_with_index do |n, i|
        x = n + 270
        x = x - 360 if x > 360
        x1 = Math::cos(x/(180/Math::PI))*0.276 + 0.5
        y1 = Math::sin(x/(180/Math::PI))*0.286 + 0.5
        h = ((arr_y[i] - mg[0] + 1)/(10 * (max - mg[0]))).abs
        #p ['-----------', mg[1], h]
        h1 = Math::cos(x/(180/Math::PI))*(0.276 + h) + 0.5
        h2 = Math::sin(x/(180/Math::PI))*(0.286 + h) + 0.5
        plot.arrow "from graph #{x1},graph #{y1} to graph #{h1},graph #{h2} nohead"
      end
      plot.arrow "from graph 0,graph 0.5 to graph 1,graph 0.5 nohead"
      plot.arrow "from graph 0.5,graph 0 to graph 0.5,graph 1 nohead"
      plot.label "#{brezent} '18 Hours' at graph 0.05, graph 0.51 center font \"Verdana,20\" "
      brezent += 1
      plot.label "#{brezent} '06 Hours' at graph 0.95, graph 0.51 center font \"Verdana,20\" "
      brezent += 1
      plot.label "#{brezent} '00/24 Hours' at graph 0.51, graph 0.01 font \"Verdana,20\" "
      brezent += 1
      plot.label "#{brezent} '12 Hours' at graph 0.51, graph 0.99 font \"Verdana,20\" "
      brezent += 1
      plot.data << Gnuplot::DataSet.new( [[0], [0]] ) do |ds|
        ds.with = "impulses"
        ds.linewidth = 0
        ds.notitle
        ds.using = '1:2'
      end
    end
    $stderr.reopen $std if $silence_gnuplot
  end
end

def save_mgn
  File.open('gogo_earthquakes.txt', 'w') do |f|
    quakes.each do |quake|
      z = ''
      quake.each do |k, v|
        next if k == :id
        z += v.to_s + ';'
      end
      f.write(z.chop)
      f.write("\n")
    end
  end
end

def load_mgn qqq
  File.open('gogo_earthquakes.txt', 'r') do |f|
    f.each_line do |quake|
      z = quake.split(';')
      c = {}
      c[:date] = z[0]
      c[:magnitude] = z[1].to_f
      qqq << c
    end
  end
end

$silence_gnuplot = true#nil#

$table = :earth_usgs
def get_quakes mg, eq
  eq = [eq] unless eq.class == Array
  d_right = $db[:earth_usgs].select(:date).order(Sequel.desc(:date)).limit(1).first[:date]
  d_left = (d_right - 7*3600*24).to_date + 1
  quakes = $db[$table].order(:date).where{(magnitude >= mg[0]) & (magnitude < mg[1])}.where("date >= ?", d_left)
  eq.each {|e| quakes = quakes.where(e)}
  quakes = quakes.all
  quakes.each do |quake|
    date = quake[:date]
    longitude = quake[:longitude]
    quake[:date] = (date + solar_time_diff(longitude)).strftime("%H:%M:%S")
    #p quake[:date]
  end
end

#quakes = []; load_mgn quakes
#gen_image_line quakes
#quakes.sort!{|a, b| a[:date] <=> b[:date]}
FileUtils.mkdir('../web/public/mgn_circle') unless Dir.exists?('../web/public/mgn_circle')
[[4, 5], [5, 6], [6, 11]].each do |mg|
  File.open("../web/public/mgn_circle/mgn_circle_sum-#{mg[0]}-#{mg[1]}.txt", "w"){ }
  quakes = get_quakes mg, 'latitude > 25'
  gen_image_circle quakes, "north", "latitude > 25N", mg
  quakes = get_quakes mg, ['latitude >= -25', 'latitude <= 25']
  gen_image_circle quakes, "center", "25S <= latitude <= 25N", mg
  quakes = get_quakes mg, 'latitude < -25'
  gen_image_circle quakes, "south", "latitude < 25S", mg
end

def get_quakes_6_7 mg
  d_right = $db[:earth_usgs].select(:date).order(Sequel.desc(:date)).limit(1).first[:date]
  d_left = (d_right - 30*3600*24).to_date + 1
  quakes = $db[$table].order(:date).where{(magnitude >= mg[0]) & (magnitude < mg[1])}.where("date >= ?", d_left).all
  if quakes
    qq = nil
    quborg = []
    z = 0
    quakes.each do |quake|
      (qq = quake; next) if qq.nil?
      if quake[:date] - qq[:date] > 2*24*3600
        (quborg[z] << qq) if quborg[z] && quborg[z].size > 0
        z += 1 if quborg[z] && quborg[z].size > 0
        qq = quake
        next
      else
        (quborg[z] << qq) if quborg[z]
        quborg[z] = [qq] unless quborg[z]        
        qq = quake
        next
      end
    end
    if quborg.size > 0 && quborg[z - 1].size > 0
      (quborg[z - 1] << quakes[-1]) if quakes[-1][:date] - quborg[z - 1][-1][:date] < 2*24*3600
      beer = []
      file = File.open("../web/public/power_usgs_6_7.txt", "w")
      quborg.each do |quad|
        beer << quad.map{|s| 10**(1 + 1 * s[:magnitude])}.reduce(:+)
        d1 = quad[0][:date]
        d2 = quad[-1][:date]
        beer[-1] = beer[-1] / (d2 - d1)
        str = ''
        str += d1.strftime("%Y.%m.%dT%H:%M:%SZ;")
        str += d2.strftime("%Y.%m.%dT%H:%M:%SZ;")
        str += beer[-1].to_s + ';'
        str += quad.size.to_s + "\n"
        file.write(str)
      end
      file.close
    else
      File.open("../web/public/power_usgs_6_7.txt", "w") {}
    end
  else
    File.open("../web/public/power_usgs_6_7.txt", "w") {}
  end
end

get_quakes_6_7 [6, 7]
