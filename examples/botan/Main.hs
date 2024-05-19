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


mainChoreo :: Choreo IO ()
mainChoreo = do
  -- -- -1. tcp testing thing :)
  -- val <- app `locally` \unwrap -> do
  --   num <- randomRIO (0,100 :: Int)
  --   pure $ "Hello from TCP: " <> show num
  -- app `locally` \unwrap -> do
  --   let val' = unwrap val
  --   print val'
  -- valServer <- (app, val) ~> server
  -- server `locally` \unwrap -> do
  --   let val = unwrap valServer
  --   print val
  -- app `locally` \_ -> liftIO $ putStrLn "app done"
  -- server `locally` \_ -> liftIO $ putStrLn "server done"

  return ()

-- {-# INLINE liftIO #-}
-- liftIO :: KnownSymbol b => Proxy b -> IO a -> Choreo IO (a @ b)
-- liftIO loc x = locally loc $ \unwrap -> x 

main :: IO ()
main = run' mainChoreo