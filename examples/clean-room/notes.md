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

1. How to incorporate the CPS of generic programming into HasChor? 

2. Where such a runtime type-checking needs to be carried out ? 

3. When we do point projection, what should be the reified list in the locations
   where reification didn't happen? 

### CPS and HasChor (Question 1)

When considering CPS style of programming, 

```haskell
reify :: String -> ( forall ts . Table ts -> r) -> r
```

We first need to introduce locations to make sure that the `Table ts` is only accesible at a given location `l`. So, we should consider a pattern of the form

```haskell
reify :: String -> ( forall ts . Table ts @ l -> r) -> r
```

By doing so, we are sure that `Table ts @ l` is only accesible **locally** to `l` and it does not *leak* to somewhere else. 

When it comes to the type `r`, it is going to be a choreography. 

```haskell
reify :: String -> ( forall ts . Table ts @ l -> Choreo m r) -> Choreo m r
```

This reads as *reify at location `l` and then continue executing the rest of the
choreography*. 

It becomes clear that reification happens at a certain location `l`, so yielding
the `Table @ l` value. 

We can now extend `Choreo.hs` to consider reifycation for tables. 

```haskell
data ChoreoSig m a where
    ...
    ReifyTable :: KnownSymbol l
               => Proxy l
               -> SchemaU @ l
               -> (forall ts . Table ts @ l -> Choreo m r)
               -> ChoreoSig m r

reify :: KnownSymbol l
      => Proxy l             -- where reification occurs
      -> SchemaU @ l         -- data comes from the same location
      -> (forall ts . Table ts @ l -> Choreo m r)
      -> Choreo m r
reify p spec k = toFreer $ ReifyTable p spec k               
```

**Q1: Can be this generalized so that it also works beyond tables?** 

### Location for reification (Question 2 and 3) 

From the type of `reify`, reification happens at a location *l* so in the other
location then the table has no columns. We see that when extending the end-point
projection function: 

```haskell
epp :: Choreo m a -> LocTm -> Network m a
epp c l' = interpFreer handler c
  where
    handler :: ChoreoSig m a -> Network m a
    handler (ReifyTable l spec k)
      | toLocTm l == l' = reifySchema (unwrap spec) (\ts -> epp (k (Wrap ts)) l')
      | otherwise       = epp (k @'[] Empty) l'  -- in other locations the table has no columns (@ '[])
```

The function that runs reification directly into the monad, it can also be extended. 

```haskell
-- | Run a `Choreo` monad directly.
runChoreo :: Monad m => Choreo m a -> m a
runChoreo = interpFreer handler
  where
    handler :: Monad m => ChoreoSig m a -> m a
    handler (ReifyTable _ spec k) = reifySchema (unwrap spec) (runChoreo . k . wrap)
```

## 1.3 Data clean room protocol (*contribution*)

[IDC predicts that by 2024, 65% of G2000 Enterprises will form data-sharing
partnerships with external stakeholders via data clean
rooms](https://www.databricks.com/blog/2022/06/28/introducing-data-cleanrooms-for-the-lakehouse.html)
to increase interdependence while safeguarding data privacy.

There seems to **not** be any specification or protocol to follow when it comes
to using a data clean room. 

So, another contribution is to provide a **protocol** for using data clean rooms. 

```
Actors
    Public server (responsible of the aggrement of data + analytics)

    Secret server (the one doing the aggregations and collecting all the data)

    Two hostpitals p1, and p2 (it could be n but let's start with two)

Protocol

    -- Both Hospitals send a description of the tables they will use
    h1: specSch1 :: String -> PublicServer 
    h2: specSch2 :: String -> PublicServer 

    -- The public server reifies specSch1 into (Table ts1) and specSch2 into (Table ts2), and 
    -- the server creates Table (ts1 ++ ts2), and sends a text specification of this table to 
    -- the hospitals. 

    PublicServer: specJoin :: String -> p1 
    PublicServer: specJoin :: String -> p2     

    -- The clients send a query in text form to the public server 
    p1: query1 :: String -> PublicServer    
    p2: query2 :: String -> PublicServer 

    -- The public server type-checks those queries to see if they can be refied into functions of the 
    -- form (Table (ts1 ++ ts2) -> Result), if so, it sends them back to the clients to see if they are 
    -- ok with such analysis on their data. 

    PublicServer [query1,query2] -> p1
    PublicServer [query1,query2] -> p2 

    h1: Ok | NotOk -> PublicServer 
    h2: Ok | NotOk -> PublicServer 

    -- If all of them gave the Ok, then 
    PublicServer: [specSch1, specSch2, query1, query2] -> SecretServer 

    p1 :: data1 :: [Rows] -> SecretServer 
    p2 :: data2 :: [Rows] -> SecretServer 
                       
    -- Here, the secret server reifies the tables and the queries and run them!

    SecretSever: Result -> p1 
    SecretSever: Result -> p2 
```

So, we need to build that protocol using **choreographies**! 

## 1.4 Data clean room protocol as a choreography (*contribution*)

We can use generic programming to implement the first part of the protocol,
i.e., the one that collects all of the data schemas from the participants.

```haskell 
collectSchemas :: (All KnownSymbol ls, KnownSymbol l', KnownSymbol l)
   => NP Proxy (l : ls)                         -- all the clients 
   -> Proxy l'                                  -- the public server 
   -> (forall ts. Table ts @ l' -> Choreo IO r) -- The continuation based on reification 
   -> Choreo IO r
collectSchemas (p@Proxy :* ls) s k = do
     spec <- locally p $ \un -> do                 -- each node asks for the schema 
        spec <- getLine
        return (read spec :: [(String,String)])
     sch <- (p, spec) ~> s                         -- the schema is sent to the server
     ... 
```

Now, the server will check if the strings being received can be reified into a
typed table. 

```haskell
     ... 
     sch <- (p, spec) ~> s 
     reify s sch $ \ts -> do     -- reification happening at the server side 
        case ls of
          Nil      -> k ts
          (_ :* _) -> collectSchemas ls s $ \tsrs -> k ...(merge ts tsrs)...
```

At the continuation of the recursive call, we need to apply the continuation with the *merge" of all the data schemas, where 

```haskell
type family App (ts1 :: [Ty]) (ts2 :: [Ty]) where
  App '[]     ts2 = ts2
  App (t:ts1) ts2 = t : App ts1 ts2

merge :: Table ts1 -> Table ts2 -> Table (App ts1 ts2)
merge (Table Nil)        ts2 = ts2
merge (Table (t :* ts1)) ts2 = Table (t :* res)
  where Table res = merge (Table ts1) ts2
```

**Q2: Here, the merge needs to be more complicated. It needs to consider the
first column as the column over which to do a join. How could we do that?**

If we zoom into the continuation of the recursive call. 

```haskell
          (_ :* _) -> collectSchemas ls s $ \tsrs -> k ...(merge ts tsrs)...
                                    --   ^^^^ :: Table ts @ l -> Choreo m r 
```

However, to merge `ts :: Table ts @ l` and `tsrs :: Table ts' @ l` we need to
*unwrapped*, and if we unwrapped, it means that we need the primitive `locally`. 

```haskell
          (_ :* _) -> collectSchemas ls s $ \tsrs -> 
            locally s (\un -> return (merge (un ts) (un tsrs))) >>= k  
```

This completes the first step of the protocol. The second part is simple send the join data schema to the participants. 

```haskell
p :: Choreo IO ()  
p = collectSchemas locations pserver $ \ts -> do -- it collects all the schemas, and obtains the merge one
   tog <- locally pserver $ \un -> do 
    let schema = show $ un ts
    putStrLn schema               
    return schema                 
   sendBackSchema pserver tog locations         -- send the join schema back to the clients 
   return ()
  where locations = h1 :* h2 :* Nil    -- We assume only two locations
```

```haskell
sendBackSchema :: (KnownSymbol s, KnownSymbol l, All KnownSymbol ls) 
                => Proxy s -> String @ s -> NP Proxy (l : ls) -> Choreo IO ()
sendBackSchema s tog (l :* ls) = do 
  tog' <- (s, tog) ~> l
  locally l $ \un -> putStrLn $ un tog'   -- show the join schema at every client 
  case ls of 
    Nil      -> return () 
    (_ :* _) -> sendBackSchema s tog ls
```

# Next steps 

- Protocol completion 
    - Design a simple DSL to do queries (just counting queries)
    - Design a reification (type-checking) of the query w.r.t. a data schema 

- Enclave connection / engineering efforts  
    - Give a different backend to work on HTTPS for clients and public server
    - Give a different backend to work with the SGX 
    - Attestation for SGX 
    - Test HasChor with the same version of GHC as the runtime of HasTEE

- Generic programming for clients
    - Write a function that reads a file (JSON) with the name of the participants, and public keys
    - Then, write a reification function that given that file it generates a
      generic list of locations `NP Proxy (l : ls)` and runs the protocol. 

- More open-ended questions 
    - How could IFC be used to avoid errors in the protocol? For instance, that
      clients talk to themselves. 
    - Maybe a lattice (maybe a pre-order is enough) between location specifies
      who is allowed to talk to who, given some structure. 
    - Fault-tolerance (advanced feature - if we have time) How would we deal
      with fault-tolerance? For instance, when the network goes down in one
      client. What would be a retry feature? 
