{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Choreography
import Choreography.Choreo
import Choreography.Location
import Choreography.Network
import Choreography.Network.Tcp
import Control.Monad.Freer
import Data.Proxy
import Data.Time
import GHC.TypeLits (KnownSymbol)
import System.Environment
import Language.Haskell.TH
import System.Random
import Web.Scotty
import Control.Concurrent
import Control.Concurrent.Chan (Chan)
import Control.Concurrent.Chan qualified as Chan
import Network.HTTP.Client qualified as H
import Data.ByteString qualified as BS
import Secrets qualified as S
import Web.Browser

-- Impl OAuth2

$S.loadSecrets

$(compileFor 0 [ ("app", ("localhost", 3000))
               , ("server", ("localhost", 4000))
               ])

startCallbackServer :: Chan String ->  IO ThreadId
startCallbackServer c = forkIO $ scotty 8080 $
    get "/oauth" $ do
      auth <- param "code"
      liftIO . putStrLn $ "APP: (Callback) got code: " <> auth
      html "auth granted, you can close this"
      liftIO $ Chan.writeChan c auth

startAuthRequest :: Choreo IO (Chan String @ "app", ThreadId @ "app")
startAuthRequest = do
  authChan <- app `locally` \unwrap -> newChan :: IO (Chan String)
  callbackServer <- app `locally` \unwrap -> do
    startCallbackServer (unwrap authChan)
  pure (authChan, callbackServer)

startUserInput :: Choreo IO (() @ "app")
startUserInput = app `locally` \unwrap -> do
  openBrowser $ concat 
    [ "https://mastodon.social/oauth/authorize"
    , "?response_type=code"
    , "&client_id=" <> clientId
    , "&redirect_uri=http://localhost:8080/oauth"
    ] 
  pure ()


finishAuthRequest :: (Chan String @ "app", ThreadId @ "app") -> Choreo IO (String  @ "app")
finishAuthRequest (authChan, callbackServer) = do
  -- get grant code from callback server  
  app `locally` \unwrap -> do
    ans <- Chan.readChan (unwrap authChan)
    putStrLn "APP: Killing callback server"
    let cs = unwrap callbackServer
    forkIO $ do
      threadDelay 10000
      killThread cs
    pure ans

sendGrantToServer :: String @ "app" -> Choreo IO (Int @ "server")
sendGrantToServer grant = do
  grant <- (app, grant) ~> server
  server `locally` \unwrap -> do
    putStrLn $ "SERVER: got grant token: " <> show (unwrap grant)
    randomRIO (0,1000000)
  


-- {-# SPECIALISE forall . sort primary worker1 worker2 #-}
-- {-# SPECIALISE forall . sort primary worker2 worker1 #-}
-- {-# SPECIALISE forall . sort worker2 primary worker1 #-}
-- {-# SPECIALISE forall . sort worker1 primary worker2 #-}
-- {-# SPECIALISE forall . sort worker1 worker2 primary #-}
mainChoreo :: Choreo IO ()
mainChoreo = do
  -- -1. tcp testing thing :)
  val <- app `locally` \unwrap -> do
    num <- randomRIO (0,100 :: Int)
    pure $ "Hello from TCP: " <> show num
  app `locally` \unwrap -> do
    let val' = unwrap val
    print val'
  valServer <- (app, val) ~> server
  server `locally` \unwrap -> do
    let val = unwrap valServer
    print val


  -- -- 0. create callback server in app
  -- callback <- startAuthRequest
  -- 
  -- -- 1. send auth request to user, pretend this is a webbrowser :)
  -- -- 2. Forward the user to the callback server
  -- startUserInput
-- 
  -- -- 3. get grant code from callback server  
  -- grant <- finishAuthRequest callback
  -- 
  -- -- 4. send authgrant to server
  -- accessTokServ <- sendGrantToServer grant  
  -- 
  -- -- 5. Send accessTok to app
  -- accessTok <- (server, accessTokServ) ~> app
  -- 
  -- -- app loop (n -> n+1)
  -- app `locally` \unwrap -> putStrLn $ 
  --   "App: got access token: " <> show (unwrap accessTok)
  

  return ()

-- {-# INLINE liftIO #-}
-- liftIO :: KnownSymbol b => Proxy b -> IO a -> Choreo IO (a @ b)
-- liftIO loc x = locally loc $ \unwrap -> x 

main :: IO ()
main = run' mainChoreo