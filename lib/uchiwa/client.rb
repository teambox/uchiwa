# coding: utf-8
require 'hyperclient'

module Uchiwa
  class Client

    attr_accessor :client

    def initialize(config = {})
      @config = config
    end


    module Resource
      module Discover
        def discover
          discoverer = Hyperclient.new('https://lyncdiscover.gotuc.net')   # FIXME
          headers = discoverer.user._get.headers
          @oauth_url = headers['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          discoverer.headers.update('Authorization' => "Bearer #{access_token}")

          url = discoverer.user.applications.to_s.sub(/\/ucwa.*/, '')
          entry_point = Hyperclient::EntryPoint.new(url)
          entry_point.headers.update('Authorization' => "Bearer #{access_token}")
          response = discoverer.user.applications._post(application)

          if response.success?
            Hyperclient::Resource.new(response.body, entry_point, response)
          else
            Hyperclient::Resource.new(nil, entry_point, response)
          end
        end

        def application
          {
            :UserAgent  => "UCWA Samples",
            :EndpointId => "a917c6f4-976c-4cf3-847d-cdfffa28ccdf",  # TODO: SecureRandom.uuid
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
