# Quick thoughts on HasChor

- At the high-level, it is about wrapping and rewrapping values with different
  phantom types, i.e., `Int @ "alice"` into `Int @ "bob"`.
- A good way to start looking is at `kvs-1` example:

```haskell
-- | `kvs` is a choreography that processes a single request located at the client and returns the response.
kvs ::
  Request @ "client" ->
  IORef State @ "server" ->
  Choreo IO (Response @ "client")
kvs request stateRef = do
  -- send the request to the server
  request' <- (client, request) ~> server
  -- the server handles the response and creates a response
  response <-
    server `locally` \unwrap ->
      handleRequest (unwrap request') (unwrap stateRef)
  -- send the response back to the client
  (server, response) ~> client
```

it does pretty much what HasTEE does in terms of programming model. The difference is that between client and server you send datatypes values

```haskell
data Request = Put String String | Get String deriving (Show, Read)
```

they need to be *fully applied* before they get sent, so perhaps that is a nice way to avoid all the type-classes magic that HasTEE does.

Note from Robert: we don't actually do that much typeclass magic, and we also enforce that functions are fully applied before we invoke the enclave.
We can not serialize and transmit functions, so they must be fully applied.
This `data Request` belongs to one of their examples. Whereas we require a `Binary` instance to communicate, they require `(Show a, Read a)` to do the same thing. It is essentially the same solution, but depending on the instance I guess that `Binary` may be more space efficient and faster.

- We should ignore conditions for the moment, i.e., the constructor cond in
  HasChor So things that we could explore.

## Code splitting 

HasChor indeed compiles into different pieces of code. If we looked into
`Choreo.hs`, we can see the part where local computations are only compile to
the right projection. So, when compiling, you indicate the location by the
command line from cabal. 

```haskell
    handler (Local l m)
      | toLocTm l == l' = wrap <$> run (m unwrap)  
      | otherwise       = return Empty
```

If we are compiling `l'` and that is the location of the local computation, then you produce 
 
```haskell
wrap <$> run (m unwrap)
-- == 
Wrap $ Run (m unwrap)
```

otherwise, that code becomes 

```haskell
return Empty 
```

Robert: This happens at runtime and not compile time, so the compiled program (the executable) has to keep the whole choreography around, as you don't yet know which partition you wish to project. Abi and I tried to hade a secret string on one of the locations, and we verified by disassembling the code that the secret string is not compiled away, and that it ends up in the final executable. We also verified that they are not partitioned by compiling the program just once, but still executing a choreography that involves four parties. You just run the executable with different command-line arguments to indicate which partition you wish to project.

## Sending nested location-decorated values or computations

```haskell

p1 :: (Int @ "person1")
p1 = wrap 42 

nested :: (Int @ "person1") @ "person1"
nested = wrap p1 
```

However, that will not work since `(~~>)` and `(~>)` have a `Show a` and `Read
a` constraint. So, such constrains played a role similar to `Binary a` in
HasTEE.

## Simple protocol for the clean-room DSL 


### Actors

- Public server (responsible of the aggrement of data + analytics)
- Secret server (the one doing the aggregations and collecting all the data)
- Two hostpitals p1, and p2 

### Protocol

```haskell 
    p1: sch1 :: DataSchema -> PublicServer 
    p2: sch2 :: DataSchema -> PublicServer 

    PublicServer: (sch1,sch2) -> p1 
    PublicServer: (sch1,sch2) -> p2     

    -- How to aggregate the schemas can be done in many ways.
    p1: (f: (sch1 + sch2) -> Result1) -> PublicServer   
    p2: (g: (sch1 + sch2) -> Result2) -> PublicServer 

    PublicServer: [f,g] -> SecretServer 

    p1 :: data1 :: sch1 -> SecretServer 
    p2 :: data2 :: sch2 -> SecretServer 

    SecretSever: Result1 -> p1 
    SecretSever: Result2 -> p2 
```


## Ideas to try

1. How do we use all the proper setups using HasChor, i.e., how do we split and enforce that secret are stored in the enclave vs. the client.
2. We should write a secure data aggregation (without Differential Privacy)
   protocol, i.e., 3 clients send their income to the server, and the server
   returns their average.
3. Take the example above and try it to make it work for n-clients. Hopefully,
   using Sum-of-Product hacks.
4. We can conceive a conditional that only runs in the server and does not
   communicate which branch it takes, so protecting secrets. Question: how do
   we know when it is a regular branch and this special one? One option is to
   add another label to values, so that `a @ l @ security` indicates a value a
   at location `l` with security level security.

## Robert comments

They have a slightly different workflow than ours. Whereas our enclave assumes the role of a server, with the client leading the computation,
hasChor allows the different programs to run as equals, with any program being able to send a message to any other program. Because they do it
like this, they need to broadcasting `cond` operator to make sure that they are all aware of which branch their siblings took and what send/recv to
match.

Whereas we split our programs at compile time (digging out the stuff not relevant to a particular program), they pass in a runtime value to choose
which branch to take. This means that **all code exists on all endpoints**. This is not good for security, where you don't want the secure code to
exist on the non-secure client.

Ale: Robert, they do split the code too. See my updated comment above. 

We use two monads to indicate location, but they parameterised values with phantom types to do this. This is a nice generalization, but the compile
time element is still missing from this. We would still wish to physically partition the applications, not just combine several in a
multi-choice wrapper.

If this work is supposed to enhance hastee we **have** to make sure that
1. we can separate the code for the different programs, at compile time
2. we don't broadcast cond branches from sensitive programs



Username: 52783654
Password: 91995
