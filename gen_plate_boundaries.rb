require 'xmlsimple'
require 'ruby_kml'

file = File.open('data/plateboundaries.kml', 'r', &:read)
xml = XmlSimple::xml_in(file)
xml = xml['Document']
coord = []

xml.each do |x|
  if x['Placemark']
    x['Placemark'].each do |y|
      if y['MultiGeometry']
        y['MultiGeometry'].each do |z|
          z['LineString'].each do |r|
            coord << r['coordinates'].first
          end
        end
      end
    end
  end
end

kml = KMLFile.new
folder = KML::Folder.new(:name => 'boundaries')    
geo = KML::MultiGeometry.new(:name => 'boundaries_plate')
style = KML::Style.new(:id => 'red')  
plc = KML::Placemark.new(:name => 'boundaries')#, 
plc.style_url = '#red'
style.line_style = KML::LineStyle.new(:color => 'ff0000ff', :width => 2)
coord.each do |ko|
  geo.features << KML::LineString.new(:coordinates => ko)      
end
plc.features << geo
folder.features << plc  
kml.objects << style
kml.objects << folder

File.open('../web/public/plateboundaries.kml', 'w') do |file|
  file.write(kml.render)
end