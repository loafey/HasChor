

Samuel, du måste bygga den nya GHC'n som beskrivs i issuet jag länkade.

Sen hoppar du in i examples/tricky/main och ändrar `compileFor x ...` till `compileFor 1 ...` och kör `cabal run tricky` i en terminal.
Sen ändrar du `1` till `0` och kör samma i en annan terminal.

Du ska nu se massa output i dina terminaler. Detta indikerar att de två programmer kontaktar varandra :) Trots att `alternate` är både location-polymorphic och rekursiv, vilket vi inte kunde klara av innan.

Om du kommenterar ut `specialise`-reglerna så kommer det inte fungera längre.