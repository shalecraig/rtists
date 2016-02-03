SCOPES = {
  "playlist-read-private" => %s{Read access to user's private playlists.  "Access your private playlists"},
  "playlist-read-collaborative" => %s{Include collaborative playlists when requesting a user's playlists. "Access your collaborative playlists"},
  "playlist-modify-public" => %s{ Write access to a user's public playlists.  "Manage your public playlists"},
  "playlist-modify-private" => %s{Write access to a user's private playlists. "Manage your private playlists"},
  "streaming" => %s{Control playback of a Spotify track. This scope is currently only available to Spotify native SDKs (for example, the iOS SDK and the Android SDK). The user must have a Spotify Premium account.  "Play music and control playback on your other devices"},
  "user-follow-modify" => %s{ Write/delete access to the list of artists and other users that the user follows. "Manage who you are following"},
  "user-follow-read" => %s{ Read access to the list of artists and other users that the user follows. "Access your followers and who you are following"},
  "user-library-read" => %s{Read access to a user's "Your Music" library. (NOTE: Although 'Albums' is included in these permissions, the relevant endpoint is not yet available)  "Access your saved tracks and albums"},
  "user-library-modify" => %s{Write/delete access to a user's "Your Music" library. (NOTE: Although 'Albums' is included in these permissions, the relevant endpoint is not yet available)  "Manage your saved tracks and albums"},
  "user-read-private" => %s{Read access to user’s subscription details (type of user account).  "Access your subscription details"},
  "user-read-birthdate" => %s{Read access to the user's birthdate.  "Receive your birthdate"},
  "user-read-email" => %s{Read access to user’s email address.  "Get your real email address"},
}

ALL_SCOPES = SCOPES.keys.join(' ')

REFRESH_TOKEN = configatron.spotify.refresh_token
CLIENT_ID = configatron.spotify.client_id
CLIENT_SECRET = configatron.spotify.client_secret

DEFAULT_CONFIG = {
    :raise_errors => true,  # choose between returning false or raising a proper exception when API calls fails

    # Connection properties
    :retries       => 0,    # automatically retry a certain number of times before returning
    :read_timeout  => 10,   # set longer read_timeout, default is 10 seconds
    :write_timeout => 10,   # set longer write_timeout, default is 10 seconds
    :persistent    => false # when true, make multiple requests calls using a single persistent connection. Use +close_connection+ method on the client to manually clean up sockets
}

class SpotifyClient
  def self.instance(verbose: false)
    if verbose && @client
      puts "Client exists, early returning."
    end
    @client ||= SpotifyClient.new(verbose: true)
  end

  def wrapped
    @client
  end

  def roll!
    auth_request = HTTParty.post(
      'https://accounts.spotify.com/api/token',
      body: {
        grant_type: 'refresh_token',
        refresh_token: REFRESH_TOKEN,
        # redirect_uri: 'http://localhost/',
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
      }
    )
    access_token = auth_request['access_token']
    puts "Spotify access token: #{access_token}" if @verbose
    config = {
      :access_token => access_token,  # initialize the client with an access token to perform authenticated calls
    }.merge(DEFAULT_CONFIG)
    @client = Spotify::Client.new(config)
    me = @client.me
    puts "auth'd as #{me['display_name']} (#{me['id']}) -- #{me['followers']['total'] || 0} followers." if @verbose
  end

  def me
    @client.me
  end

  ITER_LIMIT = 50
  def fav_tracks
    offset = 0
    tracks = []
    progress = ProgressBar.create
    using_progress = false
    while true do
      track_iter = @client.send(:run, :get, "/v1/me/tracks?offset=#{offset}&limit=#{ITER_LIMIT}", [200])
      using_progress = (track_iter['total'] > ITER_LIMIT*2)
      progress.total = track_iter['total'] if using_progress
      progress.progress += track_iter['items'].length if using_progress
      tracks += track_iter['items']
      offset += track_iter['items'].length
      if offset >= track_iter['total']
        break
      end
    end
    tracks
  end

  private
  def initialize(verbose: false)
    @refreshed = false
    @verbose = verbose
    roll!
  end
end
