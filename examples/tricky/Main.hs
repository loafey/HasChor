{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}

module Main where

import Choreography
import Choreography.Choreo
import Choreography.Location
import Choreography.Network.Http
import Data.Proxy
import GHC.TypeLits (KnownSymbol, symbolVal)
import System.Environment

$(compileFor 0         [ ("worker1", ("localhost", 4000))
                       , ("worker2", ("localhost", 5000))
                       ])

{-# SPECIALISE forall . alternate worker1 worker2 #-}
{-# SPECIALISE forall . alternate worker2 worker1 #-}
alternate :: (KnownSymbol a, KnownSymbol b) => Proxy a -> Proxy b -> Int @ a -> Int @ b -> Choreo IO ()
alternate a b ai bi = do
    aatb <- (a,ai) ~> b
    let s = symbolVal a
        ss = symbolVal b
    locally b $ \unwrap -> print ("received from " <> s <> " at " <> ss <> ": " <> (show $ unwrap aatb))
    ai' <- locally a $ \unwrap -> return (unwrap ai + 1)
    alternate b a bi ai'

main :: IO ()
main = run' (alternate worker1 worker2 (wrap 0) (wrap 0))