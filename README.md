# Uchiwa

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'uchiwa'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install uchiwa

## Usage

### Setup and get ephemeral access token

```ruby
client = Uchiwa::Client.new(:username => 'USERNAME', :password => 'PASSWORD')
client.access_token   # => nil
client.entrypoint     # => nil
client.discover!      # AutoDiscoverying to get access token and entrypoint to the API using user credentials.
client.access_token   # => "cwt=AAEB...buHc"
client.entrypoint     # => "https://lyncweb.contoso.com/ucwa/oauth/v1/applications"
```

or setup with access token

```ruby
client = Uchiwa::Client.new(:access_token => "cwt=AAEB...buHc")
client.access_token   # => "cwt=AAEB...buHc"
client.entrypoint     # => nil
client.discover!
client.access_token   # => "cwt=AAEB...buHc"
client.entrypoint     # => "https://lyncweb.contoso.com/ucwa/oauth/v1/applications"
```

### Access anywhere


## Contributing

1. Fork it ( https://github.com/meganemura/uchiwa/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
