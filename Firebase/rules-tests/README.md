# Firestore rules-tesztek

Emulátoron futnak (Java 21 kell hozzá), az éles `summit-14b74` projekthez
nem nyúlnak — a `demo-` előtagú projekt-ID-hoz belépés sem kell.

```bash
cd Firebase/rules-tests && npm install && cd ..
firebase emulators:exec --only firestore --project demo-summit "npm --prefix rules-tests test"
```
