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