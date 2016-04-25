require 'httparty'
require 'logger'
require 'optparse'
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
[x] DB usage
[x] Persist artists
[x] Event type
[x] Persist events
[x] Notifications about new events
[ ] Followed albums https://developer.spotify.com/web-api/get-users-saved-albums/
[ ] Followed tracks https://developer.spotify.com/web-api/get-users-saved-tracks/
[ ] Being able to compute the difference in prices wrt time
[ ] Separation of API from responses
[ ] Stubhub api
[ ] Ticketfly api
[ ] Async running (nightly? 12/6h?)
[ ] Notifications about price drops/raises

EOF

options = {
  update_spotify: true
}
OptionParser.new do |opts|
  opts.on('-c', '--use-spotify-cache', "Skip reloading Spotify Fav'd Artists") do
    options[:update_spotify] = false
  end
end.parse!

if options[:update_spotify]
  spotify = SpotifyClient.instance
  followed_artists = spotify.
    followed_artists.
    flat_map { |a| Artist.from_spotify_artist_blob(a) }

  track_artists = spotify.
    fav_tracks.
    flat_map { |t| t['track']['artists'] }.
    uniq { |r| r['id'] }.
    flat_map { |a| Artist.from_spotify_artist_blob(a) }

  artists = (track_artists + followed_artists).uniq { |a| a.spotify_id ? a.spotify_id : a.name }
  puts "Found #{track_artists.length} from tracks, and #{followed_artists.length} being followed - #{artists.length} total unique artists."
else
  artists = Artist.all.uniq { |a| a.spotify_id ? a.spotify_id : a.name }
  puts "Using cached artists - #{artists.length} found."
end

logger = Logger.new(STDOUT)
logger.level = Logger::WARN
SeatGeek::Connection.logger = logger
sg = SeatGeek::Connection.new({:protocol => :https})

progress = ProgressBar.create(
  :format => '%a %bᗧ%i %p%% %t',
  :progress_mark  => ' ',
  :remainder_mark => '･',
)

progress.total = artists.length
iter = 0
artists.each do |artist|
  slug = artist.name.slugify
  if slug.empty?
    progress.log "Skipped empty slug from #{artist.name}"
    next
  end

  # result = sg.events({'performers.slug' => slug, 'geoip' => true}) # "Local"
  result = sg.events({'performers.slug' => slug, 'geoip'=>'208.113.83.165'}) # SF
  # result = sg.events({'performers.slug' => slug, 'geoip'=>'206.196.115.38'}) # STL
  # result = sg.events({'performers.slug' => slug, 'geoip'=>'167.114.42.219'}) # Montreal
  # result = sg.events({'performers.slug' => slug, 'geoip'=>'192.206.151.131'}) # Toronto
  # TODO: make locations selectable?
  sg_events = result['events']

  progress.increment
  iter += 1

  if !sg_events
    progress.log("Empty result for #{slug}")
    progress.log(result)
    next
  elsif sg_events.empty?
    next
  end
  progress.log("#{artist.name}:")

  sg_events.sort { |e| e['score']}.reverse.each do |event|
    id = event['id']
    stats = event['stats']
    venue = event['venue']
    venue_city = venue['city']
    venue_name = venue['name']
    venue_country = venue['country']
    venue_state = venue['state']
    venue_score = venue['score']

    prior_event = Event.contains?(id)

    # listing details
    listing_count = stats['listing_count']

    average_price = stats['average_price']
    lowest_price_good_deals = stats['lowest_price_good_deals']
    lowest_price = stats['lowest_price']
    highest_price = stats['highest_price']
    best_price = [average_price, lowest_price_good_deals, lowest_price, highest_price, 100_000_000].compact.min

    title = event['title']

    datetime_local = event['datetime_utc'] + " UTC"
    parsed = Time.parse(datetime_local)
    event_timestamp = parsed.localtime.strftime('%a %b %e, %k:%M')
    short_ts = parsed.localtime.strftime('%b %e (%a)')

    score = event['score']

    prior_string = ""
    if !prior_event
      prior_string = " 🎉🎉🎉🎉"
      Event.create(seatgeek_id: id, title: title)
      short_title = "New #{artist.name} Concert!"
      short_description = "#{title} - #{short_ts} @ #{venue_city}"
      PushBulletClient.send_message(short_title, short_description)
    end

    pricing_string = if best_price < 100_000_000
      " Tickets ~$#{best_price}"
    else
      ""
    end
    progress.log  "\t - #{title} @#{venue_name} (#{venue_city}) on #{event_timestamp} [#{score}]#{pricing_string}#{prior_string}"
  end
end
