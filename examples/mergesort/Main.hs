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
import Data.Time
import GHC.TypeLits (KnownSymbol)
import System.Environment

-- * ROBERT: Does not work, as sort and merge are both location polymorphic and recursive

divide :: [a] -> ([a], [a])
divide xs = splitAt lhx xs
  where
    lhx = length xs `div` 2

-- $(compileFor 2         [ ("primary", ("localhost", 3000))
--                        , ("worker1", ("localhost", 4000))
--                        , ("worker2", ("localhost", 5000))
--                        ])

{-# RULES "CHOREORULES locallyandsend"
              forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) ~~> l'
                = do x <- l `locally` m
                     (l, x) ~> l' #-}
{-# RULES "CHOREORULES condprime"
              forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) `cond'` l'
                = do x <- l `locally` m
                     (l, x) `cond` l' #-}

primary :: Proxy "primary"
primary = Proxy

worker1 :: Proxy "worker1"
worker1 = Proxy

worker2 :: Proxy "worker2"
worker2 = Proxy
{-# RULES "CHOREORULES locallyprimary"
              forall (f::(forall a. At a "primary" -> a) -> m a) (primary :: Proxy "primary"). primary
                                                                    `locally` f
                = wrap <$> run (f unwrap) #-}
{-# RULES "CHOREORULES locallyworker1"
              forall (f::(forall a. At a "worker1" -> a) -> m a) (worker1 :: Proxy "worker1"). worker1
                                                                    `locally` f
                = return mkEmpty #-}
{-# RULES "CHOREORULES locallyworker2"
              forall (f::(forall a. At a "worker2" -> a) -> m a) (worker2 :: Proxy "worker2"). worker2
                                                                    `locally` f
                = return mkEmpty #-}
{-# RULES "CHOREORULES sendfromprimary"
              forall v recipient (primary :: Proxy "primary"). (primary, v) ~> recipient
                = (send (unwrap v) (toLocTm recipient)) >> return mkEmpty #-}
{-# RULES "CHOREORULES sendtoprimary"
              forall from v (primary :: Proxy "primary"). (from, v) ~> primary
                = wrap <$> recv (toLocTm from) #-}
{-# RULES "CHOREORULES sendworker1worker2"
              forall v (worker1 :: Proxy "worker1") (worker2 :: Proxy "worker2"). (worker1, v) ~> worker2
                = return mkEmpty #-}
{-# RULES "CHOREORULES sendworker2worker1"
              forall v (worker1 :: Proxy "worker1") (worker2 :: Proxy "worker2"). (worker2, v) ~> worker1
                = return mkEmpty #-}
{-# RULES "CHOREORULES condprimary"
              forall v c (primary :: Proxy "primary"). (primary, v) `cond` c
                = (broadcast (unwrap v)) >> c (unwrap v) #-}
{-# RULES "CHOREORULES condworker1"
              forall v c (worker1 :: Proxy "worker1"). (worker1, v) `cond` c
                = (recv (toLocTm worker1)) >>= \ x -> c x #-}
{-# RULES "CHOREORULES condworker2"
              forall v c (worker2 :: Proxy "worker2"). (worker2, v) `cond` c
                = (recv (toLocTm worker2)) >>= \ x -> c x #-}
run'_a3Z8 choreo_a3Z9
  = (runChoreography
       (mkHttpConfig
          [("primary", ("localhost", 3000)),
           ("worker1", ("localhost", 4000)),
           ("worker2", ("localhost", 5000))])
       choreo_a3Z9 "primary"
       >> return ())















-- {-# RULES "CHOREORULES locallyandsend"
--               forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) ~~> l'
--                 = do x <- l `locally` m
--                      (l, x) ~> l' #-}
-- {-# RULES "CHOREORULES condprime"
--               forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) `cond'` l'
--                 = do x <- l `locally` m
--                      (l, x) `cond` l' #-}

-- primary :: Proxy "primary"
-- primary = Proxy

-- worker1 :: Proxy "worker1"
-- worker1 = Proxy

-- worker2 :: Proxy "worker2"
-- worker2 = Proxy
-- {-# RULES "CHOREORULES locallyworker1"
--               forall (f::(forall a. At a "worker1" -> a) -> m a) (worker1 :: Proxy "worker1"). worker1
--                                                                     `locally` f
--                 = wrap <$> run (f unwrap) #-}
-- {-# RULES "CHOREORULES locallyprimary"
--               forall (f::(forall a. At a "primary" -> a) -> m a) (primary :: Proxy "primary"). primary
--                                                                     `locally` f
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES locallyworker2"
--               forall (f::(forall a. At a "worker2" -> a) -> m a) (worker2 :: Proxy "worker2"). worker2
--                                                                     `locally` f
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES sendfromworker1"
--               forall v recipient (worker1 :: Proxy "worker1"). (worker1, v) ~> recipient
--                 = (send (unwrap v) (toLocTm recipient)) >> return mkEmpty #-}
-- {-# RULES "CHOREORULES sendtoworker1"
--               forall from v (worker1 :: Proxy "worker1"). (from, v) ~> worker1
--                 = wrap <$> recv (toLocTm from) #-}
-- {-# RULES "CHOREORULES sendprimaryworker2"
--               forall v (primary :: Proxy "primary") (worker2 :: Proxy "worker2"). (primary, v) ~> worker2
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES sendworker2primary"
--               forall v (primary :: Proxy "primary") (worker2 :: Proxy "worker2"). (worker2, v) ~> primary
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES condworker1"
--               forall v c (worker1 :: Proxy "worker1"). (worker1, v) `cond` c
--                 = (broadcast (unwrap v)) >> c (unwrap v) #-}
-- {-# RULES "CHOREORULES condprimary"
--               forall v c (primary :: Proxy "primary"). (primary, v) `cond` c
--                 = (recv (toLocTm primary)) >>= \ x -> c x #-}
-- {-# RULES "CHOREORULES condworker2"
--               forall v c (worker2 :: Proxy "worker2"). (worker2, v) `cond` c
--                 = (recv (toLocTm worker2)) >>= \ x -> c x #-}
-- run'_a41m choreo_a41n
--   = (runChoreography
--        (mkHttpConfig
--           [("primary", ("localhost", 3000)),
--            ("worker1", ("localhost", 4000)),
--            ("worker2", ("localhost", 5000))])
--        choreo_a41n "worker1"
--        >> return ())











-- {-# RULES "CHOREORULES locallyandsend"
--               forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) ~~> l'
--                 = do x <- l `locally` m
--                      (l, x) ~> l' #-}
-- {-# RULES "CHOREORULES condprime"
--               forall l (m::(forall a. At a l -> a) -> m a) l'. (l, m) `cond'` l'
--                 = do x <- l `locally` m
--                      (l, x) `cond` l' #-}

-- primary :: Proxy "primary"
-- primary = Proxy

-- worker1 :: Proxy "worker1"
-- worker1 = Proxy

-- worker2 :: Proxy "worker2"
-- worker2 = Proxy
-- {-# RULES "CHOREORULES locallyworker2"
--               forall (f::(forall a. At a "worker2" -> a) -> m a) (worker2 :: Proxy "worker2"). worker2
--                                                                     `locally` f
--                 = wrap <$> run (f unwrap) #-}
-- {-# RULES "CHOREORULES locallyprimary"
--               forall (f::(forall a. At a "primary" -> a) -> m a) (primary :: Proxy "primary"). primary
--                                                                     `locally` f
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES locallyworker1"
--               forall (f::(forall a. At a "worker1" -> a) -> m a) (worker1 :: Proxy "worker1"). worker1
--                                                                     `locally` f
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES sendfromworker2"
--               forall v recipient (worker2 :: Proxy "worker2"). (worker2, v) ~> recipient
--                 = (send (unwrap v) (toLocTm recipient)) >> return mkEmpty #-}
-- {-# RULES "CHOREORULES sendtoworker2"
--               forall from v (worker2 :: Proxy "worker2"). (from, v) ~> worker2
--                 = wrap <$> recv (toLocTm from) #-}
-- {-# RULES "CHOREORULES sendprimaryworker1"
--               forall v (primary :: Proxy "primary") (worker1 :: Proxy "worker1"). (primary, v) ~> worker1
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES sendworker1primary"
--               forall v (primary :: Proxy "primary") (worker1 :: Proxy "worker1"). (worker1, v) ~> primary
--                 = return mkEmpty #-}
-- {-# RULES "CHOREORULES condworker2"
--               forall v c (worker2 :: Proxy "worker2"). (worker2, v) `cond` c
--                 = (broadcast (unwrap v)) >> c (unwrap v) #-}
-- {-# RULES "CHOREORULES condprimary"
--               forall v c (primary :: Proxy "primary"). (primary, v) `cond` c
--                 = (recv (toLocTm primary)) >>= \ x -> c x #-}
-- {-# RULES "CHOREORULES condworker1"
--               forall v c (worker1 :: Proxy "worker1"). (worker1, v) `cond` c
--                 = (recv (toLocTm worker1)) >>= \ x -> c x #-}
-- run'_a41m choreo_a41n
--   = (runChoreography
--        (mkHttpConfig
--           [("primary", ("localhost", 3000)),
--            ("worker1", ("localhost", 4000)),
--            ("worker2", ("localhost", 5000))])
--        choreo_a41n "worker2"
--        >> return ())


{-# SPECIALISE forall . sort primary worker1 worker2 #-}
{-# SPECIALISE forall . sort primary worker2 worker1 #-}
{-# SPECIALISE forall . sort worker2 primary worker1 #-}
{-# SPECIALISE forall . sort worker1 primary worker2 #-}
{-# SPECIALISE forall . sort primary worker1 worker2 #-}
{-# SPECIALISE forall . sort primary worker2 worker1 #-}
sort ::
  KnownSymbol a =>
  Proxy a ->
  KnownSymbol b =>
  Proxy b ->
  KnownSymbol c =>
  Proxy c ->
  ([Int] @ a) ->
  Choreo IO ([Int] @ a)
sort a b c lst = do
  condition <- a `locally` \unwrap -> do return $ length (unwrap lst) > 1
  cond (a, condition) \case
    True -> do
      pivot <- a `locally` \unwrap -> do return $ length (unwrap lst) `div` 2
      divided <- a `locally` \unwrap -> do return $ divide (unwrap lst)
      l <- a `locally` \unwrap -> do return $ fst (unwrap divided)
      r <- a `locally` \unwrap -> do return $ snd (unwrap divided)
      l' <- (a, l) ~> b
      r' <- (a, r) ~> c
      ls' <- sort b c a l'
      rs' <- sort c a b r'
      merge a b c ls' rs'
    False -> do
      return lst

{-# SPECIALISE forall . merge primary worker1 worker2 #-}
{-# SPECIALISE forall . merge primary worker2 worker1 #-}
{-# SPECIALISE forall . merge worker2 primary worker1 #-}
{-# SPECIALISE forall . merge worker1 primary worker2 #-}
{-# SPECIALISE forall . merge primary worker1 worker2 #-}
{-# SPECIALISE forall . merge primary worker2 worker1 #-}
merge ::
  KnownSymbol a =>
  Proxy a ->
  KnownSymbol b =>
  Proxy b ->
  KnownSymbol c =>
  Proxy c ->
  [Int] @ b ->
  [Int] @ c ->
  Choreo IO ([Int] @ a)
merge a b c lhs rhs = do
  lhsHasElements <- b `locally` \unwrap -> do return $ not (null (unwrap lhs))
  cond (b, lhsHasElements) \case
    True -> do
      rhsHasElements <- c `locally` \unwrap -> do return $ not (null (unwrap rhs))
      cond (c, rhsHasElements) \case
        True -> do
          rhsHeadAtC <- c `locally` \unwrap -> do return $ head (unwrap rhs)
          rhsHeadAtB <- (c, rhsHeadAtC) ~> b
          takeLhs <- b `locally` \unwrap -> do return $ head (unwrap lhs) <= unwrap rhsHeadAtB
          cond (b, takeLhs) \case
            True -> do
              -- take (head lhs) and merge the rest
              lhs' <- b `locally` \unwrap -> do return $ tail (unwrap lhs)
              merged <- merge a b c lhs' rhs
              lhsHeadAtB <- b `locally` \unwrap -> do return $ head (unwrap lhs)
              lhsHeadAtA <- (b, lhsHeadAtB) ~> a
              a `locally` \unwrap -> do return $ unwrap lhsHeadAtA : unwrap merged
            False -> do
              -- take (head rhs) and merge the rest
              rhs' <- c `locally` \unwrap -> do return $ tail (unwrap rhs)
              merged <- merge a b c lhs rhs'
              rhsHeadAtC <- c `locally` \unwrap -> do return $ head (unwrap rhs)
              rhsHeadAtA <- (c, rhsHeadAtC) ~> a
              a `locally` \unwrap -> do return $ unwrap rhsHeadAtA : unwrap merged
        False -> do
          (b, lhs) ~> a
    False -> do
      (c, rhs) ~> a

mainChoreo :: Choreo IO ()
mainChoreo = do
  lst <- primary `locally` \unwrap -> do return [1, 6, 5, 3, 4, 2, 7, 8]
  sorted <- sort primary worker1 worker2 lst
  primary `locally` \unwrap -> do
    print (unwrap sorted)
    return ()
  return ()

main :: IO ()
main = run'_a3Z8 mainChoreo

-- main :: IO ()
-- main = do
--   [loc] <- getArgs
--   case loc of
--     "primary" -> runChoreography config mainChoreo "primary"
--     "worker1" -> runChoreography config mainChoreo "worker1"
--     "worker2" -> runChoreography config mainChoreo "worker2"
--   return ()
--   where
--     config =
--       mkHttpConfig
--         [ ("primary", ("localhost", 3000)),
--           ("worker1", ("localhost", 4000)),
--           ("worker2", ("localhost", 5000))
--         ]


-- primary old = 160 rules
-- primary new = 161 rules

-- worker1 old = 160 rules
-- worker1 new = 161 rules

-- worker2 old = 160 rules
-- worker2 new = 161 rules