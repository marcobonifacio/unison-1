
```unison
f : '{} Nat
f _ = 5

fc : '{IO, Exception} Nat
fc = unsafe.coerceAbilities f

main : '{IO, Exception} [Result]
main _ =
  n = !fc
  if n == 5 then [Ok ""] else [Fail ""]
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      f    : 'Nat
      fc   : '{IO, Exception} Nat
      main : '{IO, Exception} [Result]

```
```ucm
.> find unsafe.coerceAbilities

  1. builtin.unsafe.coerceAbilities : (a ->{e1} b) -> a -> b
  

.> add

  ⍟ I've added these definitions:
  
    f    : 'Nat
    fc   : '{IO, Exception} Nat
    main : '{IO, Exception} [Result]

.> io.test main

    New test results:
  
  ◉ main   
  
  ✅ 1 test(s) passing
  
  Tip: Use view main to view the source of a test.

```
