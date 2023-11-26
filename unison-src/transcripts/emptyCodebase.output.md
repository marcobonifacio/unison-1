# The empty codebase

The Unison codebase, when first initialized, contains no definitions in its namespace.

Not even `Nat` or `+`!

BEHOLD!!!

```ucm
.> ls

  nothing to show

```
Technically, the definitions all exist, but they have no names. `builtins.merge` brings them into existence, under the current namespace:

```ucm
  ☝️  The namespace .foo is empty.

.foo> builtins.merge

  Done.

.foo> ls

  1. builtin/ (452 terms, 70 types)

```
And for a limited time, you can get even more builtin goodies:

```ucm
.foo> ls

  1. builtin/ (452 terms, 70 types)

```
More typically, you'd start out by pulling `base.
