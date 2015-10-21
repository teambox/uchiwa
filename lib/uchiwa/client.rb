# coding: utf-8
require 'hyperclient'
require 'json/ext'
# require '../lib/logger_override'
require '../lib/scheduler'
require '../lib/event_channel'
require '../lib/event_handler'
require '../lib/report_activity'

module Uchiwa
  class Client
    attr_accessor :access_token, :name, :domain

    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Logger

    ACTIVITY_TIMEOUT = 60

    Availability = {0 => :Away, 1 => :BeRightBack, 2 => :Busy, 3 => :DoNotDisturb, 4 => :IdleBusy,
                    5 => :IdleOnline, 6 => :Offline, 7 => :Online}

    def initialize
      yield self
      @logger = ::Logger.new(STDOUT, 'daily')
      @logger.attach("../logs/#{@name}_client.log")
      Celluloid.logger = @logger
      @application_id = set_application_id
      @ucwa_entrance = auto_discover @domain
      @entry_point_url = @ucwa_entrance.user.applications.to_s.sub(/\/ucwa.*/, '')
      @application = register_application @entry_point_url
      set_application_resources
      @scheduler = Scheduler.new do |s|
        s.url = @event_channel_url
        s.access_token = @access_token
        s.entry_point = @entry_point_url
        s.name = @name
      end
      subscribe "Lync_#{@name} event", :application_refresh
      @logger.info 'Scheduler subscribed to Lync events'
    end

    module Resource
      module Discover
        def auto_discover domain
          discoverer = Hyperclient.new("http://lyncdiscover.#{domain}")
          discoverer.connection.builder.insert_before discoverer.connection.builder.handlers.length - 1, Faraday::Response::Logger, @logger, bodies: true
          discoverer.headers.update('Content-Type' => 'application/json')

          begin
            discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            @oauth_url = e1.response[:headers]['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          end

          @xframe_url = discoverer._links[:xframe]

          # Here would be a GET request to @oauth_url for access_token

          Uchiwa.set_headers discoverer, @access_token
          return discoverer
        end

        def register_application url
          @entry_point = Hyperclient::EntryPoint.new(url)
          @entry_point.connection.builder.insert_before @entry_point.connection.builder.handlers.length - 1, Faraday::Response::Logger, @logger, bodies: true
          Uchiwa.set_headers @entry_point, @access_token

          response = @ucwa_entrance.user.applications._post(@application_id.to_json)
          Hyperclient::Resource.new(response._response.body, @entry_point, response._response)
        end

        def set_application_resources
          search_uri = @application.people.search._url
          @searcher = Hyperclient::Resource.new( { '_links' =>
                                                   { 'search' =>
                                                     { 'href' => "#{search_uri}/{?query,limit}",
                                                       'templated' => true } } },
                                                 @entry_point)

          @event_channel_url = @application.events._url
          # @report_activity_loop = ReportActivity.new(@application, @logger)
          @activity_timer = every(ACTIVITY_TIMEOUT) do
            @application.me.reportMyActivity._post('')
          end
        end

        def set_application_id
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

        def application_refresh
          @application = @application.itself._get
        end

        def get_my_presence
          @my_presence = @application.me.presence._get
        end

        def set_my_presence(availability)
          @application.me.presence._post({'availability' => availability}.to_json)
          # @my_presence = @application.me.presence._get
        end

        def get_presence_subscriptions
          @presence_subscriptions = @application.people.presenceSubscriptions._get
        end

        def get_subscribed_contacts
          @subscribed_contacts = @application.people.subscribedContacts._get
        end

        def search(query, limit = 100)
          @searcher.search({query: query, limit: limit})._resource
        end

        def get_my_contacts
          @my_contacts = @application.people.myContacts._get
        end

        def get_my_groups
          @my_groups = @application.people.myGroups._get
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
      logger.info('Starting event channel server!')
      Signal.trap("HUP") do
        t = Thread.new do
          logger.info('SIGHUP received, exiting event channel server!')
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
