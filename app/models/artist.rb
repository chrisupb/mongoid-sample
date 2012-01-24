class Artist
  include Mongoid::Document
  field :name, :type => String
         
  embeds_one :instrument, :class_name => "Artists::Instrument"
  accepts_nested_attributes_for :instrument
end
