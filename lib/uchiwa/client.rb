# coding: utf-8
require'uri'
require 'hyperclient'
require 'json/ext'
require '../lib/logger_override'
require 'celluloid/current'
require '../lib/hal_resources'
require '../lib/scheduler'
require '../lib/event_channel'
require '../lib/event_handler'

module Uchiwa
  class Client
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Internals::Logger

    def initialize(username, password, domain)
      @logger = ::Logger.new(STDOUT, 'daily')
      logger.attach("../logs/client.log")
      Celluloid.logger = logger

      @username = username
      @password = password
      @domain = domain
      @ucwa_entrance = auto_discover(domain)
      @application = register_application
      set_application
    end

    private

    attr_accessor :username, :password, :domain, :oauth_endpoint, :ucwa_entrance, :entry_point,
                  :logger, :application, :event_handler, :event_channel

    module Application
      def auto_discover(domain)
        discoverer = Hyperclient.new("http://lyncdiscover.#{domain}")
        discoverer.connection.builder.insert_before discoverer.connection.builder.handlers.length - 1,
                                                    Faraday::Response::Logger, @logger, bodies: true

        begin
          discoverer.user._get.headers
        rescue Faraday::Error::ClientError => e1
          oauth_url = e1.response[:headers]['www-authenticate'].to_s.match(/href="([^"]*)/)[1]
        end

        @oauth_endpoint = Hyperclient::EntryPoint.new(oauth_url)
        oauth_endpoint.connection.builder.insert_before oauth_endpoint.connection.builder.handlers.length - 1,
                                                        Faraday::Response::Logger, logger, bodies: true
        oauth_endpoint.headers.update('Content-Type' =>	'application/x-www-form-urlencoded')
        authenticate
        Uchiwa.set_headers(discoverer, oauth_endpoint._attributes['access_token'], discoverer._links[:xframe])
        discoverer
      end

      def authenticate
        oauth_endpoint._post(URI.encode("grant_type=password&username=#{username}&password=#{password}"))
      end

      def register_application
        entry_point_url = ucwa_entrance.user.applications.to_s.sub(/\/ucwa.*/, '')
        @entry_point = Hyperclient::EntryPoint.new(entry_point_url)
        entry_point.connection.builder.insert_before entry_point.connection.builder.handlers.length - 1,
                                                     Faraday::Response::Logger, logger, bodies: true
        Uchiwa.set_headers(entry_point, oauth_endpoint._attributes['access_token'], ucwa_entrance._links[:xframe])
        response = ucwa_entrance.user.applications._post(application_id.to_json)
        Hyperclient::Resource.new(response._response.body, entry_point, response._response)
      end

      def application_id
        {
            :UserAgent  => 'UCWA Connector',
            :EndpointId => SecureRandom.uuid,
            :Culture    => 'en-US'
        }
      end

      def set_application
        @activity_timer = every(ENV['ACTIVITY_TIMEOUT'].to_i) do
          application.me.reportMyActivity._post('')
          logger.info 'reportMyActivity request sent'
        end

        @event_handler = EventHandler.new(entry_point)
        @event_channel = EventChannel.new(application.events._url,
                                          oauth_endpoint._attributes['access_token'],
                                          entry_point._url, ucwa_entrance._links[:xframe])
        @scheduler = Scheduler.new(event_handler, event_channel)
        @searcher = search_resource
      end

      def application_refresh
        application.itself._get
      end
    end

    include Application
    include Resource
  end

  def Uchiwa.set_headers(end_point, access_token, xframe_url, etag = '')
    end_point.headers.update('Content-Type' =>	'application/json')
    end_point.headers.update('Authorization' => "Bearer #{access_token}")
    end_point.headers.update('Referer' => "#{xframe_url}")
  end
end
