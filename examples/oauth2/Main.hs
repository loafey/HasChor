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
import Choreography.Network.Http
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

-- Impl OAuth2

-- * ROBERT: Does not work, as sort and merge are both location polymorphic and recursive

$(compileFor 0 [ ("app", ("localhost", 3000))
               , ("server", ("localhost", 4000))
               ])

startCallbackServer :: Chan String ->  IO ThreadId
startCallbackServer c = forkIO $ scotty 8000 $
    post "/oauth" $ do
      auth <- param "auth"
      liftIO . putStrLn $ "APP: (Callback) got authcode code: " <> auth
      liftIO $ Chan.writeChan c auth
      html "auth granted"

-- {-# SPECIALISE forall . sort primary worker1 worker2 #-}
-- {-# SPECIALISE forall . sort primary worker2 worker1 #-}
-- {-# SPECIALISE forall . sort worker2 primary worker1 #-}
-- {-# SPECIALISE forall . sort worker1 primary worker2 #-}
-- {-# SPECIALISE forall . sort worker1 worker2 primary #-}
mainChoreo :: Choreo IO ()
mainChoreo = do
  -- create callback server in app
  authChan <- app `locally` \unwrap -> newChan :: IO (Chan String)
  callbackServer <- app `locally` \unwrap -> do
    startCallbackServer (unwrap authChan)

  -- send auth request to user, pretend this is a webbrowser :)
  app `locally` \unwrap -> do 
    -- TODO replace this with a webinterface
    putStrLn "<input type=\"text\" placeholder=\"log in please :)\">"
    ans <- BS.getLine

    httpman <- H.newManager H.defaultManagerSettings
    let req = H.setQueryString [("auth", Just ans)] "http://localhost:8000/oauth"
    let req' = req{ H.method = "POST" }
    H.httpLbs req' httpman

  -- get grant code from callback server  
  grant <- app `locally` \unwrap -> do
    ans <- Chan.readChan (unwrap authChan)
    putStrLn "APP: Killing callback server"
    let cs = unwrap callbackServer
    killThread cs
    pure ans
  
  
  -- send authgrant to server
  grant <- (app, grant) ~> server
  accessTok <- server `locally` \unwrap -> do
    putStrLn $ "Server: got grant token: " <> show (unwrap grant)
    randomRIO $ (0,1000000 :: Int)
  
  -- Send accessTok to app
  accessTok <- (server, accessTok) ~> app
  app `locally` \unwrap -> do
    putStrLn $ "App: got access token: " <> show (unwrap accessTok)
  

  return ()

-- {-# INLINE liftIO #-}
-- liftIO :: KnownSymbol b => Proxy b -> IO a -> Choreo IO (a @ b)
-- liftIO loc x = locally loc $ \unwrap -> x 

main :: IO ()
main = run' mainChoreo