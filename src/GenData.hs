{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module GenData where

import Data.SOP ( K(..), NP(..), Proxy (Proxy), All, All2, Compose )
import GHC.Generics ( (:*:) (..), (:.:) )
import GHC.Read (Read(readPrec))
import Text.ParserCombinators.ReadPrec (ReadPrec)
import GHC.TypeLits (KnownSymbol)


{- Type universe -}
data Ty where
  TInt    :: Ty
  TBool   :: Ty
  deriving Show

data ColumnT (t :: Ty) where
  STInt    :: ColumnT 'TInt
  STBool   :: ColumnT 'TBool
deriving instance (Show (ColumnT t))

newtype Table (ts :: [Ty]) = Table { repl :: NP (K String :*: ColumnT) ts }

-- Printing 
instance Show (Table ts) where
  show :: Table ts -> String
  show t = printSchema (repl t)

printSchema :: NP (K String :*: ColumnT) ts -> String
printSchema (K name :*: ty :* Nil) = show (name, show ty)
printSchema (K name :*: ty :* ts)  = show (name, show ty) ++ "," ++ printSchema ts

-- Reading 
instance Dummy ts => Read (Table ts) where
  readPrec :: ReadPrec (Table ts)
  readPrec = do
    ls <- readPrec :: ReadPrec [(String,String)]
    case buildSchema (Proxy :: Proxy (Table ts)) ls of
        Just t  -> return t
        Nothing -> error "Table has a wrong indicated typed!"

buildSchema :: Dummy ts => Proxy (Table ts) -> [(String,String)] -> Maybe (Table ts)
buildSchema p@Proxy = buildSchema' (dummy p)

buildSchema' :: Table ts -> [(String,String)] -> Maybe (Table ts)
buildSchema' (Table Nil) [] =  return $ Table Nil
buildSchema' (Table (K _ :*: t :* rs)) ((name,ty):ps) =
     reifyTy ty $ \ct -> case equalT ct t of
                              Just _p -> do
                                rest <- buildSchema' (Table rs) ps
                                return $ Table $ K name :*: t :* repl rest
                              Nothing -> Nothing

equalT :: ColumnT t -> ColumnT t' -> Maybe (Refl t t')
equalT STInt STInt   = return Refl
equalT STBool STBool = return Refl
equalT _      _      = Nothing

data Refl a b where
    Refl :: Refl a a


class Down (t :: Ty) where
    down :: Proxy t -> ColumnT t

instance Down 'TInt where
    down :: Proxy 'TInt -> ColumnT 'TInt
    down Proxy = STInt

instance Down 'TBool where
    down :: Proxy 'TBool -> ColumnT 'TBool
    down Proxy = STBool

class Dummy ts where
    dummy :: Proxy (Table ts) -> Table ts

instance Dummy '[] where
    dummy :: Proxy (Table '[]) -> Table '[]
    dummy Proxy = Table Nil

instance (Down t, Dummy ts) => Dummy (t:ts) where
    dummy :: Proxy (Table (t:ts)) -> Table (t:ts)
    dummy Proxy = Table $ K "" :*: down @t Proxy :* rest
        where Table rest = dummy @ts Proxy

test :: Table '[ 'TInt, 'TInt, 'TBool]
test = dummy (Proxy :: Proxy (Table '[ 'TInt, 'TInt, 'TBool]))

-- >>> show test
-- "(\"\",\"STInt\"),(\"\",\"STInt\"),(\"\",\"STBool\")"

type NameSpec = String
type TySpec   = String
type SchemaU  = [(NameSpec, TySpec)]

reifyTy :: TySpec -> (forall (t :: Ty) . Down t => ColumnT t -> r) -> r
reifyTy "STInt"  k = k STInt
reifyTy "STBool" k = k STBool
reifyTy _      _k  = error "Unknown specified type!"

reifySchema :: SchemaU
            -> (forall (ts :: [Ty]) . Dummy ts => Table ts -> r)
            -> r
reifySchema []                 k = k (Table Nil)
reifySchema ((name,ct) : uSch) k =
  reifySchema uSch (\(Table ts) -> reifyTy ct $ \t -> k (Table (K name :*: t :* ts)))

-- Tests 
table1 :: Table '[ 'TInt, 'TBool]
table1 = Table $ K "id" :*: STInt :* K "covid" :*: STBool :* Nil

-- >>> show table1
-- "[(\"id\",\"STInt\"),(\"covid\",\"STBool\")]"

-- >>> read "[(\"id\",\"STInt\"),(\"covid\",\"STBool\")]" :: Table '[ 'TInt, 'TBool]
-- ("id","STInt"),("covid","STBool")

-- >>> read "[(\"id\",\"STInt\"),(\"covid\",\"STInt\")]" :: Table '[ 'TInt, 'TBool]
-- Table has a wrong indicated typed!

type family App (ts1 :: [k]) (ts2 :: [k]) where
  App '[]     ts2 = ts2
  App (t:ts1) ts2 = t : App ts1 ts2

merge :: Table ts1 -> Table ts2 -> Table (App ts1 ts2)
merge (Table Nil)        ts2 = ts2
merge (Table (t :* ts1)) ts2 = Table (t :* res)
  where Table res = merge (Table ts1) ts2



