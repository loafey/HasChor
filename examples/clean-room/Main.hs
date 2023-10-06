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
    cfg = mkHttpConfig [ ("h1", ("localhost", 4242))
                       , ("h2", ("localhost", 4343))
                       , ("pserver", ("localhost", 4344))
                       ]

{-

open 3 terminals, and execute
  1. cabal run clean-room -- pserver
  2. cabal run clean-room -- h1
  3. cabal run clean-room -- h2

-}

sch1 :: Table '[ 'TInt, 'TBool ]
sch1 = Table $ K "id" :*: STInt :* K "covid" :*: STBool :* Nil

sch2 :: Table '[ 'TInt, 'TInt ]
sch2 = Table $ K "id" :*: STInt :* K "age" :*: STInt :* Nil

-- >>> show sch1
-- "K \"id\" :*: Int :* K \"covid\" :*: Bool :* Nil"

-- >>> show sch2
-- "K \"id\" :*: Int :* K \"age\" :*: Int :* Nil"

ttt :: Table '[ 'TInt, 'TBool, 'TInt, 'TInt]
ttt = merge sch1 sch2

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


-- Send all the schemas to the Public server 
gS :: (All KnownSymbol ls, KnownSymbol l', KnownSymbol l)
   => NP Proxy (l : ls) 
   -> Proxy l' 
   -> (forall ts. All KnownTy ts => Table ts @ l' -> Choreo IO r) 
   -> Choreo IO r
gS (p@Proxy :* ls) s k = do
     spec <- locally p $ \un -> do
        spec <- getLine
        return (read spec :: [(String,String)])
     reify p spec $ \ts -> do
       t1 <- (p, ts) ~> s
       case ls of
          Nil      -> locally' s k (\un -> un t1)
          (_ :* _) -> gS ls s $ \tsrs -> locally2 s k $ \un -> let m = merge (un t1) (un tsrs)
                                                               in withTableA m m          

-- An insight! We need a special locally that separates pure from Choreo
-- computations to make gS type-check. The good news is that it is a derived operation! 
locally' :: KnownSymbol l => Proxy l -> (a @ l -> Choreo IO b) -> (Unwrap l -> a) -> Choreo IO b
locally' p k u = do
   al <- locally p $ \un -> return $ u un   
   k al

locally2 :: (All KnownTy ts, KnownSymbol l) 
         => Proxy l -> (Table ts @ l -> Choreo IO b) -> (Unwrap l -> Table ts) -> Choreo IO b
locally2 p k u = do
   al <- locally p $ \un -> return $ u un   
   k al

-- something like that 
-- withTableAtLoc :: Table @ l -> (All KnownTy ts => r) -> r


-- If everything works, this piece of code will ask for two schemas and show the aggregated one
p :: Choreo IO ()  
p = gS (h1 :* Nil) pserver $ \ts -> do
   locally pserver $ \un -> withTable (un ts) $ putStrLn $ show (un ts) 
   (pserver, ts) ~> h1 
   return ()



