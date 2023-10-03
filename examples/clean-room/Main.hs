{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds      #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}
{-# LANGUAGE GADTs #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}
{-# HLINT ignore "Use join" #-}
{-# LANGUAGE LiberalTypeSynonyms #-}
{-# HLINT ignore "Use <$>" #-}

module Main where

import Choreography
import Data.Proxy
import Data.Time
import System.Environment
import Choreography.Location (wrap, unwrap, joinLoc)
import Data.Functor.Identity (Identity)
import Data.SOP ( K(..), NP(..), I (I), All )
import GHC.Generics ( (:*:) (..) )
import GenData
import GHC.TypeLits (KnownSymbol)
import Choreography.Choreo (reify, TableX (..), rewrap, Unwrap)
import Control.Monad (join)
import Control.Monad.Freer (joinFreer)


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

ttt = merge' sch1 sch2

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
  merged <- locally pserver $ \un -> return $ merge' (un table1) (un table2)
  tablesh1 <- (pserver, merged) ~> h1
  tablesh2 <- (pserver, merged) ~> h2
  return ()

gpublicServer :: All KnownSymbol ls => NP Proxy ls -> Choreo IO ()
gpublicServer (p@Proxy :* ls)= do
     spec <- locally p $ \un -> do
        spec <- getLine
        let w    = read spec :: [(String,String)]
        return w
     reifySchema (unwrap spec) $ \ts -> do   -- Here, we need to extend HasChor, 
                                             -- Where is the reification happening? 
                                             -- I will say in the client
        pt1 <- (p, wrap ts) ~> pserver
        gpublicServer ls
gpublicServer Nil = return ()


-- Send all the schemas to the Public server 
gServer :: (All KnownSymbol ls, KnownSymbol l') => NP Proxy ls -> Proxy l' -> Choreo IO [TableX @ l']
gServer (p@Proxy :* ls) s = do
     spec <- locally p $ \un -> do
        spec <- getLine
        return (read spec :: [(String,String)])
     reify p spec \ts -> do
      pt1  <- (p, ts) ~> s
      pt1' <- rewrap s pt1
      rs   <- gServer ls s
      return (pt1' : rs)
gServer Nil s = return []

mergeX :: TableX -> TableX -> TableX
mergeX (TableX t) (TableX t') = TableX (merge' t t')

aggregate :: KnownSymbol l => Proxy l -> [TableX @ l] -> Choreo IO (TableX @ l)
aggregate s (tx : txs) = do
   rest <- aggregate s txs
   locally s $ \un -> return $ mergeX (un tx) (un rest)


{-
-- Send all the schemas to the Public server 
gS :: (All KnownSymbol ls, KnownSymbol l')
   => NP Proxy ls -> Proxy l' -> (forall ff. Table ff -> Choreo IO r) -> Choreo IO r'
gS (p@Proxy :* ls) s k = do
     spec <- locally p $ \un -> do
        spec <- getLine
        return (read spec :: [(String,String)])
     reify p spec $ \ts -> do 
      t1 <- (p, ts) ~> s
      gS ls s ( \tsrs -> k (merge' (un pts) tsrs))
-}


-- Send all the schemas to the Public server 
gS :: (All KnownSymbol ls, KnownSymbol l')
   => NP Proxy ls -> Proxy l' -> (forall ff. Table ff @ l' -> Choreo IO r) -> Choreo IO r
gS (p@Proxy :* ls) s k = do
     spec <- locally p $ \un -> do
        spec <- getLine
        return (read spec :: [(String,String)])
     reify p spec $ \ts -> do 
      t1 <- (p, ts) ~> s
      gS ls s ( \tsrs -> newlocally s k (\un -> merge' (un t1) (un tsrs)))

newlocally :: KnownSymbol l => Proxy l -> (a @ l -> Choreo IO b) -> (Unwrap l -> a) -> Choreo IO b 
newlocally p k u = do 
   al <- locally p $ \un -> return $ u un  
   k al 

{-
  
      gS ls s ( \tsrs -> newLocally s k (\un -> merge' (un pts) tsrs))

      newLocally :: server -> (Table ts -> Choreo IO r) (Unwrap server -> Table ts) -> Choreo IO r

      gS :: server -> (Table ts -> Choreo IO r) -> Choreo IO r 

-}

{-

gS :: (All KnownSymbol ls, KnownSymbol l') => NP Proxy ls -> Proxy l' -> Choreo IO (TableX @ l')
gS (p@Proxy :* ls) s = do
     spec <- locally p $ \un -> do
        spec <- getLine
        return (read spec :: [(String,String)])
     reify p spec \ts -> do
      pt1  <- (p, ts) ~> s
      pt1' <- rewrap s pt1
      rs   <- gS ls s
      locally s $ \un -> return $ mergeX (un pt1') (un rs) 
gS Nil s = locally s $ \un -> return (TableX (Table Nil))

-- Trivial 

-}

{-

     reify p spec $ \ts -> do
      pt1  <- (p, ts) ~> s
      gs ls s (\tsrs -> return tsrs)

locally s $ (Choreo IO) r -> Choreo (Choreo IO) r
 
Choreo (Freer ChoreoSig m) a -... Choreo a 

Freer (ChoreoSig (Freer ChoreoSig m)) a = Freer (ChoreoSig m) a


-}


{- 
  ReifySchema :: (Show a, Read a, KnownSymbol l)
       => Proxy l
       -> [(String,String)] @ l
       -> (forall ts . Table ts -> Choreo m b)
       -> ChoreoSig m b

    handler (ReifySchema p spec k)
      | toLocTm l == l' = reifySchema (unwrap spec) (epp . k) 
      | otherwise       = return Empty 
-}
