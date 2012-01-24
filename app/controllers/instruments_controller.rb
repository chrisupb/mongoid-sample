class InstrumentsController < ApplicationController
  # GET artists/:artidt_id/instrument
  def show 
    user = Artist.find(params[:artist_id])
    # fails with undefined method `representable_attrs' for Artists::Instrument:Class
    respond_with user.instrument.extend(InstrumentRepresenter)
  end
end
