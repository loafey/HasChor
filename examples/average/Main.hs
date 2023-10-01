{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds      #-}
{-# LANGUAGE LambdaCase     #-}

module Main where

import Choreography
import Data.Proxy
import Data.Time
import System.Environment
import Choreography.Location (wrap)
import Data.Functor.Identity (Identity)

{-

open 4 terminals, and execute
  1. cabal run average-salary -- server
  2. cabal run average-salary -- person1
  3. cabal run average-salary -- person2
  4. cabal run average-salary -- person3

-}

{-

API:

type Unwrap l = forall a. a @ l -> a
locally :: KnownSymbol l                                   =>  Proxy l           -> (Unwrap l -> m a)              -> Choreo m (a @ l)
(~>)    :: (Show a, Read a, KnownSymbol l, KnownSymbol l') => (Proxy l, a @ l)   -> Proxy l'  -> Choreo m (a @ l')
(~~>)   :: (Show a, Read a, KnownSymbol l, KnownSymbol l') => (Proxy l, Unwrap l -> m a)      -> Proxy l'          -> Choreo m (a @ l')
cond    :: (Show a, Read a, KnownSymbol l)                 => (Proxy l, a @ l)   -> (a        -> Choreo m b)       -> Choreo m b
cond'   :: (Show a, Read a, KnownSymbol l)                 => (Proxy l, Unwrap l -> m a)      -> (a -> Choreo m b) -> Choreo m b

-}

person1 :: Proxy "person1"
person1 = Proxy

person2 :: Proxy "person2"
person2 = Proxy

person3 :: Proxy "person3"
person3 = Proxy

server :: Proxy "server"
server = Proxy

p1 :: (Int @ "person1")
p1 = wrap 42 

nested :: (Int @ "person1") @ "person1"
nested = wrap p1 

averageSalary :: Choreo IO (() @ "server")
averageSalary = do
  -- r1 <- (person1, \un -> return (un p1) :: IO Int) ~~> server    
  -- r1 <- (person1, \un -> return (un nested) :: IO (Int @ "person1")) ~~>
  -- server Here, we can see that (~~>) works with types that you can show, so
  -- you cannot send nested location-labeled values, nor send computations. This
  -- is pretty similar to our `Binary` restriction. Idea: we could support
  -- nested location, and when you send something of (Int @ "ale") @ "abi" you
  -- just send the integer encrypted but we need to indicate the intended reader, e.g., 
  -- (Int @ "ale" to "sever") @ "abi". 


  r1 <- (person1, \_ -> return 50 :: IO Int) ~~> server
  r2 <- (person2, \_ -> return 90 :: IO Int) ~~> server
  r3 <- (person3, \_ -> return 75 :: IO Int) ~~> server

  avg <- locally server $ \un -> return $ (sum [un r1, un r2, un r3]) `div` 3

  c1 <- (server, avg) ~> person1
  c2 <- (server, avg) ~> person2
  c3 <- (server, avg) ~> person3

  locally person1 $ \un -> putStrLn $ show $ un c1
  locally person2 $ \un -> putStrLn $ show $ un c2
  locally person3 $ \un -> putStrLn $ show $ un c3

  locally server $ \_ -> return ()

main :: IO ()
main = do
  [loc] <- getArgs
  case loc of
    "person1" -> runChoreography cfg averageSalary "person1"
    "person2" -> runChoreography cfg averageSalary "person2"
    "person3" -> runChoreography cfg averageSalary "person3"
    "server"  -> runChoreography cfg averageSalary "server"
  return ()
  where
    cfg = mkHttpConfig [ ("person1", ("localhost", 4242))
                       , ("person2", ("localhost", 4343))
                       , ("person3", ("localhost", 4344))
                       , ("server",  ("localhost", 4345))
                       ]
