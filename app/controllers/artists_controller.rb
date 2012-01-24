class ArtistsController < ApplicationController
  # GET artists/:id
  def show
    artist =   Artist.find(params[:id])
    # ONLY works if embedded instrument is NOT part of the representer, see ArtistRepresenter
    respond_with artist.extend(ArtistRepresenter)
  end

  # quick and dirty create artist with instrument 
  def create
    artist = Artist.new(name:"MyArtist", )
    artist.build_instrument(name: "guitar")
    artist.save
  end

  # No representers needed
  def index 
    respond_with Artist.all
  end
end
