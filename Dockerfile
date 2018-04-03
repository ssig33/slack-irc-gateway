FROM ruby:2.5.1
RUN mkdir /irc
WORKDIR /irc
COPY ./ ./
RUN bundle
EXPOSE 16668
CMD ruby sig.rb
