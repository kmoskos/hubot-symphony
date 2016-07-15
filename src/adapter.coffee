#
#    Copyright 2016 Jon Freedman
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

{Adapter, TextMessage, User} = require 'hubot'
Symphony = require './symphony'

class SymphonyAdapter extends Adapter

  constructor: (robot) ->
    super
    @robot = robot
    throw new Error('HUBOT_SYMPHONY_HOST undefined') unless process.env.HUBOT_SYMPHONY_HOST
    throw new Error('HUBOT_SYMPHONY_PUBLIC_KEY undefined') unless process.env.HUBOT_SYMPHONY_PUBLIC_KEY
    throw new Error('HUBOT_SYMPHONY_PRIVATE_KEY undefined') unless process.env.HUBOT_SYMPHONY_PRIVATE_KEY

  send: (envelope, strings...) ->
    @robot.logger.debug "Send"
    for string in strings
      @symphony.sendMessage(envelope.room, string, 'TEXT')

  reply: (envelope, strings...) ->
    @robot.logger.debug "Reply"
    @send(envelope, strings)

  run: ->
    @robot.logger.info "Initialising..."
    @symphony = new Symphony(process.env.HUBOT_SYMPHONY_HOST, process.env.HUBOT_SYMPHONY_PRIVATE_KEY, process.env.HUBOT_SYMPHONY_PUBLIC_KEY)
    @symphony.whoAmI()
      .then (response) =>
        @symphony.getUser(response.userId)
        .then (response) =>
          @robot.logger.info "Connected as #{response.userAttributes?.displayName} [#{response.userSystemInfo?.status}]"
      .fail (err) =>
        @robot.emit 'error', new Error("Unable to resolve identity: #{err}")
    @symphony.createDatafeed()
      .then (response) =>
        @emit "connected"
        @_pollDatafeed(response.id)
      .fail (err) =>
        @robot.emit 'error', new Error("Unable to create datafeed: #{err}")

  _pollDatafeed: (datafeedId) =>
    @robot.logger.debug "Polling datafeed #{datafeedId}"
    while true
      @symphony.readDatafeed(datafeedId)
        .then (response) =>
          @robot.logger.debug "Received #{response.length} datafeed messages"
          @_receiveMessage msg for msg in response when msg.v2messageType = 'V2Message'
        .fail (err) =>
          @robot.emit 'error', new Error("Unable to read datafeed #{datafeedId}: #{err}")

  _receiveMessage: (message) =>
    user = @symphony.getUser(message.fromUserId)
    user.room = message.streamId
    message = new TextMessage(new User(message.fromUserId, name: user.displayName), message.id)
    @robot.receive message

exports.use = (robot) ->
  new SymphonyAdapter robot