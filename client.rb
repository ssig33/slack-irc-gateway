require 'cgi'

module SlackIRCGateway
  class Client
    def initialize(socket: nil, logger: nil)
      @socket = socket
      @logger = logger
    end
    
    def process
      while line = @socket.gets
        line.chomp!
        log { "received from IRC client: #{line}" }
        case line
        when /^PASS\s+/i
          @password = $~.post_match
        when /^NICK\s+/i
          @user = $~.post_match
        when /^USER\s+/i
          on_user($~.post_match)
        when /^PRIVMSG\s+/i, /^NOTICE\s+/i
          s = $~.post_match
          on_privmsg(*s.split(/\s+/, 2))
        when /^WHOIS\s+/i
          on_whois($~.post_match)
        when /^PING\s+/i
          on_ping($~.post_match)
        when /^QUIT/i
          on_quit
        end
      end
    rescue => e
      log_error { "error in IRC client read loop: #{e.inspect}" }
      terminate
    end
    
    private
    
    def on_user(param)
      params = param.split(' ', 4)
      realname = params[3]
      realname = $~.post_match if realname =~ /^:/
      
      log { "connecting: #{@user}" }

      reply(1, ":Welcome to Slack IRC Gateway!")
      reply(376, ":End of MOTD.")

      client = Slack::Web::Client.new
      
      @users = client.users_list.members 
      @you = @users.select{|x| 
        x.profile.email == realname
      }.first

      if @you
        client.channels_list.channels.each do |channel|
          info = client.channels_info(channel: channel.id).channel
          @channels ||= []
          @channels << info
          if info.members.include?(@you.id)
            send("#{my_prefix} JOIN ##{channel.name}")
            # show names list
            #names = room.members.map{|_,m| "#{m.owner ? '@' : ''}#{m.username}" }.join(' ')
            reply(366, "##{channel.name} :End of NAMES list.")
          end
        end
        Thread.start do
          wc = Slack::RealTime::Client.new
          wc.on :hello do 
            log { "Hello Slack!!"}
          end
          wc.on(:message) do |data|
            log{ data }
            channel = @channels.select{|x| x.id == data.channel}.first
            text = data.text
            text.scan(/<@.+?>/).each do |m|
              id = m.split("@").last.split(">").first
              user = @users.select{|x| x.id == id}.first
              username = user.profile.display_name
              username = user.profile.first_name if username == ''
              username = user.profile.real_name if username == ''
              text.sub!(m, "@#{username}")
            end
            if channel
              if data.username
                log{"@bot:#{data.username}##{channel.name}: #{data.text}"}
                send_text(data.username, "#{data.username}@slack.com", data.text, channel.name, PRIVMSG)
              else
                user = @users.select{|x| x.id == data.user}.first
                if user
                  log{ user }
                  username = user.profile.display_name
                  username = user.profile.first_name if username == ''
                  username = user.profile.real_name if username == ''
                  log{"@#{username}##{channel.name}: #{data.text}"}
                  send_text(username, user.profile.email, data.text, channel.name, PRIVMSG)
                end
              end
            end
          end
          wc.start!
        end
      end
    end
    
    def on_privmsg(chan, text)
      chan = chan[1..-1]
      text = $~.post_match if text =~ /^:/
      
      url = "https://slack.com/api/chat.postMessage?token=#{ENV['SLACK_API_TOKEN']}&channel=%23#{CGI.escape chan}&text=#{CGI.escape text}&username=#{@user}&link_names=1&pretty=1&icon_url=#{CGI.escape(@you.profile.image_192)}"
      RestClient.get(url)
    end
    
    def on_whois(param)
    end

    def on_ping(server)
      send("PONG #{server}")
    end
    
    def on_quit
      send(%Q[ERROR :Closing Link: #{@user}!#{@user}@slack.com ("Client quit")])
      terminate
    end
    
    def terminate
      @socket.close
      @worker.terminate
    rescue Exception
    end
    
    def send(line)
      @socket.puts(line)
    end
    
    def reply(num, line)
      s = sprintf(":slack %03d #{@user} #{line}", num)
      send(s)
    end
    
    def send_text(username, email, message, channel, cmd)
      lines = message.split(/\r?\n/)
      lines.each do |line|
        send(":#{username}!#{email} #{cmd} ##{channel} :#{line.chomp}")
      end
    end
    
    def my_prefix
      ":#{@user}!#{@user}@slack.com"
    end
    
    def user_prefix(user)
      ":#{user}!#{user}@slack.com"
    end
    
    def log(&block)
      @logger.info(&block) if @logger
    end
    
    def log_error(&block)
      @logger.error(&block) if @logger
    end
    
  end
end
