# Generic programming and choreographies for data clean rooms

1. The goal is to obtain well-typed representation of data schemas in order to
get well-typed data queries. The schemas are not known at compile time, so
generic programming is needed here. 

2. The number of location is not known at compile time but at *start up* time.
   Generic programming is needed here too. 

## 1.1 Generic programming for data schemas 

We consider tabular tables of type 

```haskell
newtype Table (ts :: [Ty]) = Table { repl :: NP (K String :*: ColumnT) ts }
```

which is essentially an n-product of columns of type `ColumnT t` where `t` is an
element of the heterogenous list `ts`.

```haskell
table1 :: Table '[ 'TInt, 'TBool]
table1 = Table $ K "id" :*: STInt :* K "covid" :*: STBool :* Nil
```

For simplicity, we consider the universe of types (i.e., the type of columns) as
integers and booleans. 

```haskell
data Ty where
  TInt    :: Ty
  TBool   :: Ty

data ColumnT (t :: Ty) where
  STInt    :: ColumnT 'TInt
  STBool   :: ColumnT 'TBool
```

In generic programming, you usually program in a CPS, where a runtime string is
going to be reified into a type -- but you do not know which one, so *all
posibilities need to be taken into account*. This is the pattern to follow: 

```haskell
reify :: String -> (forall t . SomeType t -> r) -> r
```

For instance, the function to reify the type of a column is as follows.

```haskell
reifyTy :: TySpec -> (forall (t :: Ty) . ColumnT t -> r) -> r
reifyTy "STInt"  k = k STInt
reifyTy "STBool" k = k STBool
reifyTy _      _k  = error "Unknown specified type!"
```

So, when using this function the continuation `k` will have the rest of the
well-typed computation. 

Function `reifyTy` is the function that can fail at runtime. However, if an
appropiated string is given (e.g., `STInt`), then `k STInt` executes and since
it is well-typed, it has much less posibilities to fail.  

To reify a complete data schema, we follow the same pattern.

```haskell
type NameSpec = String
type TySpec   = String
type SchemaU  = [(NameSpec, TySpec)]

reifySchema :: SchemaU
            -> (forall (ts :: [Ty]) . Table ts -> r)
            -> r
reifySchema []                 k = k (Table Nil)
reifySchema ((name,ct) : uSch) k =
  reifySchema uSch $ \(Table ts) ->
    reifyTy ct $ \case
                    STInt  -> k (Table (K name :*: STInt :* ts))
                    STBool -> k (Table (K name :*: STBool :* ts))
```

## 1.2 Choreographies and generic data schemas (*contribution*) 

The functions described above (e.g., `reifyTy` and `reifySchema`) can be seen as
*runtime type-checking*. 

When choreographies are introduced, then we face the following questions: 

a. How to incorporate the CPS of generic programming into HasChor? 

b. Where such a runtime type-checking needs to be carried out ? 

c. When we do point projection, what should be the reified list in the locations
   where reification didn't happen? 

### CPS and HasChor 


```
reify :: ... ( forall ts . Table ts -> r) -> r

```

```haskell
locally' :: KnownSymbol l => Proxy l -> (a @ l -> Choreo IO b) -> (Unwrap l -> a) -> Choreo IO b
locally' p k u = do
   al <- locally p $ \un -> return $ u un   
   k al
```





