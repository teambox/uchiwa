# coding: utf-8
require 'hyperclient'
require 'json/ext'
require '../lib/scheduler'
require '../lib/event_channel'

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
          discoverer.connection.builder.insert_before discoverer.connection.builder.handlers.length - 1, Faraday::Response::Logger, @config[:logger], bodies: true
          discoverer.headers.update('Content-Type' => 'application/json')

          begin
            discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            headers = e1.response[:headers]
          end

          @oauth_url = headers['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          @xframe_url = discoverer._links[:xframe]

          # Here would be a GET request to @oauth_url for access_token

          Uchiwa.set_headers discoverer, @config[:access_token]

          @entry_point = Hyperclient::EntryPoint.new(discoverer.user.applications.to_s.sub(/\/ucwa.*/, ''))
          @entry_point.connection.builder.insert_before @entry_point.connection.builder.handlers.length - 1, :logger, @config[:logger], bodies: true
          Uchiwa.set_headers @entry_point, @config[:access_token]

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
          @scheduler = Scheduler.new(event_channel_url, @config[:access_token], @entry_point)
        end

        def application_id
          {
            :UserAgent  => "UCWA Samples",
            :EndpointId => SecureRandom.uuid,
            :Culture    => "en-US",
          }
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

  def Uchiwa.set_headers(end_point, access_token, etag = '')
    end_point.headers.update('Content-Type' =>	'application/json')
    end_point.headers.update('Authorization' => "#{access_token}")

    # This is barely needed - for browsers only
    # end_point.headers.update('X-Ms-Origin' => 'http://localhost')

    end_point.headers.update('Referer' => "#{@xframe_url}")

    # This should be reimplemented to be automatically set on PUT requests if needed
    end_point.headers.update('If-Match' => etag) unless etag.empty?
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
        EventChannelServer.run!
      rescue => e
        logger.error("ERROR => #{e}\n#{e.inspect}")
      end
    end
  end

  def Uchiwa.stop_event_channel_server
    Process.kill('HUP', @server_pid)
  end
end
