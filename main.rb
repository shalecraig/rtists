require 'httparty'
require 'logger'
require 'pry'
require 'ruby-progressbar'
require 'seatgeek'
require 'slugify'
require 'spotify-client'
require 'stubhub'
require 'configatron'

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

def self.get_artists_from_fav_tracks(spotify)
  spotify.
    fav_tracks.
    flat_map { |t| t['track']['artists'] }.
    uniq { |r| r['id'] }.
    flat_map { |a| Artist.from_spotify_artist_blob(a) }
end

def self.get_followed_artists(spotify)
  spotify.
    followed_artists.
    flat_map { |a| Artist.from_spotify_artist_blob(a) }
end

spotify = SpotifyClient.instance
followed_artists = get_followed_artists(spotify)
track_artists = get_artists_from_fav_tracks(spotify)
artists = (track_artists + followed_artists).uniq { |a| a.spotify_id ? a.spotify_id : a.name }
puts "Found #{track_artists.length} from tracks, and #{followed_artists.length} being followed - #{artists.length} total unique artists."

logger = Logger.new(STDOUT)
logger.level = Logger::WARN
SeatGeek::Connection.logger = logger
sg = SeatGeek::Connection.new({:protocol => :https})

# Interesting
# sg.events({'performers.slug' => 'justin-bieber'}) -> works
# sg.events({'performers.slug' => 'Justin-Bieber'}) -> Doesn't Work
# sg.events({'performers.slug' => 'Justin Bieber'}) -> Doesn't Work
# sg.events({'performers.slug' => 'Justin+Bieber'}) -> Doesn't Work

progress = ProgressBar.create( :format         => '%a %bᗧ%i %p%% %t',
                    :progress_mark  => ' ',
                    :remainder_mark => '･')

progress.total = artists.length
iter = 0
artists.each do |artist|
  slug = artist.name.slugify

  result = sg.events({'performers.slug' => slug, 'geoip' => true})
  sg_events = result['events']

  sh_events = nil
  # while sh_events.nil? do
  #   begin
  #     sh_events = Stubhub::Event.search(name, city: CGI::escape('San Francisco'), state: 'CA')
  #   rescue
  #   end
  # end
  sh_events ||= []
  sh_events = sh_events.
    select { |e| e.eventLocation_facet_str.downcase.include?('sf') || e.eventLocation_facet_str.downcase.include?('bay area') }

  progress.increment
  iter += 1

  next if (sh_events || []).empty? && (sg_events || []).empty?
  progress.log("#{artist.name}:")

  sh_events.each do |event|
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

  # best_id = sg_events.max { |e| e['score'] }['id']
  sg_events.sort { |e| e['score']}.reverse.each do |event|
    # best = event['id'] == best_id
    stats = event['stats']
    venue = event['venue']
      venue_city = venue['city']
      venue_name = venue['name']
      venue_country = venue['country']
      venue_state = venue['state']
      venue_score = venue['score']

    # listing details
    listing_count = stats['listing_count']

    average_price = stats['average_price']
    lowest_price_good_deals = stats['lowest_price_good_deals']
    lowest_price = stats['lowest_price']
    highest_price = stats['highest_price']
    best_price = [average_price, lowest_price_good_deals, lowest_price, highest_price, 100_000_000].compact.min

    title = event['title']

    # TODO: determine event time
    datetime_local = event['datetime_utc'] + " UTC"
    parsed = Time.parse(datetime_local)
    # event_timestamp = 'Tue Jan 1, 18:30'
    # TODO: use the right tz in this form.
    event_timestamp = parsed.localtime.strftime('%a %b %e, %k:%M')

    score = event['score']

    pricing_string = if best_price < 100_000_000
      " Tickets ~$#{best_price}"
    else
      ""
    end
    progress.log  "\t - #{title} @#{venue_name} (#{venue_city}) on #{event_timestamp} [#{score}]#{pricing_string} "
  end
end
