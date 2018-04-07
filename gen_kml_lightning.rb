require 'sequel'
require 'kamel'

$db = Sequel.mysql2(:user => 'root', :password => 'skif13', :database=>'db')

Sequel.default_timezone = :utc

overlay = Kamel::Overlay.new
overlay.name = 'Lightning'

d_right = $db[:lightning].select(:date).order(Sequel.desc(:date)).limit(1).first[:date].to_date + 1
d_right = Time.parse(ARGV[0]).to_date if ARGV[0]
d_left = d_right - 1
$db[:lightning].order(Sequel.asc(:date)).where("date >= ?", d_left).
                                         where("date < ?", d_right).all.each do |strike|
  overlay.placemark!(:name => strike[:date].strftime("%Y/%m/%d %H:%M:%S") + "; #{strike[:coord_x]}°, #{strike[:coord_y]}°",
                     :location => {:lng => strike[:coord_x], :lat => strike[:coord_y]},
                     :icon => 'https://cosmetecor.org/lightning.png')
end

filename = '../web/public/lightning.kml'
filename = d_left.strftime("../web/public/lightning/lightning-%Y-%m-%d.kml") if ARGV[0]
File.open(filename, 'w') do |file|
  file.write(overlay.to_kml)
end