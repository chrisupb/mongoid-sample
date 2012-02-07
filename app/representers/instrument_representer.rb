module InstrumentRepresenter
  include Roar::Representer::JSON
  include Roar::Representer::Feature::Hypermedia

  property :name

  # undefined local variable or method `artists_url' for #<Artists::Instrument:0x00000003e4ad60>
  link :self do  
    artists_url
  end

end
