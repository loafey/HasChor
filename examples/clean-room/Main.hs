{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds      #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# LANGUAGE GADTs #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}
{-# LANGUAGE NoLiberalTypeSynonyms #-}
{-# HLINT ignore "Use print" #-}

module Main where

import Choreography
import Data.Proxy
import Data.Time
import System.Environment
import Data.Functor.Identity (Identity)
import Data.SOP ( K(..), NP(..), I (I), All )
import GHC.Generics ( (:*:) (..) )
import GenData
import GHC.TypeLits (KnownSymbol)
import Choreography.Choreo (reify, Unwrap)
import Control.Monad (join)


main :: IO ()
main = do
  [loc] <- getArgs
  case loc of
    "h1" -> runChoreography cfg p "h1"
    "h2" -> runChoreography cfg p "h2"
    "pserver" -> runChoreography cfg p "pserver"
  return ()
  where
    cfg = mkHttpConfig [ ("h1", ("localhost", 5000))
                       , ("h2", ("localhost", 5001))
                       , ("pserver", ("localhost", 5002))
                       ]

{-

open 3 terminals, and execute
  1. cabal run clean-room -- pserver
  2. cabal run clean-room -- h1
  3. cabal run clean-room -- h2

-}

h1 :: Proxy "h1"
h1 = Proxy

h2 :: Proxy "h2"
h2 = Proxy

pserver :: Proxy "pserver"
pserver = Proxy

{- 
    Two combinations 

    Join: DataSchema1 x DataSchema2 with one common field 
    Add: DataSchema1 == DataSchema2
-}

{-
  Actors
    Public server (responsible of the aggrement of data + analytics)

    Secret server (the one doing the aggregations and collecting all the data)

    Two hostpitals p1, and p2 

    Protocol

    p1: sch1 :: DataSchema -> PublicServer 
    p2: sch2 :: DataSchema -> PublicServer 

    PublicServer: (sch1,sch2) -> p1 
    PublicServer: (sch1,sch2) -> p2     

    p1: (f: (sch1 + sch2) -> Result1) -> PublicServer   (how to aggregate the schemas can be done in many ways) 
    p2: (g: (sch1 + sch2) -> Result2) -> PublicServer 

    PublicServer [f,g] -> p1
    PublicServer [f,g] -> p2 

    PublicServer: [f,g] -> SecretServer 

    p1 :: data1 :: sch1 -> SecretServer 
    p2 :: data2 :: sch2 -> SecretServer 
                       
    SecretSever: Result1 ->DP p1 
    SecretSever: Result2 ->DP p2 
-}


-- An insight: We need a special locally that separates pure from Choreo
-- computations to make collectSchemas type-check. The good news is that it is a derived operation! 
locally' :: KnownSymbol l => Proxy l -> (a @ l -> Choreo IO b) -> (Unwrap l -> a) -> Choreo IO b
locally' p k u = do
   al <- locally p $ \un -> return $ u un   
   k al

-- Send all the schemas to the public server, and they all get reified here!  
collectSchemas :: (All KnownSymbol ls, KnownSymbol l', KnownSymbol l)
   => NP Proxy (l : ls) 
   -> Proxy l' 
   -> (forall ts. Table ts @ l' -> Choreo IO r) 
   -> Choreo IO r
collectSchemas (p@Proxy :* ls) s k = do
     spec <- locally p $ \un -> do
        spec <- getLine
        return (read spec :: [(String,String)])
     sch <- (p, spec) ~> s 
     reify s sch $ \ts -> do
        case ls of
          Nil      -> locally' s k (\un -> un ts)
          (_ :* _) -> collectSchemas ls s $ \tsrs -> locally' s k $ \un -> merge (un ts) (un tsrs)

-- If everything works, this piece of code will ask for two schemas and show the aggregated one
p :: Choreo IO ()  
p = collectSchemas locations pserver $ \ts -> do
   tog <- locally pserver $ \un -> do 
    let schema = show $ un ts
    putStrLn schema
    return schema 
   sendBackSchema pserver tog locations 
   return ()
  where locations = h1 :* h2 :* Nil 

sendBackSchema :: (KnownSymbol s, All KnownSymbol ls) 
                => Proxy s -> String @ s -> NP Proxy ls -> Choreo IO ()
sendBackSchema s tog Nil       = return ()
sendBackSchema s tog (l :* ls) = do 
  tog' <- (s, tog) ~> l
  locally l $ \un -> putStrLn $ un tog' 
  sendBackSchema s tog ls