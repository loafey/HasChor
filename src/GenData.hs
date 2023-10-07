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

instance Show (Table ts) where
  show :: Table ts -> String
  show t = withTable t $ "[" ++ printSchema (repl t) ++ "]"

printSchema :: NP (K String :*: ColumnT) ts -> String
printSchema (K name :*: ty :* Nil) = withColumn ty $ show (name, show ty)
printSchema (K name :*: ty :* ts)  = withColumn ty $ show (name, show ty) ++ "," ++ printSchema ts

withColumn :: ColumnT t -> (KnownTy t => r) -> r
withColumn c r = case c of
  STInt  -> r
  STBool -> r

withTable :: Table ts -> (All KnownTy ts => r) -> r
withTable (Table ts) = go ts
  where go :: NP (K String :*: ColumnT) ts -> (All KnownTy ts => r) -> r
        go Nil       r = r
        go (c@(K _ :*: t) :* cs) r = withColumn t $ go cs r


-- >>> show table1
-- "K \"id\" :*: Int :* K \"covid\" :*: Bool :* Nil"


type NameSpec = String
type TySpec   = String
type SchemaU  = [(NameSpec, TySpec)]

reifyTy :: TySpec -> (forall (t :: Ty) . ColumnT t -> r) -> r
reifyTy "STInt"  k = k STInt
reifyTy "STBool" k = k STBool
reifyTy _      _k  = error "Unknown specified type!"

reifySchema :: SchemaU
            -> (forall (ts :: [Ty]) . Table ts -> r)
            -> r
reifySchema []                 k = k (Table Nil)
reifySchema ((name,ct) : uSch) k =
  reifySchema uSch $ \(Table ts) ->
    reifyTy ct $ \case
                    STInt  -> k (Table (K name :*: STInt :* ts))
                    STBool -> k (Table (K name :*: STBool :* ts))

type family App (ts1 :: [Ty]) (ts2 :: [Ty]) where
  App '[]     ts2 = ts2
  App (t:ts1) ts2 = t : App ts1 ts2

merge :: Table ts1 -> Table ts2 -> Table (App ts1 ts2)
merge (Table Nil)        ts2 = ts2
merge (Table (t :* ts1)) ts2 = Table (t :* res)
  where Table res = merge (Table ts1) ts2



newtype Dummy ts = Dummy (Table ts)

{- An empty dictionary is "Nil" -}
dnil :: Dummy '[]
dnil =  Dummy (Table Nil)

{- We can extend the dictionary r with y given that y is known -}
dcons :: forall y ys. KnownTy y => Dummy ys -> Dummy (y : ys)
dcons (Dummy (Table np)) = Dummy $ Table $ K "" :*: cType @y :* np 

dummy :: All KnownTy ts => Proxy ts -> Table ts 
dummy p = let Dummy tab = cpara_SList (Proxy @KnownTy) dnil dcons in tab 

instance All KnownTy ts => Read (Table ts) where
  readPrec :: ReadPrec (Table ts)
  readPrec = do
    ls <- readPrec :: ReadPrec [(String,String)]
    case buildSchema (Proxy :: Proxy (Table ts)) ls of
        Just t  -> return t
        Nothing -> error "Table has a wrong indicated typed!"

buildSchema :: forall ts . All KnownTy ts => Proxy (Table ts) -> [(String,String)] -> Maybe (Table ts)
buildSchema p@Proxy = buildSchema' $ dummy (Proxy :: Proxy ts)  

buildSchema' :: All KnownTy ts => Table ts -> [(String,String)] -> Maybe (Table ts)
buildSchema' (Table Nil) [] =  return $ Table Nil
buildSchema' (Table (K _ :*: t :* rs)) ((name,ty):ps) =
     reifyTy ty $ \ct -> do 
      rest <- buildSchema' (Table rs) ps
      return $ Table $ K name :*: cType :* repl rest

-- Tests 
table1 :: Table '[ 'TInt, 'TBool]
table1 = Table $ K "id" :*: STInt :* K "covid" :*: STBool :* Nil

-- >>> read "[(\"id\",\"STInt\"),(\"covid\",\"STBool\")]" :: Table '[ 'TInt, 'TBool]
-- K "id" :*: Int :* K "covid" :*: Bool :* Nil

-- >>> show table1
-- "[(\"id\",\"Int\"),(\"covid\",\"Bool\")]"
