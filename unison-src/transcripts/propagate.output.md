# Propagating type edits

We introduce a type `Foo` with a function dependent `fooToInt`.

```unison
unique type Foo = Foo

fooToInt : Foo -> Int
fooToInt _ = +42
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      type Foo
      fooToInt : Foo -> Int

```
And then we add it.

```ucm
.subpath> add

  ⍟ I've added these definitions:
  
    type Foo
    fooToInt : Foo -> Int

.subpath> find.verbose

  1. -- #uj8oalgadr2f52qloufah6t8vsvbc76oqijkotek87vooih7aqu44k20hrs34kartusapghp4jmfv6g1409peklv3r6a527qpk52soo
     type Foo
     
  2. -- #uj8oalgadr2f52qloufah6t8vsvbc76oqijkotek87vooih7aqu44k20hrs34kartusapghp4jmfv6g1409peklv3r6a527qpk52soo#0
     Foo.Foo : Foo
     
  3. -- #j6hbm1gc2ak4f46b6705q90ld4bmhoi8etq2q45j081i9jgn95fvk3p6tjg67e7sm0021035i8qikmk4p6k845l5d00u26cos5731to
     fooToInt : Foo -> Int
     
  

.subpath> view fooToInt

  fooToInt : Foo -> Int
  fooToInt _ = +42

```
Then if we change the type `Foo`...

```unison
unique type Foo = Foo | Bar
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These names already exist. You can `update` them to your
      new definition:
    
      type Foo

```
and update the codebase to use the new type `Foo`...

```ucm
.subpath> update.old

  ⍟ I've updated these names to your new definition:
  
    type Foo

```
... it should automatically propagate the type to `fooToInt`.

```ucm
.subpath> view fooToInt

  fooToInt : Foo -> Int
  fooToInt _ = +42

.> cd .

```
### Preserving user type variables

We make a term that has a dependency on another term and also a non-redundant
user-provided type signature.

```unison
preserve.someTerm : Optional foo -> Optional foo
preserve.someTerm x = x

preserve.otherTerm : Optional baz -> Optional baz
preserve.otherTerm y = someTerm y
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      preserve.otherTerm : Optional baz -> Optional baz
      preserve.someTerm  : Optional foo -> Optional foo

```
Add that to the codebase:

```ucm
.subpath> add

  ⍟ I've added these definitions:
  
    preserve.otherTerm : Optional baz -> Optional baz
    preserve.someTerm  : Optional foo -> Optional foo

.> cd .

```
Let's now edit the dependency:

```unison
preserve.someTerm : Optional x -> Optional x
preserve.someTerm _ = None
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      preserve.someTerm : Optional x -> Optional x

```
Update...

```ucm
.subpath> update.old

  ⍟ I've updated these names to your new definition:
  
    preserve.someTerm : Optional x -> Optional x

.> cd .

```
Now the type of `someTerm` should be `Optional x -> Optional x` and the
type of `otherTerm` should remain the same.

```ucm
.subpath> view preserve.someTerm

  preserve.someTerm : Optional x -> Optional x
  preserve.someTerm _ = None

.subpath> view preserve.otherTerm

  preserve.otherTerm : Optional baz -> Optional baz
  preserve.otherTerm y = someTerm y

```
### Propagation only applies to the local branch

Cleaning up a bit...

```ucm
.> delete.namespace subpath

  Done.

  ☝️  The namespace .subpath.lib is empty.

.subpath.lib> builtins.merge

  Done.

```
Now, we make two terms, where one depends on the other.

```unison
one.someTerm : Optional foo -> Optional foo
one.someTerm x = x

one.otherTerm : Optional baz -> Optional baz
one.otherTerm y = someTerm y
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      one.otherTerm : Optional baz -> Optional baz
      one.someTerm  : Optional foo -> Optional foo

```
We'll make two copies of this namespace.

```ucm
.subpath> add

  ⍟ I've added these definitions:
  
    one.otherTerm : Optional baz -> Optional baz
    one.someTerm  : Optional foo -> Optional foo

.subpath> fork one two

  Done.

.> cd .

```
Now let's edit one of the terms...

```unison
someTerm : Optional x -> Optional x
someTerm _ = None
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      someTerm : Optional x -> Optional x

```
... in one of the namespaces...

```ucm
.subpath.one> update.old

  ⍟ I've updated these names to your new definition:
  
    someTerm : #nirp5os0q6 x -> #nirp5os0q6 x

```
The other namespace should be left alone.

```ucm
.subpath> view two.someTerm

  two.someTerm : Optional foo -> Optional foo
  two.someTerm x = x

```
