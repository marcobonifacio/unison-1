# Test that the options selector for fuzzy finding is working as expected for different argument types.

If an argument is required but doesn't have a fuzzy resolver, the command should just print the help.


```ucm
-- The second argument of move.term is a 'new-name' and doesn't have a fuzzy resolver
.> move.term

`move.term foo bar` renames `foo` to `bar`.

```
If a fuzzy resolver doesn't have any options available it should print a message instead of
opening an empty fuzzy-select.

```ucm
  ☝️  The namespace .empty is empty.

.empty> view

⚠️

Sorry, I was expecting an argument for the definition to view, and I couldn't find any to suggest to you. 😅

```
```unison
optionOne = 1

nested.optionTwo = 2

lib.dep.defnInLib = 3

lib.dep.lib.tdep.defnInTransitiveDep = 4
```

Definition args

```ucm
  ☝️  The namespace . is empty.

.> add

  ⍟ I've added these definitions:
  
    lib.dep.defnInLib                    : ##Nat
    lib.dep.lib.tdep.defnInTransitiveDep : ##Nat
    nested.optionTwo                     : ##Nat
    optionOne                            : ##Nat

.> debug.fuzzy-options view _

  Select a definition to view:
    * lib.dep.defnInLib
    * optionOne
    * nested.optionTwo

.> debug.fuzzy-options edit _

  Select a definition to edit:
    * optionOne
    * nested.optionTwo

```
Namespace args

```ucm
.> debug.fuzzy-options find-in _

  Select a namespace:
    * lib
    * lib.dep
    * nested

```
Project Branch args

```ucm
.> project.create-empty myproject

  🎉 I've created the project myproject.

  🎨 Type `ui` to explore this project's code in your browser.
  🔭 Discover libraries at https://share.unison-lang.org
  📖 Use `help-topic projects` to learn more about projects.
  
  Write your first Unison code with UCM:
  
    1. Open scratch.u.
    2. Write some Unison code and save the file.
    3. In UCM, type `add` to save it to your new project.
  
  🎉 🥳 Happy coding!

myproject/main> branch mybranch

  Done. I've created the mybranch branch based off of main.
  
  Tip: To merge your work back into the main branch, first
       `switch /main` then `merge /mybranch`.

.> debug.fuzzy-options switch _

  Select a project or branch to switch to:
    * myproject/main
    * myproject/mybranch
    * myproject

```
