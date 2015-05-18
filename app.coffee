require('dotenv').load()
CSON = require 'cson'
bodyParser = require('body-parser')
cors = require 'cors'
dateFormat = require 'dateformat'
express = require 'express'
extend = require 'extend'
github = require 'octonode'
morgan = require 'morgan'
redis = require 'redis'
session = require 'express-session'
Path = require 'path'

i18nUtils = require './lib/i18n-utils'

RedisStore = require('connect-redis') session

if uriString = process.env.REDISTOGO_URL || process.env.BOXEN_REDIS_URL
  uri = require('url').parse uriString
  redis = require('redis').createClient uri.port, uri.hostname
  redis.auth uri.auth?.split(':')?[1]
else
  redis = require('redis').createClient()

app = express()
app.use session {
  secret: process.env.SESSION_SECRET || '<insecure>'
  store: new RedisStore client: redis
  resave: yes
  saveUninitialized: yes
}
app.use bodyParser.json()
app.use bodyParser.urlencoded extended: yes
app.use cors
  credentials: yes
  allowedHeaders: ['Origin', 'X-Requested-With', 'Content-Type', 'Accept', 'Authorization']
  origin: (origin, callback) -> callback null, yes
app.use morgan 'combined'

currentToken = (req, res) ->
  return token if token = req.session.token
  res.status(401).json message: 'Not logged in'
  return

app.get '/', (req, res) ->
  if token = currentToken(req, res)
    res.json message: 'It works', token: token

app.get '/login', (req, res) ->
  {returnUrl} = req.query
  authUrl = github.auth.config(
    id: process.env.GITHUB_CLIENT_ID
    secret: process.env.GITHUB_CLIENT_SECRET
  ).login ['user', 'repo']
  state = authUrl.match(/&state=([0-9a-z]{32})/i)?[1]
  req.session.authReturnUrl = returnUrl
  req.session.authState = state
  if returnUrl
    res.redirect 302, authUrl
  else
    res.json { authUrl }

app.get '/oauth/callbacks', (req, res) ->
  {authReturnUrl, authState} = req.session
  {state, code} = req.query
  req.session.authReturnUrl = null
  req.session.authState = null
  if authState && state && authState isnt state
    res.status(403).json messages: ['Invalid state']
    return
  github.auth.login code, (err, token) ->
    if err
      console.error err
      res.status(400).json messages: [err.message]
      return
    req.session.token = token
    if authReturnUrl
      res.redirect 302, authReturnUrl
    else
      res.json messages: ['Success']

app.get '/i18n', (req, res) ->
  unless req.session.i18n
    res.status(404).json messages: ['No I18n']
    return
  i18n = extend yes, {}, req.session.i18n || {}
  res.json if key = req.query.key
    i18nUtils.find i18n, key.split '.'
  else
    i18n

app.post '/i18n', (req, res) ->
  {key, value} = req.body
  i18n = req.session.i18n ||= {}
  errors = []
  errors.push "parameter key is missing" if key == undefined
  errors.push "parameter value is missing" if value == undefined
  if errors.length
    res.status(400).json messages: errors
    return
  parentKey = key.split '.'
  key = parentKey.pop()
  obj = i18nUtils.find i18n, parentKey
  obj[key] = value
  res.json i18n

createTree = (repo, tree, pendingResources, callback) ->
  newTree = []
  encoding = 'utf-8'
  mode = '100644'
  type = 'blob'
  createNext = (cb) ->
    unless blob = pendingResources.create.pop()
      return cb()
    {data, path} = blob
    content = i18nUtils.createFile data
    repo.createBlob content, encoding, (e, b) ->
      return callback e, null if e?
      {sha} = b
      newTree.push { sha, path, type, mode }
      createNext cb

  updateNext = (cb) ->
    unless blob = pendingResources.update.pop()
      return cb()
    {data, path} = blob
    repo.blob blob.sha, (e, b) ->
      return callback e, null if e?
      {content} = b
      if b.encoding is 'base64'
        content = new Buffer(content, 'base64').toString('utf8')
      i18nUtils.updateFile content, data,
      (data, k, p, resolved) ->
        p = Path.join Path.dirname(path), "#{p}.coffee"
        for blob in tree
          if p is blob.path
            blob.data = data
            pendingResources.update.push blob
            do resolved
            break
      ,
      (content) ->
        repo.createBlob content, encoding, (e, b) ->
          return callback e, null if e?
          {sha} = b
          newTree.push { sha, path, type, mode }
          updateNext cb

  updateNext ->
    createNext ->
      for blob in newTree
        delete blob.data
        delete blob.size
        delete blob.url
      callback null, newTree

app.post '/i18n/submit', (req, res) ->
  {repo,path,baseBranch} = req.body
  path += '/' unless /\/$/.test path
  return unless token = currentToken req, res
  unless i18n = req.session.i18n
    res.status(404).json messages: ['No I18n']
    return
  client = github.client token
  repo = client.repo repo
  client.me().info (e, b) ->
    return res.status(400).json messages: [e.message] if e?
    me = b
    branchName = "i18n-#{me.login}-#{dateFormat new Date(), 'yyyymmddhhMMss'}"
    repo.ref "heads/#{baseBranch}", (e, b) ->
      return res.status(400).json messages: [e.message] if e?
      baseCommit = b.object.sha
      ref = "refs/heads/#{branchName}"
      repo.tree baseCommit, yes, (e, b) ->
        return res.status(400).json messages: [e.message] if e?
        baseTree = b.sha
        pendingResources = i18nUtils.getPendingResources b.tree, i18n, path
        createTree repo, b.tree, pendingResources, (e, tree) ->
          return res.status(400).json messages: ["createTree: #{e.message}"] if e?
          repo.createTree tree, baseTree, (e, b) ->
            return res.status(400).json messages: ["repo.createTree: #{e.message}"] if e?
            {sha} = b
            title = "Generated translations by #{me.login} via I18n Manager"
            repo.createCommit title, sha, [baseCommit], (e, b) ->
              return res.status(400).json messages: ["repo.createCommit: #{e.message}"] if e?
              {sha} = b
              repo.createRef ref, sha, (e, b) ->
                return res.status(400).json messages: ["createRef: #{e.message}"] if e?
                body = "https://github.com/kaizenplatform/i18n-manage-api"
                head = "#{repo.name.split('/')[0]}:#{branchName}"
                prOpts = { title, body, head, base: baseBranch }
                repo.createPr prOpts, (e, b, h) ->
                  return res.status(400).json messages: ["createPr: #{e.message}"] if e?

                  issue = client.issue req.body.repo, b.number
                  issue.update labels: ['i18n'], (e, b) ->
                    return res.status(400).json messages: ["update issue: #{e.message}"] if e?

                    req.session.i18n = null
                    res.json { url: b.html_url }

app.listen process.env.PORT || 3000

