lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'database_cleaner'
require 'activerecord-typedstore'

Dir[File.expand_path(File.join(File.dirname(__FILE__), 'support', '**', '*.rb'))].each { |f| require f }

Time.zone = 'UTC'

RSpec.configure do |config|
  config.order = 'random'
end
