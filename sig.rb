# i'm having many respects to lingr-irc.

require 'bundler'
Bundler.require

require 'socket'
require 'logger'

puts "DRIVERS START YOUR ENGINE!"
Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end
client = Slack::Web::Client.new
puts client.auth_test


module SlackIRCGateway
  PRIVMSG = "PRIVMSG"
  NOTICE = "NOTICE"
 
  class Server
    def initialize(port: 16668, logger: nil)
      @port = port
      @logger = logger
    end

    def start
      @server = TCPServer.open(@port)
      log { "started Slack IRC gateway at localhost:#{@port}" }
      loop do
        c = Client.new(socket: @server.accept, logger: @logger)
        Thread.new do
          c.process
        end
      end
    end
    
    def log(&block)
      @logger.info(&block) if @logger
    end
  end
end

require './client'

c = SlackIRCGateway::Server.new(logger: Logger.new(STDERR))
c.start
