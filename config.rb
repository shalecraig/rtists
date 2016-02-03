require 'yaml'
require 'pry'

secrets = YAML.load_file('secrets.yaml')

# Loads secrets
configatron.configure_from_hash(secrets)
