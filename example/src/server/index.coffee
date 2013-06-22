express = require('express')
coffeeify = require('coffeeify')
derby = require('derby')
racerBrowserChannel = require('racer-browserchannel')
LiveDbMongo = require('livedb-mongo').LiveDbMongo
MongoStore = require('connect-mongo')(express)
app = require('../auth')
serverError = require('./serverError')
mongoskin = require('mongoskin')
publicDir = require('path').join __dirname + '/../../public'
conf = require('nconf')

expressApp = module.exports = express()

# Get Redis configuration
if conf.get('REDIS_HOST')
  redis = require("redis").createClient conf.get('REDIS_PORT'), conf.get('REDIS_HOST')
  redis.auth conf.get('REDIS_PASSWORD')
else
  redis = require("redis").createClient()
redis.select conf.get('REDIS_DB')

# Get Mongo configuration
mongoUrl = conf.get('MONGO_URL')
mongo = mongoskin.db "#{mongoUrl}?auto_reconnect", {safe: true}

# The store creates models and syncs data
store = derby.createStore
  db: new LiveDbMongo(mongo)
  redis: redis

store.on 'bundle', (browserify) ->
  browserify.transform coffeeify

###
(1)
Setup a hash of strategies you'll use - strategy objects and their configurations
Note, API keys should be stored as environment variables (eg, process.env.FACEBOOK_KEY, process.env.FACEBOOK_SECRET)
rather than a configuration file. We're storing it in config.json for demo purposes.
###
auth = require("../../../index.js") # change to `require('derby-auth')` in your project
strategies =
  facebook:
    strategy: require("passport-facebook").Strategy
    conf:
      clientID: conf.get('fb:appId')
      clientSecret: conf.get('fb:appSecret')

  linkedin:
    strategy: require("passport-linkedin").Strategy
    conf:
      consumerKey: conf.get('linkedin:apiKey')
      consumerSecret: conf.get('linkedin:apiSecret')

  github:
    strategy: require("passport-github").Strategy
    conf:
      clientID: conf.get('github:appId')
      clientSecret: conf.get('github:appSecret')
      callbackURL: "http://127.0.0.1:3000/auth/github/callback"

  twitter:
    strategy: require("passport-twitter").Strategy
    conf:
      consumerKey: conf.get('twit:consumerKey')
      consumerSecret: conf.get('twit:consumerSecret')

      # You can optionally pass in per-strategy configuration options (consult Passport documentation)
      callbackURL: "http://127.0.0.1:3000/auth/twitter/callback"


# optional parameters passed into derby-auth.init, domain is required due to some Passport technicalities,
# allowPurl lets people access non-authenticated accounts at /:uuid, and schema sets up default user
# account schema structures
options = domain: "http://localhost:3000"

auth.store.init(store)
auth.store.basicUserAccess(store)

expressApp
    .use(express.favicon())
    .use(express.compress())
    .use(app.scripts(store))
    .use(express['static'](publicDir))
    .use(express.cookieParser())
    .use(express.session({
        secret: conf.get('SESSION_SECRET') || 'YOUR SECRET HERE'
        store: new MongoStore({
            url: mongoUrl
            safe: true
        })
    }))
    .use(express.bodyParser())
    .use(express.methodOverride())
    .use(racerBrowserChannel(store))
    .use(store.modelMiddleware())

    # (2)
    # derbyAuth.middleware is inserted after modelMiddleware and before the app router to pass server accessible data to a model
    # Pass in {store} (sets up accessControl & queries), {strategies} (see above), and options
    .use(auth.middleware(strategies, options))

    .use(app.router())
    .use(expressApp.router)
    .use(serverError())

expressApp.all "*", (req, res, next) -> next("404: #{req.url}")