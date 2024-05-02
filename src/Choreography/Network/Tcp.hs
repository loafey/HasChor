{-# LANGUAGE DataKinds  #-}
{-# LANGUAGE GADTs      #-}
{-# LANGUAGE LambdaCase #-}


module Choreography.Network.Tcp where

-- | A TCP based backend serving as an alternative to the existing HTTP based one.
--   Most of this code is a port.

import Choreography.Location
import Choreography.Network hiding (run)
import Data.ByteString (fromStrict, null, ByteString, length, pack, unpack)
import Data.ByteString.Char8 (unpack)
import Data.String (fromString)
import Data.Proxy (Proxy(..))
import Data.HashMap.Strict (HashMap, (!))
import Data.HashMap.Strict qualified as HashMap
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import Control.Concurrent
import Control.Concurrent.Chan
import Control.Monad
import Control.Monad.Freer
import Control.Monad.IO.Class
import Network.Socket
import Debug.Trace
import Network.Socket.ByteString (recv, sendAll)
import Network.Run.TCP
import qualified Control.Exception as E

-- * Http configuration

-- | The HTTP backend configuration specifies how locations are mapped to
-- network hosts and ports.
data TcpConfig = TcpConfig
  { locToUrl :: HashMap LocTm Addr
  , urlToLoc :: HashMap String LocTm -- disgusting hack
  } deriving Show

type Host = String
type Port = Int
type Addr = (Host, Port)


-- | Create a TCP backend configuration from a association list that maps
-- locations to network hosts and ports.
mkTcpConfig :: [(LocTm, (Host, Port))] -> TcpConfig
mkTcpConfig l = TcpConfig 
    (HashMap.fromList $ l)
    (HashMap.fromList $ map (\(a,b) -> (show b,a)) $ l)
  where
    addrFixer "localhost" = tupleToHostAddress (7, 0, 0, 127)
    addrFixer addr = do
      let [a,b,c,d] = read <$> split "" addr '.'
      tupleToHostAddress (d, c, b, a)
    split acc (a:as) s | a == s    = acc : split [] as s
                       | otherwise = split (acc ++ [a]) as s

locs :: TcpConfig -> [LocTm]
locs = HashMap.keys . locToUrl

-- * Receiving channels

type RecvChans = HashMap LocTm (Chan String)

mkRecvChans :: TcpConfig -> IO RecvChans
mkRecvChans cfg = foldM f HashMap.empty (locs cfg)
  where
    f :: HashMap LocTm (Chan String) -> LocTm
      -> IO (HashMap LocTm (Chan String))
    f hm l = do
      c <- newChan
      return $ HashMap.insert l c hm


-- * HTTP backend

runNetworkTcp :: MonadIO m => TcpConfig -> LocTm -> Network m a -> m a
runNetworkTcp cfg self prog = do
  mgr <- liftIO $ newManager defaultManagerSettings
  chans <- liftIO $ mkRecvChans cfg
  recvT <- liftIO $ forkIO (recvClient cfg chans)
  result <- runNetworkMain mgr chans prog
  liftIO $ threadDelay 1000000 -- wait until all outstanding requests to be completed
  liftIO $ killThread recvT
  return result
  where
    runNetworkMain :: MonadIO m => Manager -> RecvChans -> Network m a -> m a
    runNetworkMain mgr chans = interpFreer handler
      where
        handler :: MonadIO m => NetworkSig m a -> m a
        handler (Run m)    = m
        handler (Send a l) = liftIO $ do
          res <- sendClient (fromString $ show a) (locToUrl cfg ! l)
          case res of
            Left err -> putStrLn $ "Error : " ++ err
            Right _  -> return ()
        handler (Recv l)   = liftIO $ read <$> readChan (chans ! l)
        handler (BCast a)  = mapM_ handler $ fmap (Send a) (locs cfg)

    sendClient :: ByteString -> Addr -> IO (Either String ())
    sendClient msg (host, port) = do
      runTCPClient host (show port) $ \s -> do
        sendAll s $ Data.ByteString.pack [fromIntegral $ Data.ByteString.length msg]
        sendAll s msg
      pure . pure $ ()

    recvClient :: TcpConfig -> RecvChans -> IO ()
    recvClient cfg chans = runTCPServer (Just "localhost") (show . snd $ locToUrl cfg ! self) serve
      where 
        serve s = do
          putStrLn "waiting for message"
          len <- Network.Socket.ByteString.recv s 1
          let l = fromIntegral . head . Data.ByteString.unpack $ len
          msg <- Network.Socket.ByteString.recv s l
          unless (Data.ByteString.null msg) $ do
            addr <- getSocketName s
            liftIO $ writeChan 
              (chans ! ((urlToLoc cfg) ! (show addr))) 
              (Data.ByteString.Char8.unpack msg)



instance Backend TcpConfig where
  runNetwork = runNetworkTcp