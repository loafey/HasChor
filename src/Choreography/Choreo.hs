{-# LANGUAGE GADTs              #-}
{-# LANGUAGE ImpredicativeTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use const" #-}

-- | This module defines `Choreo`, the monad for writing choreographies.
module Choreography.Choreo where

import Choreography.Location
import Choreography.Network
import Control.Monad.Freer
import Data.List
import Data.Proxy
import GHC.TypeLits
import GenData (Table, SchemaU, reifySchema, KnownTy)
import Control.Monad (join)
import Data.SOP (All)

-- * The Choreo monad

-- | A constrained version of `unwrap` that only unwraps values located at a
-- specific location.
type Unwrap l = forall a. a @ l -> a

-- | Effect signature for the `Choreo` monad. @m@ is a monad that represents
-- local computations.
data ChoreoSig m a where
  Local :: (KnownSymbol l)
        => Proxy l
        -> (Unwrap l -> m a)
        -> ChoreoSig m (a @ l)

  Comm :: (Show a, Read a, KnownSymbol l, KnownSymbol l')
       => Proxy l
       -> a @ l
       -> Proxy l'
       -> ChoreoSig m (a @ l')

  Cond :: (Show a, Read a, KnownSymbol l)
       => Proxy l
       -> a @ l
       -> (a -> Choreo m b)
       -> ChoreoSig m b

  ReifyTable :: KnownSymbol l
             => Proxy l
             -> SchemaU @ l
             -> (forall ts . All KnownTy ts => Table ts @ l -> Choreo m r)
             -> ChoreoSig m r

-- | Monad for writing choreographies.
type Choreo m = Freer (ChoreoSig m)

-- | Run a `Choreo` monad directly.
runChoreo :: Monad m => Choreo m a -> m a
runChoreo = interpFreer handler
  where
    handler :: Monad m => ChoreoSig m a -> m a
    handler (Local _ m)  = wrap <$> m unwrap
    handler (Comm _ a _) = return $ (wrap . unwrap) a
    handler (Cond _ a c) = runChoreo $ c (unwrap a)
    handler (ReifyTable _ spec k) = reifySchema (unwrap spec) (runChoreo . k . wrap)

-- | Endpoint projection.
epp :: Choreo m a -> LocTm -> Network m a
epp c l' = interpFreer handler c
  where
    handler :: ChoreoSig m a -> Network m a
    handler (Local l m)
      | toLocTm l == l' = wrap <$> run (m unwrap)  -- this is a local computation, they are indeed 
                                                   -- projecting code. 
                                                   -- Question: there is no restriction about what you send. 
                                                   -- What happens if what you send contains suspended computations with secret data? 
                                                   -- What happens with nested location-decorated values? 
      | otherwise       = return Empty
    handler (Comm s a r)
      | toLocTm s == l' = send (unwrap a) (toLocTm r) >> return Empty
      | toLocTm r == l' = wrap <$> recv (toLocTm s)
      | otherwise       = return Empty
    handler (Cond l a c)
      | toLocTm l == l' = broadcast (unwrap a) >> epp (c (unwrap a)) l'
      | otherwise       = recv (toLocTm l) >>= \x -> epp (c x) l'
    handler (ReifyTable l spec k)
      | toLocTm l == l' = reifySchema (unwrap spec) (\ts -> epp (k (Wrap ts)) l')
      | otherwise       = epp (k @'[] Empty) l'


{- 

compile :: [LocTm] -> Choreo m a -> [(LocTm, Network m a)]
compile ls p = map (\l -> (l, epp p l)) ls

-}

-- * Choreo operations
-- | Perform a local computation at a given location.
locally :: KnownSymbol l
        => Proxy l           -- ^ Location performing the local computation.
        -> (Unwrap l -> m a) -- ^ The local computation given a constrained
                             -- unwrap funciton.
        -> Choreo m (a @ l)
locally l m = toFreer (Local l m)

-- | Communication between a sender and a receiver.
(~>) :: (Show a, Read a, KnownSymbol l, KnownSymbol l')
     => (Proxy l, a @ l)  -- ^ A pair of a sender's location and a value located
                          -- at the sender
     -> Proxy l'          -- ^ A receiver's location.
     -> Choreo m (a @ l')
(~>) (l, a) l' = toFreer (Comm l a l')

-- | Conditionally execute choreographies based on a located value.
cond :: (Show a, Read a, KnownSymbol l)
     => (Proxy l, a @ l)  -- ^ A pair of a location and a scrutinee located on
                          -- it.
     -> (a -> Choreo m b) -- ^ A function that describes the follow-up
                          -- choreographies based on the value of scrutinee.
     -> Choreo m b
cond (l, a) c = toFreer (Cond l a c)

-- | A variant of `~>` that sends the result of a local computation.
(~~>) :: (Show a, Read a, KnownSymbol l, KnownSymbol l')
      => (Proxy l, Unwrap l -> m a) -- ^ A pair of a sender's location and a local
                                    -- computation.
      -> Proxy l'                   -- ^ A receiver's location.
      -> Choreo m (a @ l')
(~~>) (l, m) l' = do
  x <- l `locally` m
  (l, x) ~> l'

-- | A variant of `cond` that conditonally executes choregraphies based on the
-- result of a local computation.
cond' :: (Show a, Read a, KnownSymbol l)
      => (Proxy l, Unwrap l -> m a) -- ^ A pair of a location and a local
                                    -- computation.
      -> (a -> Choreo m b)          -- ^ A function that describes the follow-up
                                    -- choreographies based on the result of the
                                    -- local computation.
      -> Choreo m b
cond' (l, m) c = do
  x <- l `locally` m
  cond (l, x) c

reify :: KnownSymbol l
      => Proxy l
      -> SchemaU @ l
      -> (forall ts . All KnownTy ts => Table ts @ l -> Choreo m r)
      -> Choreo m r
reify p spec k = toFreer $ ReifyTable p spec k 

