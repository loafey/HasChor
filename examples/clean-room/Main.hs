{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds      #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}
{-# LANGUAGE GADTs #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}

module Main where

import Choreography
import Data.Proxy
import Data.Time
import System.Environment
import Choreography.Location (wrap)
import Data.Functor.Identity (Identity)
import Data.SOP ( K(..), NP(..), I (I), All )
import GHC.Generics ( (:*:) (..) )
import GenData
import GHC.TypeLits (KnownSymbol)


main :: IO ()
main = return ()

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

sch1 :: Table '[ 'TInt, 'TBool ]
sch1 = Table $ K "id" :*: STInt :* K "covid" :*: STBool :* Nil

sch2 :: Table '[ 'TInt, 'TInt ]
sch2 = Table $ K "id" :*: STInt :* K "age" :*: STInt :* Nil

h1 :: Proxy "h1"
h1 = Proxy

h2 :: Proxy "h2"
h2 = Proxy

pserver :: Proxy "pserver"
pserver = Proxy

sserver :: Proxy "sserver"
sserver = Proxy

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

    PublicServer: [f,g] -> SecretServer 

    p1 :: data1 :: sch1 -> SecretServer 
    p2 :: data2 :: sch2 -> SecretServer 

    SecretSever: Result1 -> p1 
    SecretSever: Result2 -> p2 
-}

{- 
  Example 
-}


step1 =  (h1, wrap sch1) ~> pserver
step2 =  (h2, wrap sch2) ~> pserver

publicServer :: Choreo IO ()
publicServer = do
  table1 <- (h1, wrap sch1) ~> pserver
  table2 <- (h2, wrap sch2) ~> pserver
  merged <- locally pserver $ \un -> return $ merge (un table1) (un table2)
  tablesh1 <- (pserver, merged) ~> h1
  tablesh2 <- (pserver, merged) ~> h2
  return ()



-- gpublicServer :: All KnownSymbol ls => NP Proxy ls -> Choreo IO ()
-- gpublicServer (p@Proxy :* ls)= do
--     t1 <- locally p $ \un -> do
--        spec <- getLine
--        let w    = read spec :: [(String,String)]
--            tabX = reifySchema w TableX 
--        return tabX   
--     pt1 <- (p, t1) ~> pserver 
--     return ()

