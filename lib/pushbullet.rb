require 'configatron'
require 'httparty'

module PushBulletClient
  def self.me
    self.do_send(:get, '/v2/users/me')
  end

  def self.active_devices
    resp = self.do_send(:get, '/v2/devices')
    return resp unless resp[0] == 200
    resp[0]['devices'].select { |x| x['active'] }
  end

  def self.send_message(title, text)
    device_iden ||= active_devices.first['iden']
    self.do_send(:post, '/v2/pushes', body: {type: 'note', title: title, body: text, device_iden: device_iden} )
  end

  private

  def self.do_send(method, uri, body: nil, headers: nil)
    headers = (headers || {}).merge(default_headers)
    raise "urls must start with a slash - #{uri} doesn't" unless uri.start_with?('/')
    url = "#{base_url}#{uri}"

    case method.to_sym
    when :post
      the_request = lambda { HTTParty.post(url, body: body, headers: headers) }
    when :get
      raise 'No query allowed for get requests' if body
      the_request = lambda { HTTParty.get(url, headers: headers) }
    else
      raise "I don't know how to handle #{method} requests."
    end
    response = the_request.call
    [response, response.code]
  end

  def self.default_headers
    {
      'Access-Token' => configatron.pushbullet.access_token,
    }
  end

  def self.base_url
    'https://api.pushbullet.com'
  end
end
