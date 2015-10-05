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
          @discoverer = Hyperclient.new('https://lyncdiscover.metio.net')
          @discoverer.connection.response :logger, @log, bodies: true
          @discoverer.headers.update('Content-Type' =>	'application/json')
          @discoverer.headers.update('X-Ms-Origin' => 'http://localhost')

          begin
            headers = @discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            headers = e1.response[:headers]
          end

          @oauth_url = headers['www-authenticate'].to_s.match(/href=\"([^\"]*)/)[1]
          @xframe_url = @discoverer._links[:xframe]
          @discoverer.headers.update('Authorization' => "#{access_token}")
          @discoverer.headers.update('Referer' => "#{@xframe_url}")
          url = @discoverer.user.applications.to_s.sub(/\/ucwa.*/, '')

          entry_point = Hyperclient::EntryPoint.new(url)
          entry_point.connection.response :logger, @log, bodies: true
          entry_point.headers.update('Content-Type' =>	'application/json')
          entry_point.headers.update('Authorization' => "#{access_token}")

          response = @discoverer.user.applications._post(application_id.to_json)
          if response._success?
            body = response._response.body.dup
            @application = Hyperclient::Resource.new(body, entry_point, response._response)
          else
            @application = Hyperclient::Resource.new(nil, entry_point, response._response)
          end
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

        # TODO: This will work only via conditional request PUT (with the If-Match: "{ETag value}"
        def make_available body
          @application.me.makeMeAvailable._post(body.to_json)
        end

        def get_contact_list
          # @application._embedded._get.people.myContacts
          @contacts = @application.people.myContacts
        end

        def search(query,
                   limit = 100)
          @found_contacts = @application.people._get.search(query, limit)
        end
      end
    end

    include Resource::Discover
  end
end
