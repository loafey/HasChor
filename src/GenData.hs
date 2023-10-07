{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use <&>" #-}

module GenData where

import Data.SOP ( K(..), NP(..), Proxy (Proxy), All (cpara_SList) )
import GHC.Generics ( (:*:) (..) )
import GHC.Read (Read(readPrec))
import Text.ParserCombinators.ReadPrec (ReadPrec, lift)
import GHC.TypeLits (KnownSymbol)
import Data.Kind (Constraint)
import Text.ParserCombinators.ReadP ( string, ReadP, pfail )


{- Type universe -}
data Ty where
  TInt    :: Ty
  TBool   :: Ty

data ColumnT (t :: Ty) where
  STInt    :: ColumnT 'TInt
  STBool   :: ColumnT 'TBool

class KnownTy (t :: Ty) where
  cType :: ColumnT t

instance KnownTy 'TInt where
  cType :: ColumnT 'TInt
  cType = STInt

instance KnownTy 'TBool where
  cType :: ColumnT 'TBool
  cType = STBool

instance KnownTy t => Show (ColumnT t) where
  show :: KnownTy t => ColumnT t -> String
  show _ = case (cType @t) of
             STInt  -> "Int"      -- t == 'TInt
             STBool -> "Bool"     -- t == 'TBool

newtype Table (ts :: [Ty]) = Table { repl :: NP (K String :*: ColumnT) ts }


withColumn :: ColumnT t -> (KnownTy t => r) -> r
withColumn c r = case c of
  STInt  -> r
  STBool -> r

withTable :: Table ts -> (All KnownTy ts => r) -> r
withTable (Table ts) = go ts
  where go :: NP (K String :*: ColumnT) ts -> (All KnownTy ts => r) -> r
        go Nil       r = r
        go (c@(K _ :*: t) :* cs) r = withColumn t $ go cs r

newtype Shows ts = Shows (NP (K String :*: ColumnT) ts -> String)

instance All KnownTy ts => Show (Table ts) where
   show :: All KnownTy ts => Table ts -> String
   show (Table np) = r np
      where
        Shows r = cpara_SList (Proxy @KnownTy) nil cons

        {- An empty dictionary is "Nil" -}
        nil :: Shows '[]
        nil =  Shows $ const "Nil"

        {- We can extend the dictionary r with y given that y is known -}
        cons :: forall y ys. KnownTy y => Shows ys -> Shows (y : ys)
        cons (Shows r) = Shows $ \(y :* ys) -> show y ++ " :* " ++ r ys

-- >>> show table1
-- "K \"id\" :*: Int :* K \"covid\" :*: Bool :* Nil"

instance KnownTy t => Read (ColumnT t) where
   readPrec :: KnownTy t => ReadPrec (ColumnT t)
   readPrec = case (cType @t) of
               STInt  -> do
                s <- lift (string "Int")
                if s == "Int" then return STInt
                              else lift pfail
               STBool -> lift (string "Bool") >> return STBool

-- >>> read "XXXX" :: ColumnT 'TInt 
-- Int


-- Why is that happening? 
-- >>> read "XXX" :: ColumnT 'TBool
-- Bool


-- >>> read "K \"id\" :*: STInt" :: (K String :*: ColumnT) 'TInt
-- Prelude.read: no parse

-- >>> show (K "ale" :*: STInt) :: (K String :*: ColumnT) 'TInt
-- Couldn't match type: [Char]
--                with: (:*:) (K String) ColumnT 'TInt
-- Expected: (:*:) (K String) ColumnT 'TInt
--   Actual: String
-- In the expression:
--     show (K "ale" :*: STInt) :: (K String :*: ColumnT) 'TInt
-- In an equation for `it_aahcP':
--     it_aahcP = show (K "ale" :*: STInt) :: (K String :*: ColumnT) 'TInt

-- Couldn't match type: [Char]
--                with: ColumnT 'TInt
-- Expected: ColumnT 'TInt
--   Actual: String
-- In the expression: show (K "ale" :*: STInt) :: ColumnT 'TInt
-- In an equation for `it_a9YU9':
--     it_a9YU9 = show (K "ale" :*: STInt) :: ColumnT 'TInt


-- >>> read "K \"id\" :*: Int :* K \"covid\" :*: Bool :* Nil" :: Table '[ 'TInt, 'TBool]
-- Prelude.read: no parse

newtype Reads ts = Reads (ReadPrec (NP (K String :*: ColumnT) ts))

{- An empty dictionary is "Nil" -}
rnil :: Reads '[]
rnil =  Reads $ return Nil

{- We can extend the dictionary r with y given that y is known -}
rcons :: forall y ys. KnownTy y => Reads ys -> Reads (y : ys)
rcons (Reads m) = Reads $ do
  n   <- readPrec :: ReadPrec ((K String :*: ColumnT) y)
  sep <- lift (string ":*:")
  np <- m
  return (n :* np)

instance All KnownTy ts => Read (Table ts) where
   readPrec :: ReadPrec (Table ts)
   readPrec = r >>= return . Table
      where
        Reads r = cpara_SList (Proxy @KnownTy) rnil rcons


-- >>> read "XInt" :: ColumnT 'TInt 
-- Int


type NameSpec = String
type TySpec   = String
type SchemaU  = [(NameSpec, TySpec)]

reifyTy :: TySpec -> (forall (t :: Ty) . KnownTy t => ColumnT t -> r) -> r
reifyTy "STInt"  k = k STInt
reifyTy "STBool" k = k STBool
reifyTy _      _k  = error "Unknown specified type!"

reifySchema :: SchemaU
            -> (forall (ts :: [Ty]) . All KnownTy ts => Table ts -> r)
            -> r
reifySchema []                 k = k (Table Nil)
reifySchema ((name,ct) : uSch) k =
  reifySchema uSch $ \(Table ts) ->
    reifyTy ct $ \case
                    STInt  -> k (Table (K name :*: STInt :* ts))
                    STBool -> k (Table (K name :*: STBool :* ts))


-- Tests 
table1 :: Table '[ 'TInt, 'TBool]
table1 = Table $ K "id" :*: STInt :* K "covid" :*: STBool :* Nil

-- >>> show table1
-- "K \"id\" :*: Int :* K \"covid\" :*: Bool :* Nil"

type family App (ts1 :: [Ty]) (ts2 :: [Ty]) where
  App '[]     ts2 = ts2
  App (t:ts1) ts2 = t : App ts1 ts2

merge :: Table ts1 -> Table ts2 -> Table (App ts1 ts2)
merge (Table Nil)        ts2 = ts2
merge (Table (t :* ts1)) ts2 = Table (t :* res)
  where Table res = merge (Table ts1) ts2



-- newtype Dummy ts = Dummy (Table ts)

-- {- An empty dictionary is "Nil" -}
-- dnil :: Dummy '[]
-- dnil =  Dummy (Table Nil)

-- {- We can extend the dictionary r with y given that y is known -}
-- dcons :: forall y ys. KnownTy y => Dummy ys -> Dummy (y : ys)
-- dcons (Dummy (Table np)) = Dummy $ Table $ K "" :*: cType @y :* np 

-- class DummyT ts where
--   dummy :: Table ts 

-- instance All KnownTy ts => DummyT ts where
--    dummy :: All KnownTy ts => Table ts
--    dummy = r 
--      where Dummy r = cpara_SList (Proxy @KnownTy) dnil dcons
