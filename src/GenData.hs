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
import Text.ParserCombinators.ReadP (string, ReadP)


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
               STInt  -> lift (string "Int")  >> return STInt
               STBool -> lift (string "Bool") >> return STBool

-- >>> read "Int" :: ColumnT 'TInt 
-- Int

-- Why is that happening? 
-- >>> read "XXX" :: ColumnT 'TBool
-- Bool

-- >>> read "K \"id\" :*: Int" :: (K String :*: ColumnT) 'TInt
-- Prelude.read: no parse

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


equalT :: ColumnT t -> ColumnT t' -> Maybe (Refl t t')
equalT STInt STInt   = return Refl
equalT STBool STBool = return Refl
equalT _      _      = Nothing

data Refl a b where
    Refl :: Refl a a


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


-- cpara_SList :: All c xs => proxy c -> r '[] -> (forall y ys. (c y, All c ys) => r ys -> r (y ': ys)) -> r xs
-- newtype Appp ts1 ts2 = Appp (Table (App ts1 ts2))

-- {- An empty dictionary is "Nil" -}
-- anil :: Appp '[] ts2
-- anil =  Appp ts2 

-- {- We can extend the dictionary r with y given that y is known -}
-- acons :: forall y ys ts2. KnownTy y => Appp ys ts2 -> Appp (y : ys) ts2
-- acons (Appp ys) = Appp ys 

