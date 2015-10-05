# coding: utf-8
require 'hyperclient'
require 'logger'
require 'json/ext'

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
          discoverer = Hyperclient.new('https://lyncdiscover.metio.net') do |client|
            client.connection do |conn|
              conn.response :logger, log, bodies: true
            end
          end
          discoverer.headers.update('Content-Type' =>	'application/json')

          begin
            headers = discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            headers = e1.response[:headers]
          end

          @oauth_url = headers['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]

          # begin
            # discoverer.xframe._post(@oauth_url)
          # rescue Faraday::Error::ClientError => e10 - get token - not needed in sandbox
          # end

          discoverer.headers.update('Authorization' => "#{access_token}")
          # url = discoverer.user.applications.to_s.sub(/\/ucwa.*/, '')
          # entry_point = Hyperclient::EntryPoint.new(url)
          # entry_point.headers.update('Authorization' => "#{access_token}")

          application = discoverer.user.applications._post(application_id.to_json)
          # if application._success?
            # Hyperclient::Resource.new(application, discoverer, application._response)
          # else
            # Hyperclient::Resource.new(nil, entry_point, _response)
          # end
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
      end
    end

    include Resource::Discover
  end
end
