require 'httparty'
require 'logger'
require 'pry'
require 'ruby-progressbar'
require 'seatgeek'
require 'slugify'
require 'spotify-client'
require 'stubhub'

require_relative 'config'
require_relative 'models'
require_relative 'lib'

<<-EOF

TODOs:
[x] Unified "artist" types
[ ] Followed albums https://developer.spotify.com/web-api/get-users-saved-albums/
[ ] Followed tracks https://developer.spotify.com/web-api/get-users-saved-tracks/
[x] DB usage
[x] Persist artists
[ ] Unified "event" types
[ ] Persist events
[ ] Being able to compute the difference in prices wrt time
[ ] Separation of API from responses
[ ] Stubhub api
[ ] Ticketfly api
[ ] Async running (nightly? 12/6h?)
[ ] Notifications about the deltas

EOF

spotify = SpotifyClient.instance
followed_artists =   spotify.
  followed_artists.
  flat_map { |a| Artist.from_spotify_artist_blob(a) }

track_artists = spotify.
  fav_tracks.
  flat_map { |t| t['track']['artists'] }.
  uniq { |r| r['id'] }.
  flat_map { |a| Artist.from_spotify_artist_blob(a) }

artists = (track_artists + followed_artists).uniq { |a| a.spotify_id ? a.spotify_id : a.name }
puts "Found #{track_artists.length} from tracks, and #{followed_artists.length} being followed - #{artists.length} total unique artists."

logger = Logger.new(STDOUT)
logger.level = Logger::WARN
SeatGeek::Connection.logger = logger
sg = SeatGeek::Connection.new({:protocol => :https})

progress = ProgressBar.create( :format         => '%a %bᗧ%i %p%% %t',
                    :progress_mark  => ' ',
                    :remainder_mark => '･')
progress.total = artists.length
iter = 0
artists.each do |artist|
  slug = artist.name.slugify

  result = sg.events({'performers.slug' => slug, 'geoip' => true})
  sg_events = result['events']

  progress.increment
  iter += 1

  next if sg_events.empty?
  progress.log("#{artist.name}:")

  sg_events.each do |event|
    title = event.act_primary
    venue_name = event.name_primary
    venue_city = event.city
    event_timestamp = "wat"

    min = [event.minPrice, event.maxPrice].min
    pricing_string = " Tickets ~$#{min}"

    min_list = event.minListPrice
    if min_list && min_list < min
      pricing_string += " (#{min_list} is good)"
    end

    progress.log  "\t - #{title} @#{venue_name} (#{venue_city}) on #{event_timestamp} #{pricing_string} "
  end
end
