module ArtistRepresenter
  include Roar::Representer::JSON
  include Roar::Representer::Feature::Hypermedia

  property :name
  property :instrument, :class => Artists::Instrument, :extend => InstrumentRepresenter

  link :self do  
    artist_url id
  end
end
