module ArtistRepresenter
  include Roar::Representer::JSON

  property :name
  # Error: undefined method `representable_attrs' for Artists::Instrument:Class
  # Uncomment => no error 
  property :instrument, :class => Artists::Instrument, :extend => InstrumentRepresenter

end
