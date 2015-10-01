# coding: utf-8
require 'hyperclient'
require 'logger'

module Uchiwa
  class Client

    attr_accessor :client

    def initialize(config = {})
      @config = config
    end


    module Resource
      module Discover
        def discover
          log = Logger.new(STDOUT)
          log.level = Logger::DEBUG
          discoverer = Hyperclient.new('http://lyncdiscover.metio.net') do |client|
            client.connection do |conn|
              conn.response :logger, log, bodies: true
            end
          end
          begin
            headers = discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            discoverer.headers.update('www-authenticate' => e1.response[:headers]['www-authenticate'])
            headers = e1.response[:headers]
          end

          # @oauth_url = e1.response[:headers]['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          @oauth_url = headers['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          discoverer.headers.update('Authorization' => "Bearer #{access_token}")

          begin
            url = discoverer.user.applications.to_s.sub(/\/ucwa.*/, '')
          rescue Faraday::Error::ClientError => e1
          end
          entry_point = Hyperclient::EntryPoint.new(url)
          entry_point.headers.update('Authorization' => "Bearer #{access_token}")
          begin
            response = discoverer.user.applications._post(application)
          rescue Faraday::Error::ClientError => e2
          end
          if e2.response[:status] == 200
            app_resource = Hyperclient::Resource.new(e3.response[:body], entry_point, e2.response)
          else
            app_resource = Hyperclient::Resource.new(nil, entry_point, e2.response)
          end
        end

        def application
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
      end
    end

    include Resource::Discover
  end
end
