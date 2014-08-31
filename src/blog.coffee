{Promise} = require 'q'
fs = require 'fs'
mime = require 'mime'
oauth = require 'oauth'
request = require 'request'
wsse = require 'wsse'
xml2js = require 'xml2js'

# Hatena::Blog AtomPub API wrapper
#
# - GET    CollectionURI       (/<username>/<blog_id>/atom/entry)
#   => Blog#index
# - POST   CollectionURI       (/<username>/<blog_id>/atom/entry)
#   => Blog#create
# - GET    MemberURI           (/<username>/<blog_id>/atom/entry/<entry_id>)
#   => Blog#show
# - PUT    MemberURI           (/<username>/<blog_id>/atom/entry/<entry_id>)
#   => Blog#update
# - DELETE MemberURI           (/<username>/<blog_id>/atom/entry/<entry_id>)
#   => Blog#destroy
# - GET    ServiceDocumentURI  (/<username>/<blog_id>/atom)
#   => None
# - GET    CategoryDocumentURI (/<username>/<blog_id>/atom/category)
#   => None
class Blog

  # constructor
  # params:
  #   options: (required)
  #   - type     : authentication type. default `'wsse'`
  #   - username : user name. (required)
  #   - blogId   : blog id. (required)
  #   (type 'wsse')
  #   - apikey   : wsse authentication apikey. (required)
  #   (type 'oauth')
  #   - consumerKey       : oauth consumer key. (required)
  #   - consumerSecret    : oauth consumer secret. (required)
  #   - accessToken       : oauth access token. (required)
  #   - accessTokenSecret : oauth access token secret. (required)
  constructor: ({
    type,
    username,
    blogId,
    apikey,
    consumerKey
    consumerSecret,
    accessToken,
    accessTokenSecret
  }) ->
    @_type = type ? 'wsse'
    @_username = username
    @_blogId = blogId
    @_apikey = apikey
    @_consumerKey = consumerKey
    @_consumerSecret = consumerSecret
    @_accessToken = accessToken
    @_accessTokenSecret = accessTokenSecret
    @_baseUrl = 'https://blog.hatena.ne.jp'

  # POST CollectionURI (/<username>/<blog_id>/atom/entry)
  # params:
  #   options: (required)
  #   - title      : 'title'. entry title.default `''`.
  #   - content    : 'content'. entry content. default `''`.
  #   - updated    : 'updated'. default `undefined`
  #   - categories : 'category' '@term'. default `undefined`.
  #   - draft      : 'app:control' > 'app:draft'. default `undefined`.
  #   callback:
  #   - err: error
  #   - res: response
  # returns:
  #   Promise
  create: ({ title, content, updated, categories, draft }, callback) ->
    title = title ? ''
    content = content ? ''
    method = 'post'
    path = "/#{@_username}/#{@_blogId}/atom/entry"
    body = entry:
      $:
        xmlns: 'http://www.w3.org/2005/Atom'
        'xmlns:app': 'http://www.w3.org/2007/app'
      title:
        _: title
      content:
        $:
          type: 'text/plain'
        _: content
    body.entry.updated = _: updated if updated?
    body.entry.category = categories.map((c) -> $: { term: c }) if categories?
    body.entry['app:control'] = { 'app:draft': { _: 'yes' } } if draft ? false
    statusCode = 201
    @_request { method, path, body, statusCode }, callback

  # TODO:
  # # PUT EditURI (/atom/edit/XXXXXXXXXXXXXX)
  # # params:
  # #   options: (required)
  # #   - id    : image id. (required)
  # #   - title : 'title'. image title. (required)
  # #   callback:
  # #   - err: error
  # #   - res: feed
  # # returns:
  # #   Promise
  # update: ({ id, title }, callback) ->
  #   return @_reject('options.id is required', callback) unless id?
  #   return @_reject('options.title is required', callback) unless title?
  #   method = 'put'
  #   path = '/atom/edit/' + id
  #   body =
  #     entry:
  #       $:
  #         xmlns: 'http://purl.org/atom/ns#'
  #       title:
  #         _: title
  #   statusCode = 200
  #   @_request { method, path, body, statusCode }, callback
  #
  # # DELETE EditURI (/atom/edit/XXXXXXXXXXXXXX)
  # # params:
  # #   options: (required)
  # #   - id: image id. (required)
  # #   callback:
  # #   - err: error
  # #   - res: response
  # # returns:
  # #   Promise
  # destroy: ({ id }, callback) ->
  #   return @_reject('options.id is required', callback) unless id?
  #   method = 'delete'
  #   path = '/atom/edit/' + id
  #   statusCode = 200
  #   @_request { method, path, statusCode }, callback
  #
  # # GET EditURI (/atom/edit/XXXXXXXXXXXXXX)
  # # params:
  # #   options: (required)
  # #   - id: image id. (required)
  # #   callback:
  # #   - err: error
  # #   - res: response
  # # returns:
  # #   Promise
  # show: ({ id }, callback) ->
  #   return @_reject('options.id is required', callback) unless id?
  #   method = 'get'
  #   path = '/atom/edit/' + id
  #   statusCode = 200
  #   @_request { method, path, statusCode }, callback
  #
  # # GET FeedURI (/atom/feed)
  # # params:
  # #   options:
  # #   callback:
  # #   - err: error
  # #   - res: response
  # # returns:
  # #   Promise
  # index: (options, callback) ->
  #   callback = options unless callback?
  #   method = 'get'
  #   path = '/atom/feed'
  #   statusCode = 200
  #   @_request { method, path, statusCode }, callback

  _reject: (message, callback) ->
    try
      e = new Error(message)
      callback(e) if callback?
      Promise.reject(e)
    catch
      Promise.reject(e)

  _request: ({ method, path, body, statusCode }, callback) ->
    callback = callback ? (->)
    params = {}
    params.method = method
    params.url = @_baseUrl + path
    if @_type is 'oauth'
      params.oauth =
        consumer_key: @_consumerKey
        consumer_secret: @_consumerSecret
        token: @_accessToken
        token_secret: @_accessTokenSecret
    else # @_type is 'wsse'
      token = wsse().getUsernameToken @_username, @_apikey, nonceBase64: true
      params.headers =
        'Authorization': 'WSSE profile="UsernameToken"'
        'X-WSSE': 'UsernameToken ' + token
    promise = if body? then @_toXml(body) else Promise.resolve(null)
    promise
      .then (body) =>
        params.body = body if body?
        @_requestPromise params
      .then (res) =>
        if res.statusCode isnt statusCode
          throw new Error("HTTP status code is #{res.statusCode}")
        @_toJson res.body
      .then (json) ->
        callback(null, json)
        json
      .then null, (err) ->
        callback(err)
        err

  _requestPromise: (params) ->
    new Promise (resolve, reject) =>
      @_rawRequest params, (err, res) ->
        if err?
          reject err
        else
          resolve res

  _toJson: (xml) ->
    new Promise (resolve, reject) ->
      parser = new xml2js.Parser explicitArray: false, explicitCharkey: true
      parser.parseString xml, (err, result) ->
        if err?
          reject err
        else
          resolve result

  _toXml: (json) ->
    builder = new xml2js.Builder()
    try
      xml = builder.buildObject json
      Promise.resolve xml
    catch e
      Promise.reject e

  _rawRequest: request

  _mime: mime

module.exports = Blog
