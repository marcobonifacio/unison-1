#### Big list crash

Big lists have been observed to crash, while in the garbage collection step.

```unison
unique type Direction = U | D | L | R

x = [(R,1005),(U,563),(R,417),(U,509),(L,237),(U,555),(R,397),(U,414),(L,490),(U,336),(L,697),(D,682),(L,180),(U,951),(L,189),(D,547),(R,697),(U,583),(L,172),(D,859),(L,370),(D,114),(L,519),(U,829),(R,389),(U,608),(R,66),(D,634),(L,320),(D,49),(L,931),(U,137),(L,349),(D,689),(L,351),(D,829),(R,819),(D,138),(L,118),(D,849),(R,230),(U,858),(L,509),(D,311),(R,815),(U,217),(R,359),(U,840),(R,77),(U,230),(R,361),(U,322),(R,300),(D,646),(R,348),(U,815),(R,793),(D,752),(R,967),(U,128),(R,948),(D,499),(R,359),(U,572),(L,566),(U,815),(R,630),(D,290),(L,829),(D,736),(R,358),(U,778),(R,891),(U,941),(R,544),(U,889),(L,920),(U,913),(L,447),(D,604),(R,538),(U,818),(L,215),(D,437),(R,447),(U,576),(R,452),(D,794),(R,864),(U,269),(L,325),(D,35),(L,268),(D,639),(L,101),(U,777),(L,776),(U,958),(R,105),(U,517),(R,667),(D,423),(R,603),(U,469),(L,125),(D,919),(R,879),(U,994),(R,665),(D,377),(R,456),(D,570),(L,685),(U,291),(R,261),(U,846),(R,840),(U,418),(L,974),(D,270),(L,312),(D,426),(R,621),(D,334),(L,855),(D,378),(R,694),(U,845),(R,481),(U,895),(L,362),(D,840),(L,712),(U,57),(R,276),(D,643),(R,566),(U,348),(R,361),(D,144),(L,287),(D,864),(L,556),(U,610),(L,927),(U,322),(R,271),(D,90),(L,741),(U,446),(R,181),(D,527),(R,56),(U,805),(L,907),(D,406),(L,286),(U,873),(L,79),(D,280),(L,153),(D,377),(R,253),(D,61),(R,475),(D,804),(R,788),(U,393),(L,660),(U,314),(R,489),(D,491),(L,234),(D,712),(L,253),(U,651),(L,777),(D,726),(R,146),(U,47),(R,630),(U,517),(R,226),(U,624),(L,834),(D,153),(L,513),(U,799),(R,287),(D,868),(R,982),(U,390),(L,296),(D,373),(R,9),(U,994),(R,105),(D,673),(L,657),(D,868),(R,738),(D,277),(R,374),(U,828),(R,860),(U,247),(R,484),(U,986),(L,723),(D,847),(L,578),(U,487),(L,51),(D,865),(L,328),(D,199),(R,812),(D,726),(R,355),(D,463),(R,761),(U,69),(R,508),(D,753),(L,81),(D,50),(L,345),(D,66),(L,764),(D,466),(L,975),(U,619),(R,59),(D,788),(L,737),(D,360),(R,14),(D,253),(L,512),(D,417),(R,828),(D,188),(L,394),(U,212),(R,658),(U,369),(R,920),(U,927),(L,339),(U,552),(R,856),(D,458),(R,407),(U,41),(L,930),(D,460),(R,809),(U,467),(L,410),(D,800),(L,135),(D,596),(R,678),(D,4),(L,771),(D,637),(L,876),(U,192),(L,406),(D,136),(R,666),(U,730),(R,711),(D,291),(L,586),(U,845),(R,606),(U,2),(L,228),(D,759),(R,244),(U,946),(R,948),(U,160),(R,397),(U,134),(R,188),(U,850),(R,623),(D,315),(L,219),(D,450),(R,489),(U,374),(R,299),(D,474),(L,767),(D,679),(L,160),(D,403),(L,708)]
```

```ucm

  Loading changes detected in scratch.u.

  I found and typechecked these definitions in scratch.u. If you
  do an `add` or `update`, here's how your codebase would
  change:
  
    ⍟ These new definitions are ok to `add`:
    
      type Direction
      x : [(Direction, Nat)]

```