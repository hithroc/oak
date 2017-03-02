module Oak.Web (runApp) where

import Web.Spock
import Web.Spock.Config
import Network.HTTP.Types.Status
import Data.Monoid
import Control.Monad
import Control.Monad.IO.Class
import Control.Concurrent.STM
import qualified Data.UUID as UUID
import Data.UUID.V4
import qualified Data.IntMap as IM
import Network.Wai.Handler.Warp
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Network.Wai.Middleware.Static

import Oak.Web.Types
import Oak.Web.Components
import Oak.Core.Booster

customError s = do
  setStatus s
  text $ T.pack (show $ statusCode s) 
      <> " - "
      <> (T.decodeUtf8 $ statusMessage s)

sessionHook :: ActionCtxT ctx (WebStateM conn UserSession st) ()
sessionHook = do
  setHeader "Cache-Control" "no-cache, no-store, must-revalidate"
  setHeader "Pragma" "no-cache"
  setHeader "Expires" "0"
  uuid <- getUserUUID <$> readSession
  when (UUID.null uuid) $ do
    nuuid <- liftIO $ nextRandom
    modifySession $ (\x -> x { getUserUUID = nuuid })

runApp :: CardDatabase -> IO ()
runApp db = do
  let settings = setPort 42421
               . setHost "127.0.0.1"
               $ defaultSettings
  trooms <- atomically $ newTVar (IM.empty)
  troomcnt <- atomically $ newTVar 0
  spockCfg <- defaultSpockCfg (UserSession UUID.nil) PCNoDatabase (GlobalState troomcnt trooms db)
  app <- spockAsApp (spock (spockCfg { spc_errorHandler = customError }) app)
  runSettings (settings) (app)


app :: SpockM () UserSession GlobalState ()
app = do
  middleware . staticPolicy $ only
    [("app.js", "frontend/dist/app.js")
    ,("room.css", "static/room.css")
    ]
  prehook sessionHook $ do
    get root $ file "text/html" "static/index.html"
    roomComponent
    get ("debug" <//> "exception") $ error "[](/rdwut)"
    get ("debug" <//> "session") $ do
      sess <- readSession
      text . T.pack . show $ sess
    get ("debug" <//> "status" <//> var) $ \code -> do
      setStatus $ mkStatus code "Unknown Code"
      text "Error"
    get ("debug" <//> "route" <//> wildcard) $ \wc -> do
      req <- request
      text $ T.pack $ show req
