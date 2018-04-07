require 'sequel'
require 'xmlsimple'
require 'kamel'
require 'zip'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db')
Sequel.default_timezone = :utc

class Array
  def to_f
    self.map! {|a| a.to_f}
  end
end

module Zip
  class Entry
    def set_time(binary_dos_date, binary_dos_time)
      @time = ::Zip::DOSTime.parse_binary_dos_format(binary_dos_date, binary_dos_time)
    rescue ArgumentError
      #puts "Invalid date/time in zip entry"
    end
  end
end

class Polygon
  attr_reader :points, :name

  def initialize init, name = nil
    if init.class == Array
      @points = init
    else
      @name = name[0...-4]
      xml = XmlSimple::xml_in(init)
      xml = xml['Document']
      xml.each do |x|
        if x['Placemark']
          x['Placemark'].each do |y|
            y['LineString'].each do |r|
              coord = r['coordinates'].first.strip.split(' ')
              coord.map!{|a| a.split(',')[0..1]}
              @points = coord.to_f
            end
          end
        end
      end
    end
  end

  def signum x
    x > 0 ? 1 : (x < 0 ? -1 : 0)
  end

  def check_edge from_, to_, cur_
    from = from_.dup
    to = to_.dup
    cur = cur_.dup
    to[0] += 360 if to[0] < 0
    from[0] += 360 if from[0] < 0
    cur[0] += 360 if cur[0] < 0

    ax = (from[0] - cur[0])
    ay = (from[1] - cur[1])
    bx = (to[0] - cur[0])
    by = (to[1] - cur[1])
    s = signum(ax * by - ay * bx)
    #return 0 if (s == 0 && (ay == 0 || by == 0) && ax * bx <= 0)
    if ((ay < 0) ^ (by < 0))
        return s if (by < 0)
        return -s
    end
    1
  end

  def check_point m
    gipgip = 1
    (0...@points.size-1).each do |p|
      gipgip *= check_edge *@points[p..p+1], m
    end
    gipgip
  end
end

class Poly_array
  include Enumerable
  def initialize
    @polys = []
  end

  def read_dir path
    filenames = Dir.entries(path).select {|f| !File.directory? f}
    filenames = filenames.select {|f| File.extname(f).downcase == '.kmz'}
    filenames.sort.each do |file|
      file = file.encode('UTF-8').force_encoding('UTF-8')
      Zip::File.open('kmz_plates/' + file) do |zip_file|
        content = zip_file.first.get_input_stream.read
        poly = Polygon.new content, file
        @polys << poly
      end
      # Find specific entry
      # entry = zip_file.glob('*.csv').first
      # puts entry.get_input_stream.read
    end
  end

  def check_points points
    points.each do |point|
      n = 0
      @polys.each do |poly|
        if (poly.check_point point) == -1
          point << n
          break
        end
        n += 1
      end
      point << -1 if point.size == 2
    end
    points
  end

  def [](i)
    @polys[i]
  end

  def each(&block)
    @polys.each(&block)
  end

  def generate_plates
    kml = KMLFile.new
    folder = KML::Folder.new(:name => 'boundaries')
    #geo = KML::MultiGeometry.new(:name => 'boundaries_plate')
    #style = KML::Style.new(:id => 'red')#,
    #plc.style_url = '#red'
    #style.line_style = KML::LineStyle.new(:color => 'ff0000ff', :width => 2)
    @polys.each do |ko|
      hg = []
      ko.points.each {|nj| hg << nj.join(',')}
      hg = hg.join(' ')
      plc = KML::Placemark.new(:name => "#{ko.name}")
      plc.features << KML::LineString.new(:coordinates => hg)
      folder.features << plc
    end
    #kml.objects << style
    kml.objects << folder

    File.open('../web/public/plates_graphs.kml', 'w') do |file|
      file.write(kml.render)
    end
  end
end

poly_king = Poly_array.new
poly_king.read_dir 'kmz_plates'
#poly_king.generate_plates
greedy = []

d_right = $db[:earth_usgs].select(:date).order(Sequel.desc(:date)).limit(1).first[:date]
d_left = (d_right - 7*3600*24).to_date + 1

$db[:earth_usgs].order(:date).where('date >= ?', d_left).
                              where('magnitude >= 5').
                              where('magnitude < 6').all.each do |quake|#
  greedy << [quake[:longitude], quake[:latitude]]
end

poly_king.check_points greedy

green = greedy.select{|a| a[2] >= 0}

#================
st = green.shift
sum = 0
green.each do |gr|
  (st = gr; next) unless st
  (sum += 1; st = nil) if gr[2] == st[2]
end