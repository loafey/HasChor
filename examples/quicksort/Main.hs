{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}

module Main where

import Choreography
import Choreography.Choreo
import Choreography.Location
import Choreography.Network.Local
-- import Control.Concurrent.Async (async, mapConcurrently_, wait)
import Data.Proxy
import Data.Time
import GHC.TypeLits (KnownSymbol)
import System.Environment

-- * ROBERT: Does not work, as quicksort is both location polymorphic and recursive

$(compileFor 0 [ ("primary", ("localhost", 3000))
               , ("worker1", ("localhost", 4000))
               , ("worker2", ("localhost", 5000))
               ])

{-# SPECIALISE forall . quicksort primary worker1 worker2 #-}
{-# SPECIALISE forall . quicksort primary worker2 worker1 #-}
{-# SPECIALISE forall . quicksort worker1 primary worker2 #-}
{-# SPECIALISE forall . quicksort worker1 worker2 primary #-}
{-# SPECIALISE forall . quicksort worker2 worker1 primary #-}
{-# SPECIALISE forall . quicksort worker2 primary worker1 #-}
quicksort :: (KnownSymbol a, KnownSymbol b, KnownSymbol c) => Proxy a -> Proxy b -> Proxy c -> [Int] @ a -> Choreo IO ([Int] @ a)
quicksort a b c lst = do
  isEmpty <- a `locally` \unwrap -> pure (null (unwrap lst))
  cond (a, isEmpty) \case
    True -> do
      a `locally` \_ -> pure []
    False -> do
      smallerf <- a `locally` \unwrap -> let x:xs = unwrap lst in pure [ i | i <- xs, i <= x]
      smaller <- (a, smallerf) ~> b
--      smaller <- (a, \unwrap -> let x : xs = unwrap lst in pure [i | i <- xs, i <= x]) ~~> b
      smaller' <- quicksort b c a smaller
      smaller'' <- (b, smaller') ~> a
      biggerf <- a `locally` \unwrap -> let x : xs = unwrap lst in pure [ i | i <- xs, i > x]
      bigger <- (a, biggerf) ~> c
--      bigger <- (a, \unwrap -> let x : xs = unwrap lst in pure [i | i <- xs, i > x]) ~~> c
      bigger' <- quicksort c a b bigger
      bigger'' <- (c, bigger') ~> a
      a `locally` \unwrap -> pure $ unwrap smaller'' ++ [head (unwrap lst)] ++ unwrap bigger''

mainChoreo :: Choreo IO ()
mainChoreo = do
  lst <- primary `locally` \unwrap -> do return [1, 6, 5, 3, 4, 2, 7, 8]
  sorted <- quicksort primary worker1 worker2 lst
  primary `locally` \unwrap -> do
    putStrLn "here I am!"
    print (unwrap sorted)
    putStrLn "I printed them!"
    return ()
  return ()

main :: IO ()
main = run' mainChoreo