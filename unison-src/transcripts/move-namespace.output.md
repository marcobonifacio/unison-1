# Tests for `move.namespace`

## Happy path

Create a namespace and add some history to it

```unison
a.termInA = 1
unique type a.T = T
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      type a.T
      a.termInA : Nat

```
```ucm
  ☝️  The namespace .happy is empty.

.happy> add

  ⍟ I've added these definitions:
  
    type a.T
    a.termInA : Nat

```
```unison
a.termInA = 2
unique type a.T = T1 | T2
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These names already exist. You can `update` them to your
      new definition:
    
      type a.T
      a.termInA : Nat

```
```ucm
.happy> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

```
Should be able to move the namespace, including its types, terms, and sub-namespaces.

```ucm
.happy> move.namespace a b

  Done.

.happy> ls b

  1. T       (type)
  2. T/      (2 terms)
  3. termInA (##Nat)

.happy> history b

  Note: The most recent namespace hash is immediately below this
        message.
  
  ⊙ 1. #4j747vnmdk
  
    + Adds / updates:
    
      T T.T1 T.T2 termInA
    
    - Deletes:
    
      T.T
  
  □ 2. #r71j4144fe (start of history)

```
## Namespace history


Create some namespaces and add some history to them

```unison
a.termInA = 1
b.termInB = 10
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      a.termInA : Nat
      b.termInB : Nat

```
```ucm
  ☝️  The namespace .history is empty.

.history> add

  ⍟ I've added these definitions:
  
    a.termInA : Nat
    b.termInB : Nat

```
```unison
a.termInA = 2
b.termInB = 11
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These names already exist. You can `update` them to your
      new definition:
    
      a.termInA : Nat
      b.termInB : Nat

```
```ucm
.history> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

```
Deleting a namespace should not leave behind any history,
if we move another to that location we expect the history to simply be the history
of the moved namespace. 

```ucm
.history> delete.namespace b

  Done.

.history> move.namespace a b

  Done.

-- Should be the history from 'a'
.history> history b

  Note: The most recent namespace hash is immediately below this
        message.
  
  ⊙ 1. #j0cjjqepb3
  
    + Adds / updates:
    
      termInA
  
  □ 2. #m8smmmgjso (start of history)

-- Should be empty
.history> history a

  ☝️  The namespace .history.a is empty.

```
## Moving over an existing branch 

Create some namespace and add some history to them

```unison
a.termInA = 1
b.termInB = 10
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      a.termInA : Nat
      b.termInB : Nat

```
```ucm
  ☝️  The namespace .existing is empty.

.existing> add

  ⍟ I've added these definitions:
  
    a.termInA : Nat
    b.termInB : Nat

```
```unison
a.termInA = 2
b.termInB = 11
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These names already exist. You can `update` them to your
      new definition:
    
      a.termInA : Nat
      b.termInB : Nat

```
```ucm
.existing> update

  Okay, I'm searching the branch for code that needs to be
  updated...

  Done.

.existing> move.namespace a b

  ⚠️
  
  A branch existed at the destination: b so I over-wrote it.
  
  Tip: You can use `undo` or `reflog` to undo this change.

  Done.

```
## Moving the Root 

I should be able to move the root into a sub-namespace

```ucm
-- Should request confirmation
.> move.namespace . .root.at.path

  ⚠️
  
  Moves which affect the root branch cannot be undone, are you sure?
  Re-run the same command to proceed.

.> move.namespace . .root.at.path

  Done.

.> ls

  1. root/ (630 terms, 89 types)

.> history

  Note: The most recent namespace hash is immediately below this
        message.
  
  
  
  □ 1. #4ussajn1fc (start of history)

```
```ucm
.> ls .root.at.path

  1. builtin/  (625 terms, 88 types)
  2. existing/ (1 term)
  3. happy/    (3 terms, 1 type)
  4. history/  (1 term)

.> history .root.at.path

  Note: The most recent namespace hash is immediately below this
        message.
  
  ⊙ 1. #sm3e1ff3o3
  
    - Deletes:
    
      existing.b.termInB
    
    > Moves:
    
      Original name      New name
      existing.a.termInA existing.b.termInA
  
  ⊙ 2. #r9d6ogmf6k
  
    + Adds / updates:
    
      existing.a.termInA existing.b.termInB
    
    = Copies:
    
      Original name     New name(s)
      happy.b.termInA   existing.a.termInA
      history.b.termInA existing.a.termInA
  
  ⊙ 3. #i3nbnio6so
  
    + Adds / updates:
    
      existing.a.termInA existing.b.termInB
  
  ⊙ 4. #38b1mbqlu9
  
    > Moves:
    
      Original name     New name
      history.a.termInA history.b.termInA
  
  ⊙ 5. #8unpdmu968
  
    - Deletes:
    
      history.b.termInB
  
  ⊙ 6. #6keeqlbr7c
  
    + Adds / updates:
    
      history.a.termInA history.b.termInB
    
    = Copies:
    
      Original name   New name(s)
      happy.b.termInA history.a.termInA
  
  ⊙ 7. #otsrjrs2el
  
    + Adds / updates:
    
      history.a.termInA history.b.termInB
  
  ⊙ 8. #irbtol8piu
  
    > Moves:
    
      Original name   New name
      happy.a.T       happy.b.T
      happy.a.T.T1    happy.b.T.T1
      happy.a.T.T2    happy.b.T.T2
      happy.a.termInA happy.b.termInA
  
  ⊙ 9. #s3ppk1c8qc
  
    + Adds / updates:
    
      happy.a.T happy.a.T.T1 happy.a.T.T2 happy.a.termInA
    
    - Deletes:
    
      happy.a.T.T
  
  ⊙ 10. #8qf0jit35s
  
    + Adds / updates:
    
      happy.a.T happy.a.T.T happy.a.termInA
  
  There's more history before the versions shown here. Use
  `history #som3n4m3space` to view history starting from a given
  namespace hash.
  
  ⠇
  
  ⊙ 11. #u4v65n4qcl
  

```
I should be able to move a sub namespace _over_ the root.

```ucm
-- Should request confirmation
.> move.namespace .root.at.path.happy .

  ⚠️
  
  Moves which affect the root branch cannot be undone, are you sure?
  Re-run the same command to proceed.

.> move.namespace .root.at.path.happy .

  Done.

.> ls

  1. b/ (3 terms, 1 type)

.> history

  Note: The most recent namespace hash is immediately below this
        message.
  
  ⊙ 1. #ur0jj0uuhu
  
    + Adds / updates:
    
      b.T b.T.T1 b.T.T2 b.termInA
  
  ⊙ 2. #8a0jmdflfd
  
    - Deletes:
    
      a.T a.T.T1 a.T.T2 a.termInA
  
  ⊙ 3. #3sbe4c0ql9
  
    + Adds / updates:
    
      a.T a.T.T1 a.T.T2 a.termInA
    
    - Deletes:
    
      a.T.T
  
  □ 4. #kfuu64io6v (start of history)

```
```ucm
-- should be empty
.> ls .root.at.path.happy

  nothing to show

.> history .root.at.path.happy

  ☝️  The namespace .root.at.path.happy is empty.

```
