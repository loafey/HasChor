{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds      #-}
{-# LANGUAGE LambdaCase     #-}

module Main where

import Choreography
import Data.Proxy
import Data.Time
import System.Environment

{-

open 4 terminals, and execute
  1. cabal run average-salary -- server
  2. cabal run average-salary -- person1
  3. cabal run average-salary -- person2
  4. cabal run average-salary -- person3

-}

person1 :: Proxy "person1"
person1 = Proxy

person2 :: Proxy "person2"
person2 = Proxy

person3 :: Proxy "person3"
person3 = Proxy

server :: Proxy "server"
server = Proxy

averageSalary :: Choreo IO (() @ "server")
averageSalary = do
  r1 <- (person1, \_ -> return 50 :: IO Int) ~~> server
  r2 <- (person2, \_ -> return 90 :: IO Int) ~~> server
  r3 <- (person3, \_ -> return 75 :: IO Int) ~~> server

  locally server $ \un -> putStrLn $ show $ (sum [un r1, un r2, un r3]) `div` 3

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
