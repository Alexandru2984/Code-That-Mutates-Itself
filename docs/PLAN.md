# Evolving Minds — plan de produs

Data de pornire: 2026-11-04. Obiectiv: un observator de viață artificială sigur,
ușor de înțeles, interesant de explorat și utilizabil pe telefon.

## Ordinea livrării

1. **Audit și inventar.** Cod, dependențe, sesiuni LiveView, suprafețe publice,
   snapshoturi, proxy și serviciul real. Documentăm constatările și limitele.
2. **Securitate.** Actualizări pentru advisories, separarea sesiunilor public/admin,
   autorizare la mount și la evenimente, revocare la schimbarea credențialelor,
   limitare comună între conexiuni, validarea comenzilor, plafon atomic pentru
   populație, cookie Secure, payloaduri limitate și restaurare validată.
3. **Observatorul.** Layout adaptat mobilului, text lizibil, navigare coerentă,
   căutare după nume și ID, filtre după trib/stare, sortări suplimentare,
   favorite persistente local, comparație între minți, pauză a observației,
   linkuri către dosare și feedback pentru conexiune.
4. **Explorare și înțelegere.** Hartă interactivă a trăsăturilor, clasamente,
   rezumatul lumii, feed filtrabil, genealogii căutabile, ghid pentru vizitatori,
   export JSON al datelor publice și dialoguri accesibile cu tastatura.
5. **Operare și livrare.** Script de deploy corect pentru această instalare,
   backup înainte de restart, verificare de readiness, instrucțiuni de rollback,
   configurație proxy versionată și verificări după restart.
6. **SEO și CI, la final.** Titluri și descrieri pe pagină, canonical, metadate
   sociale, sitemap, robots pentru admin; workflow cu privilegii minime,
   audit de dependențe, build de producție și regresii pentru fluxurile noi.

Fiecare etapă implementată are commit separat, fără coautori sau atribuire către
instrumentele folosite. Testele de regresie relevante se execută odată cu fixul;
extinderea infrastructurii CI și SEO rămâne la final.

## Livrat în această sesiune

| Etapă | Rezultat verificat |
| --- | --- |
| Audit | Inventar real al serviciului/proxyului, audit Hex și scanare a istoricului; cheia de semnare expusă a fost identificată și revocată. |
| Securitate | Sesiuni admin separate, verificări la mount și evenimente, revocare, limite între taburi/conexiuni, plafon în motor, cookie Secure, payloaduri limitate și restore validat. Admin fără scripturi externe de analytics. |
| Observator | Design nou adaptat mobilului, filtre combinate, favorite locale, comparație între trei minți, pauză a observației, dosare cu link direct și dialoguri accesibile din tastatură. |
| Explorare | Hartă de trăsături, rețea socială interactivă, clasamente, distribuții, generații, jurnal filtrabil, genealogie cu căutare/paginare și export public JSON. Ordinea DOM urmează corect sortarea live. |
| Laborator | Patru scenarii private, seed reproductibil, mediu/trăsături/mutații configurabile, viteză, pas individual, inspector, grafice și jurnal. Salvare locală, export și import JSON validat, cu reluarea generatorului aleator. |
| Operare | Release-uri izolate, backup la deploy, oprire SIGTERM controlată, readiness, rollback și verificare HTTP publică. Backupul local existent a fost verificat și pornit într-o instanță izolată. |
| SEO și CI | Canonical, metadate sociale, imagine de partajare, sitemap pentru cele trei pagini, robots și noindex pentru admin. Workflow cu SHA-uri fixe, privilegii minime, audituri, build de producție și teste Chromium. |

Funcționalitățile sunt publicate pe `https://elixir.micutu.com`, inclusiv `/lab`.
Workflowul GitHub este comis; rularea sa pe infrastructura GitHub are loc după
sincronizarea repository-ului remote. Comenzile și testele au trecut local.

## Următoarele priorități

1. Alerte externe pentru readiness, snapshoturi vechi, restarturi și abuz de autentificare.
2. Exercițiu complet de reconstruire a infrastructurii pe alt host; backupul extern este acum activ și verificat.
3. Test de capacitate într-un mediu separat și bugete comune dacă se adaugă noduri BEAM.

Continuare: runtime-ul și backupul local au fost mutate pe `evolving-minds`, fără
grupuri privilegiate; release-urile sunt read-only. Offsite-ul rulează separat ca
`evolving-minds-offsite`, cu un subset privat al configurației rclone și fără a
expune credențialele procesului web. Copia criptată a fost recuperată și pornită
într-o instanță izolată; datele de producție nu au fost înlocuite.

Administrarea are acum un layout adaptat mobilului și trei indicatoare pentru
snapshot, backup local și transfer criptat. Stările lipsă, vechi sau invalide sunt
vizibile; această verificare din aplicație nu înlocuiește alertele externe.

Laboratorul păstrează șase experimente denumite și compară trei snapshoturi cu
grafice de populație și export CSV. Salvările vechi sunt recuperate fără a le
suprascrie; ștergerea are Undo. Datele corupte și biblioteca plină nu provoacă
ștergeri automate. Numele sunt afișate ca text, iar CSV-ul neutralizează formulele.

Trei misiuni ghidate urmăresc cooperarea, supraviețuirea în foamete și diversitatea.
Obiectivele trebuie îndeplinite simultan, iar realizările sunt locale, fără clasament
competitiv. Linkurile de partajare reproduc seedul și condițiile inițiale la pasul
zero; exportul JSON păstrează în continuare starea curentă a experimentului.

Dynasties prezintă familiile cu cei mai mulți membri vii și permite explorarea
întregii descendențe păstrate, împreună cu filtrele existente. Ancestorii eliminați
prin retenție sunt semnalați explicit. Rezolvarea rădăcinilor este memoizată,
ciclurile vechi nu blochează pagina, iar structura arborelui se calculează o dată
la încărcare/refresh în loc să fie reconstruită la fiecare căutare.

## Extensii ulterioare, fără a le prezenta ca livrate

- Replays și serii istorice persistente, cu retenție și buget de stocare.
- Mai multe modele educaționale și scenarii dinamice între epoci.
- Misiuni de observație și realizări locale, fără a altera lumea comună.
- Povești despre dinastii, migrații și evoluția strategiilor între epoci.
- Partajare de dosare cu imagini sociale generate din datele publice.
- Statistici pe trib, comparații între epoci, corelații și export CSV.
- Traducere română/engleză cu un catalog de traduceri complet.
- Mod PWA pentru ghid și favorite offline; lumea live necesită conexiune.
- Conturi, colecții sincronizate și notificări numai după proiectarea identității,
  consimțământului, retenției și mecanismelor anti-abuz.
- Monetizare/donații fără avantaje care distrug selecția naturală.

## Criterii de acceptare

- Datele lumii existente supraviețuiesc deployului.
- Un vizitator public nu poate monta sau opera LiveView-uri administrative.
- Reconectarea nu resetează bugetele acțiunilor publice; populația are plafon în motor.
- Snapshoturile invalide sunt respinse înaintea modificării lumii.
- Fără scroll orizontal al paginii la 360px; controale utilizabile la atingere.
- Funcțiile noi sunt reale și au stări goale/erori, fără elemente decorative inactive.
- Testele relevante, buildul și auditul de dependențe sunt raportate cu rezultatul real.
- Se diferențiază explicit modificările comise de cele activate în producție.
