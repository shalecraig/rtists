require 'configatron'

class PushBulletClient
  def self.client
    @instance ||= PushBulletClient.new
  end

  private

  def initialize
    @client = Washbullet::Client.new(configatron.pushbbullet.access_token)
  end
end
