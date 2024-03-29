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

{-# RULES "CHOREORULES locallyandsend"
              forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) ~~> l'
                = do x <- l `locally` m
                     (l, x) ~> l' #-}
{-# RULES "CHOREORULES condprime"
              forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) `cond'` l'
                = do x <- l `locally` m
                     (l, x) `cond` l' #-}

worker1 :: Proxy "worker1"
worker1 = Proxy

worker2 :: Proxy "worker2"
worker2 = Proxy
{-# RULES "CHOREORULES locallyworker2"
              forall (f::(forall a. At a "worker2" -> a) -> m a) (worker :: Proxy "worker2"). worker
                                                                    `locally` f
                = wrap <$> run (f unwrap) #-}
{-# RULES "CHOREORULES locallyworker1"
              forall (f::(forall a. At a "worker1" -> a) -> m a) (worker :: Proxy "worker1"). worker
                                                                    `locally` f
                = return mkEmpty #-}
{-# RULES "CHOREORULES sendfromworker2"
              forall v recipient (worker :: Proxy "worker2"). (worker, v) ~> recipient
                = (send (unwrap v) (toLocTm recipient)) >> return mkEmpty #-}
{-# RULES "CHOREORULES sendtoworker2"
              forall from v (worker :: Proxy "worker2"). (from, v) ~> worker
                = wrap <$> recv (toLocTm from) #-}
{-# RULES "CHOREORULES condworker2"
              forall v c (worker :: Proxy "worker2"). (worker, v) `cond` c
                = (broadcast (unwrap v)) >> c (unwrap v) #-}
{-# RULES "CHOREORULES condworker1"
              forall v c (worker :: Proxy "worker1"). (worker, v) `cond` c
                = (recv (toLocTm worker)) >>= \ x -> c x #-}
run'_a3z2 choreo_a3z3
  = (runChoreography
       (mkHttpConfig
          [("worker1", ("localhost", 4000)),
           ("worker2", ("localhost", 5000))])
       choreo_a3z3 "worker2"
       >> return ())

-- $(compileFor 1         [ ("worker1", ("localhost", 4000))
--                        , ("worker2", ("localhost", 5000))
--                        ])

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
main = run'_a3z2 (alternate worker1 worker2 (wrap 0) (wrap 0))

-- 6 rules