# Test the `todo` command

## Simple type-changing update.

```unison
x = 1
useX = x + 10

type MyType = MyType Nat
useMyType = match MyType 1 with
  MyType a -> a + 10
```

Perform a type-changing update so dependents are added to our update frontier.

```unison
x = -1

type MyType = MyType Text
```

```ucm
.simple> update.old

  ⍟ I've updated these names to your new definition:
  
    type MyType
    x : Int

.simple> todo

  🚧
  
  The namespace has 2 transitive dependent(s) left to upgrade.
  Your edit frontier is the dependents of these definitions:
  
    type #vijug0om28
    #gjmq673r1v : Nat
  
  I recommend working on them in the following order:
  
  1. useMyType : Nat
  2. useX      : Nat
  
  

```
## A merge with conflicting updates.

```unison
x = 1
type MyType = MyType
```

Set up two branches with the same starting point.

Update `x` to a different term in each branch.

```unison
x = 2
type MyType = MyType Nat
```



🛑

The transcript failed due to an error in the stanza above. The error is:


  
    ❓
    
    I couldn't resolve any of these symbols:
    
        2 | type MyType = MyType Nat
    
    
    Symbol   Suggestions
             
    Nat      No matches
  

