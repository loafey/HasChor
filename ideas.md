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

We use two monads to indicate location, but they parameterised values with phantom types to do this. This is a nice generalization, but the compile
time element is still missing from this. We would still wish to physically partition the applications, not just combine several in a
multi-choice wrapper.

If this work is supposed to enhance hastee we **have** to make sure that
1. we can separate the code for the different programs, at compile time
2. we don't broadcast cond branches from sensitive programs
