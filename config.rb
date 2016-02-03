require 'yaml'
require 'pry'
require 'configatron'

secrets = YAML.load_file('secrets.yaml')

# Loads secrets
configatron.configure_from_hash(secrets)
configatron.lock!
