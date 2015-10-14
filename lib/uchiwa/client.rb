# coding: utf-8
require 'hyperclient'
require 'json/ext'
require 'angelo'

module Uchiwa
  class Client
    availability = {0 => :Away, 1 => :BeRightBack, 2 => :Busy, 3 => :DoNotDisturb, 4 => :IdleBusy,
                    5 => :IdleOnline, 6 => :Offline, 7 => :Online}

    def initialize(config = {})
      @config = config
    end

    module Resource
      module Discover
        def discover
          discoverer = Hyperclient.new('https://lyncdiscover.metio.net')
          discoverer.connection.response :logger, @config[:logger], bodies: true
          discoverer.headers.update('Content-Type' => 'application/json')

          begin
            discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            headers = e1.response[:headers]
          end

          @oauth_url = headers['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          @xframe_url = discoverer._links[:xframe]

          # Here would be a GET request to @oauth_url for access_token

          set_headers discoverer

          @entry_point = Hyperclient::EntryPoint.new(discoverer.user.applications.to_s.sub(/\/ucwa.*/, ''))
          @entry_point.connection.response :logger, @config[:logger], bodies: true
          set_headers @entry_point

          response = discoverer.user.applications._post(application_id.to_json)
          @application = Hyperclient::Resource.new(response._response.body, @entry_point,
                                                   response._response)
          search_uri = @application.people.search._url
          @searcher = Hyperclient::Resource.new( { '_links' =>
                                                   { 'search' =>
                                                     { 'href' => "#{search_uri}/{?query,limit}",
                                                       'templated' => true } } },
                                                 @entry_point)
          event_channel_url = @application.events._url
          # @event_channel = Hyperclient::Resource.new(event_channel_url, @entry_point)
          @event_channel = Hyperclient::Resource.new({ '_links' =>
                                                       {'events' =>
                                                         {'href' => "#{event_channel_url}"}}},
                                                     @entry_point)
        end

        def application_id
          {
            :UserAgent  => "UCWA Samples",
            :EndpointId => SecureRandom.uuid,
            :Culture    => "en-US",
          }
        end

        def access_token
          @config[:access_token] ||= begin
            oauth
          end
        end

        def oauth
          client = Hyperclient.new(@oauth_url)
          client  # TODO
        end

        def set_headers(end_point, etag = '')
          end_point.headers.update('Content-Type' =>	'application/json')
          end_point.headers.update('Authorization' => "#{access_token}")

          # This is barely needed - for browsers only
          # end_point.headers.update('X-Ms-Origin' => 'http://localhost')

          end_point.headers.update('Referer' => "#{@xframe_url}")

          # This should be reimplemented to be automatically set on PUT requests if needed
          end_point.headers.update('If-Match' => etag) unless etag.empty?
        end

        def make_available body
          @application.me.makeMeAvailable._post(body.to_json)
          @application = @application.itself._get
        end

        def get_my_presence
          @my_presence = @application.me.presence._get
        end

        def set_my_presence(availability)
          @application.me.presence._post({'availability' => availability}.to_json)

          # The following barely needed - should see what event receiving will bring
          @application = @application.itself._get
          @my_presence = @application.me.presence._get
        end

        def search(query, limit = 100)
          @searcher.search({query: query, limit: limit})._resource
        end

        def get_contact_presence(contact)
          contact.contactPresence._get
        end

        def event_channel_poll
          @event_channel = @event_channel.events._get
        end
      end
    end

    # TODO: This will work only via conditional request PUT (with the If-Match: "{ETag value}"
    # new_key = @application.communication[:_attributes].to_h.key('please pass this in a PUT
    # request')
    # body[new_key] = body.delete body.key('please pass this in a PUT request')
    # body[:etag] = @application.communication[:_attributes][:etag]
    # set_headers @entry_point, body[:etag]

    # def get_contact_list
    # @application._embedded._get.people.myContacts
    # @contacts = @application.people.myContacts
    # end

    include Resource::Discover
  end

  class EventChannelServer < Angelo::Base
    addr '0.0.0.0'
    port 8080
    ping_time 3
    report_errors!
    log_level Logger::DEBUG

    def pong; 'pong'; end

    def hello; 'Hello there!'; end

    task :hello do
      hello
    end

    task :pong do
      pong
    end

    get '/' do
      # async :hello
      hello
    end

    get '/ping' do
      # async :pong
      pong
    end
  end

  def Uchiwa.start_event_channel_server(logger)
    @server_pid = fork do
      logger.info('Starting event channel!')
      Signal.trap("HUP") do
        t = Thread.new do
          logger.info('SIGHUP received, exiting!')
        end
        exit
      end

      begin
        Uchiwa::EventChannelServer.run!
      rescue => e
        logger.error("ERROR => #{e}\n#{e.inspect}")
      end
    end
  end

  def Uchiwa.stop_event_channel_server
    Process.kill('HUP', @server_pid)
  end
end
