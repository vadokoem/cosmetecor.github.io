require 'sequel'
require 'xmlsimple'
require 'kamel'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db')

Sequel.default_timezone = :utc

d_right = $db[:earth_usgs].select(:date).order(Sequel.desc(:date)).limit(1).first[:date]
d_left = (d_right - 7*3600*24).to_date + 1

[[4, 5], [5, 6], [6, 11]].each do |mg|
  kml = KMLFile.new
    $db.transaction do
      folder = KML::Folder.new(:name => 'bound')
      geo = KML::MultiGeometry.new(:name => 'Boundaries')
      style = KML::Style.new(:id => 'orange')
      plc = KML::Placemark.new(:name => 'bum')#,
      plc.style_url = '#orange'
      style.line_style = KML::LineStyle.new(:color => 'ff00cfff', :width => 2)
      ko = []
      $db[:earth_usgs].order(:date).where("date >= ?", d_left).
                       where{(magnitude >= mg[0]) & (magnitude < mg[1])}.all.each do |quake|
        ko << [quake[:longitude], quake[:latitude]]
      end
      geo.features << KML::LineString.new(:coordinates => ko)
      plc.features << geo
      folder.features << plc

      kml.objects << style
      kml.objects << folder
    end
  File.open("../web/public/earth_quake_bound_#{mg[0]}-#{mg[1]}.kml", 'w') do |file|
    file.write(kml.render)
  end

  kml = KMLFile.new
    $db.transaction do
      folder = KML::Folder.new(:name => 'bound')
      style = KML::Style.new(:id => 'green')
      style.icon_style = KML::IconStyle.new(:color => 'ff00cc00', :icon => KML::Icon.new(:href => 'https://maps.google.com/mapfiles/kml/paddle/blu-blank.png'))
      o = 0
      desc_start = nil
      $db[:earth_usgs].order(:date).where("date >= ?", d_left).
                       where{(magnitude >= mg[0]) & (magnitude < mg[1])}.all.each do |quake|
        o += 1
        desc_start = quake[:date].to_i if o < 2
        desc = quake[:date].to_i - desc_start.to_i
        folder.features << KML::Placemark.new(
          :name => "#{quake[:longitude]}°, #{quake[:latitude]}°; #{quake[:date].strftime("%Y/%m/%d %H:%M:%S")}; Magnitude = #{quake[:magnitude]}",
          :description => desc.to_s,
          :geometry => KML::Point.new(:coordinates => {:lat => quake[:latitude], :lng => quake[:longitude]}))
      end
      kml.objects << style
      kml.objects << folder
    end
  File.open("../web/public/earth_quake_pin_#{mg[0]}-#{mg[1]}.kml", 'w') do |file|
    file.write(kml.render)
  end
end