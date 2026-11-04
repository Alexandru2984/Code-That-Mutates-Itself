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

## Extensii ulterioare, fără a le prezenta ca livrate

- Replays și serii istorice persistente, cu retenție și buget de stocare.
- Experimente private/sandbox și scenarii educaționale reproductibile.
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
