# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'uchiwa/version'

Gem::Specification.new do |spec|
  spec.name          = 'uchiwa'
  spec.version       = Uchiwa::VERSION
  spec.authors       = ['meganemura']
  spec.email         = ['mura2megane@gmail.com']

  spec.required_rubygems_version = '>= 2.0'

  spec.summary       = 'Ruby Wrapper for UCWA 1.0 (Unified Communications Web API)'
  spec.description   = spec.description
  spec.homepage      = 'https://github.com/meganemura/uchiwa'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'hyperclient'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rubocop'
end
