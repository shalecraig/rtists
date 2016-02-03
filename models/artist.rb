ActiveRecord::Schema.define do
  unless ActiveRecord::Base.connection.tables.include? 'artists'
    create_table :artists do |table|
      table.column :spotify_id, :string
      table.column :name,       :string
    end
  end
end


class Artist < ActiveRecord::Base
  # TODO: make this work with other things.
  def self.upsert!(spotify_id: nil, name: nil)
    params = {}
    params[:spotify_id] = spotify_id if spotify_id
    params[:name] = name if name
    Artist.find_or_create_by(params)
  end

  def self.from_spotify_artist_blob(json_blob)
    name = json_blob['name']
    id = json_blob['id']
    non_extrapolated = [Artist.upsert!(spotify_id: id, name: name)]

    # Try all variants of the name(s)
    extrapolated = (name.split('&') + name.split(',') - [name]).
      map(&:strip).
      uniq.
      map do |name|
        # TODO: merge more fields into here?
        Artist.upsert!(name: name)
    end
    extrapolated + non_extrapolated
  end
end
