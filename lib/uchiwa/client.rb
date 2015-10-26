# coding: utf-8
require 'hyperclient'
require 'json/ext'
require 'celluloid/current'
require '../lib/scheduler'
require '../lib/event_channel'
require '../lib/event_handler'


module Uchiwa
  class Client
    attr_accessor :access_token, :name, :domain
    attr_reader :entry_point, :my_groups

    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Internals::Logger

    ACTIVITY_TIMEOUT = 60

    SigningOptions = { random_property_name: 'please pass this in a PUT request',
                        signInAs: 'Online',
                        supportedMessageFormats: [ 'Plain', 'Html'],
                        supportedModalities: ['PhoneAudio', 'Messaging'],
                        rel: 'communication'}

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
      @logger.info("\n\n@application._links = #{@application._links.inspect}")
      set_application_resources
      @scheduler = Scheduler.new do |s|
        s.url = @event_channel_url
        s.access_token = @access_token
        s.entry_point = @entry_point_url
        s.name = @name
      end
    end

    module Resource
      module Discover
        def auto_discover(domain)
          discoverer = Hyperclient.new("http://lyncdiscover.#{domain}")
          discoverer.connection.builder.insert_before discoverer.connection.builder.handlers.length - 1, Faraday::Response::Logger, @logger, bodies: true
          discoverer.headers.update('Content-Type' => 'application/json')

          begin
            discoverer.user._get.headers
          rescue Faraday::Error::ClientError => e1
            @oauth_url = e1.response[:headers]['www-authenticate'].to_s.match(/href="([^"]*)/)[1]
          end

          @xframe_url = discoverer._links[:xframe]

          # Here would be a GET request to @oauth_url for access_token

          Uchiwa.set_headers discoverer, @access_token
          discoverer
        end

        def register_application(url)
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
                                                     {'href' => "#{search_uri}/{?query,limit}",
                                                       'templated' => true } } },
                                                 @entry_point)

          @event_channel_url = @application.events._url

          @activity_timer = every(ACTIVITY_TIMEOUT) do
            @application.me.reportMyActivity._post('')
            @logger.info 'reportMyActivity request sent'
          end
          make_available SigningOptions
        end

        def set_application_id
          {
            :UserAgent  => 'UCWA Samples',
            :EndpointId => SecureRandom.uuid,
            :Culture    => 'en-US',
          }
        end

        def make_available(body)
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

        def subscribe_to_group_presence(group_name)
          uris = []
          @my_groups._embedded.group.each do |g|
            if g[:name] == group_name
              group_contacts = g.groupContacts._get._response.body.to_json
              group_contacts = JSON.parse(group_contacts, object_class: OpenStruct)
              group_contacts._embedded.contact.each_index do |i|
                uris[i] = group_contacts._embedded.contact[i].uri
                i += 1
              end
              g.subscribeToGroupPresence._post({:duration => ENV['CONTACT_SUBSCRIPTION_DURATION'],
                                                                 :uris => uris}.to_json)
            end
          end

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
end
