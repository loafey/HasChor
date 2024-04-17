{-# LANGUAGE DataKinds  #-}
{-# LANGUAGE GADTs      #-}
{-# LANGUAGE LambdaCase #-}


module Choreography.Network.Tcp where

-- | A TCP based backend serving as an alternative to the existing HTTP based one.
--   Most of this code is a port.

import Choreography.Location
import Choreography.Network hiding (run)
import Data.ByteString (fromStrict, null, ByteString)
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
import qualified Control.Exception as E

-- * Http configuration

-- | The HTTP backend configuration specifies how locations are mapped to
-- network hosts and ports.
data TcpConfig = TcpConfig
  { locToUrl :: HashMap LocTm Addr
  , urlToLoc :: HashMap String LocTm -- disgusting hack
  }

type Host = String
type Port = Int
type Addr = SockAddr


-- | Create a TCP backend configuration from a association list that maps
-- locations to network hosts and ports.
mkTcpConfig :: [(LocTm, (Host, Port))] -> TcpConfig
mkTcpConfig l = TcpConfig 
    (HashMap.fromList $ fmap (fmap addrToSock) l)
    (HashMap.fromList $ map (\(a,b) -> (show b,a)) $ fmap (fmap addrToSock) l)
  where
    addrToSock = \(h, p) -> SockAddrInet (fromIntegral p) (addrFixer h)
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
    sendClient msg addr = do
      runTCPClient addr $ \s -> do
        sendAll s msg
        pure . pure $ ()
      where
        runTCPClient :: SockAddr -> (Socket -> IO a) -> IO a
        runTCPClient addr client = withSocketsDo $ do
            addr <- traceShowId <$> resolve
            E.bracket (open addr) close client
          where
            resolve = do
              let hints = defaultHints { addrSocketType = Stream }
              addrInfo hints addr
            open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
              connect sock $ addrAddress addr
              return sock

    recvClient :: TcpConfig -> RecvChans -> IO ()
    recvClient cfg chans = run
      where 
        serve s = do
          msg <- Network.Socket.ByteString.recv s 1024
          unless (Data.ByteString.null msg) $ do
            putStrLn "Handling message..."
            addr <- getSocketName s
            putStrLn $ "Addr: " <> show addr
            liftIO $ writeChan (chans ! ((urlToLoc cfg) ! (show addr))) (unpack msg)
            serve s

        addr = locToUrl cfg ! self 

        resolve = do
          let hints = defaultHints 
                { addrFlags = [AI_PASSIVE]
                , addrSocketType = Stream
                }
          addrInfo hints addr

        run = withSocketsDo $ do
          addr <- traceShowId <$> resolve
          E.bracket (open addr) close loop

        open addr = E.bracketOnError (openSocket addr) close $ \sock -> do
          setSocketOption sock ReuseAddr 1
          withFdSocket sock setCloseOnExecIfNeeded
          bind sock $ addrAddress addr
          listen sock 1024
          return sock

        loop sock = forever $ E.bracketOnError (accept sock) (close . fst)
          $ \(conn, _peer) -> void $
            forkFinally (serve conn) (const $ gracefulClose conn 5000)
          
addrInfo hints addr = head <$> ((uncurry $ getAddrInfo (Just hints)) $ stinkify addr)
  where 
    stinkify = \case
      SockAddrInet port host -> (Just . show $ host, Just . show $ port)
      SockAddrInet6 port _ host _	 -> (Just . show $ host, Just . show $ port)
      SockAddrUnix _ -> (Nothing, Nothing)

instance Backend TcpConfig where
  runNetwork = runNetworkTcp