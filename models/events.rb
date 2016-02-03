ActiveRecord::Schema.define do
  unless ActiveRecord::Base.connection.tables.include? 'events'
    create_table :events do |table|
      table.column :seatgeek_id, :integer
      table.column :title,        :string
      # TODO: reference the artist that this corresponds to
    end
  end
end


class Event < ActiveRecord::Base
  def self.contains?(seatgeek_id)
    Event.find_by(seatgeek_id: seatgeek_id)
  end
end
