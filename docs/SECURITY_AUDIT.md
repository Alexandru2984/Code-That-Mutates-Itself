# Audit de securitate — Evolving Minds

Data: 2026-11-04. Audit de cod și configurație locală, verificări HTTP neintruzive.
Nu s-au făcut teste de epuizare de resurse sau atacuri destructive în producție.

## Inventar inițial, înainte de remedieri

- Elixir 1.18.3 / OTP 27; Phoenix LiveView; simulare fără bază de date SQL.
- Serviciu activ: `evolving-minds-canary.service`, utilizator `micu`, port 4001 pe loopback.
- Nginx deservește `elixir.micutu.com`; Cloudflare este în fața originului.
- systemd existent are ProtectSystem=strict, NoNewPrivileges, UMask=0077,
  limite de memorie/procese și acces de scriere limitat la directorul de date.
- Snapshotul existent are permisiuni 0600. Backup zilnic local prin systemd;
  documentația veche despre cron/rclone nu descrie această instalare.
- Baseline: 45 teste core și 31 web trec; există două avertismente în teste.

## Constatări inițiale

| ID | Prioritate | Constatare și impact | Remediere |
| --- | --- | --- | --- |
| SEC-01 | Ridicată | `mix hex.audit` raportează advisories pentru Phoenix, LiveView, phoenix_html, Bandit, hpax, Plug, plug_crypto și lazy_html; Plug 1.20.1 este retras. Impactul diferă: HTTP/2 la Bandit este în spatele proxyului, iar lazy_html este doar pentru teste. | Actualizare compatibilă și audit repetat; lockfile comis. |
| SEC-02 | Ridicată | Publicul și admin folosesc sesiunea LiveView implicită. Plug.BasicAuth acoperă HTTP, dar admin nu are control la mount/eveniment. Navigarea LiveView poate sări peste pipeline-ul HTTP. | live_session separat, dovadă de autentificare în sesiunea semnată, on_mount inclusiv dashboard, verificare la acțiuni și revocare. |
| SEC-03 | Medie | Limitarea injecțiilor și nașterilor există doar în assigns per LiveView. Reconectarea sau alt tab resetează limita. | Bugete comune în proces supravegheat, identitate derivată din IP prin proxy de încredere, buget global și memorie limitată. |
| SEC-04 | Medie | Limita populației se verifică în UI, folosind un snapshot care poate fi vechi; admin poate cere orice count. | max_children în DynamicSupervisor, input cu interval fix, tratarea erorilor de capacitate. |
| SEC-05 | Medie | Cookie de sesiune fără atribut Secure în răspunsul HTTPS public observat. | Secure în producție; păstrăm HttpOnly/SameSite. |
| SEC-06 | Medie, acces local necesar | binary_to_term fără :safe, fără limită de fișier/decompresie și fără validarea structurii. Un snapshot modificat/corupt poate provoca alocări sau crashuri la boot. Nu există upload public de snapshoturi. | Decodare sigură, limite, schemă și verificare completă înainte de restore. |
| SEC-07 | Medie | Parametrii count și epoch sunt convertiți prin funcții care ridică excepții; evenimentele malformate pot termina sesiunea. | Allowlist și validare de tip/interval, răspuns controlat. |
| SEC-08 | Medie | Parser multipart activ deși nu există uploaduri; limite implicite mari și socket fără limită explicită de payload. | Reducerea parserelor și limitelor, limite de transport. |
| SEC-09 | Critică | Scanarea ulterioară a 335 de bloburi istorice a găsit fostul `evolving_minds/.env.prod`; SECRET_KEY_BASE de acolo coincide cu cheia runtime. Eliminarea fișierului în iunie nu a revocat cheia. Semnăturile sesiunilor și tokenurilor puteau fi falsificate de cineva cu acces la acel istoric. | Cheie nouă generată direct în fișierul protejat de runtime, fără afișare; activare la restartul controlat. Istoricul nu se rescrie implicit. Guard CI pentru fișiere de credențiale urmărite și tokenuri comune. |
| OPS-01 | Ridicată pentru deploy | Scriptul și unitatea versionate indică vechiul director/serviciu, nu instalarea activă. Rularea lor ar putea crea un serviciu concurent sau eșua. | Deploy parametrizat pentru unitatea reală, verificări și backup înainte de restart. |
| OPS-02 | Medie | /healthz întoarce mereu ok, chiar dacă procesele simulării lipsesc. | Readiness real, răspuns minimal și 503 la indisponibilitate. |
| OPS-03 | Medie | Verificarea efectivă în browser a LiveDashboard a arătat că bootstrapul inline era blocat de CSP, deși răspunsul HTTP era 200. | Nonce criptografic per răspuns, integrat cu LiveDashboard și păstrat prin Nginx; fără script-src unsafe-inline. Regresie în Chromium. |
| UX-01 | Produs | Header cu lățime minimă cumulată mare, texte de 7–9px, select fără etichete, dialoguri fără focus trap/Escape, lipsesc reconectare și accesibilitate pentru mișcare redusă. | Layout mobil și componente/feedback accesibile. |
| UX-02 | Produs | Căutarea filtrează doar ID, genealogia încarcă întregul arbore, nu există favorite, comparație sau linkuri către un dosar. | Funcții de explorare și structură de navigare. |

## Constatare suplimentară la izolarea backupului

SEC-10, medie, acces local de scriere în arhive necesar: jobul offsite verifica și
redeschidea succesiv calea partajată. Schimbarea fișierului între pași putea face
uploadul să citească alți octeți decât cei validați; checksumul extern accepta și
căi arbitrare din sidecar. Remedierea deschide fișiere regulate cu O_NOFOLLOW,
impune limite de citire/decompresie și un sidecar strict, apoi încarcă exclusiv o
copie verificată din directorul privat al UID-ului offsite. Șase teste de regresie
acoperă inclusiv schimbarea în symlink între selecție și open. Nu este o
vulnerabilitate accesibilă direct printr-un upload web public.

## Puncte solide

HEEx escapează textul; euristicile sunt funcții construite din trăsături, fără eval.
CSRF și verificarea Origin există. ETS protejat, memorii/evenimente limitate,
snapshot prin rename atomic și state store care curăță procesele terminate.
Nu s-au găsit secrete în fișierele urmărite la inspecția inițială; aceasta nu
acoperea istoricul. Scanarea ulterioară a istoricului a identificat SEC-09.
Scanarea pe tipare este limitată și nu dovedește absența altor tipuri de secrete.

## Model de amenințări și limite

Principalele riscuri sunt escaladarea public→admin, DoS pe conexiuni/acțiuni și
alterarea stării persistente prin acces local. Procesul web și backupul local
rulează acum ca `evolving-minds`, iar transferul offsite ca `evolving-minds-offsite`,
fără grupuri privilegiate. Operatorul `micu` păstrează drepturile de deploy;
compromiterea operatorului sau a root rămâne în afara izolării procesului web.

Limitarea aplicației este pentru o singură instanță BEAM; la scalare trebuie
un buget comun între noduri. Un atac distribuit necesită protecții și la edge.
Nu există suficiente date pentru a estima cost financiar, MTTD real sau numărul
vizitatorilor afectați. Verificarea altor domenii nu face parte din acest audit. Restaurarea din
destinația remote aleasă de proprietar a fost testată ulterior într-o instanță izolată.

## Surse tehnice

- Model LiveView: https://phoenix-live-view.hexdocs.pm/security-model.html
- ETF și :safe: https://www.erlang.org/docs/27/apps/erts/erlang.html#binary_to_term/2
- Advisory-urile exacte sunt returnate de `mix hex.audit`; disponibilitatea unui
  patch și relevanța pentru aplicație se verifică la actualizare.

## Starea finală a remedierilor

- SEC-01: Phoenix 1.7.24, LiveView 1.2.13, phoenix_html 3.3.5, Bandit 1.14.1,
  hpax 1.1.0, Plug 1.20.3, plug_crypto 2.2.1 și lazy_html 0.1.14. Auditul Hex
  final nu raportează pachete retrase sau advisories. Auditul npm al dependențelor
  de verificare în browser raportează zero vulnerabilități.
- SEC-02/07: sesiuni LiveView public/admin/dashboard distincte; dovadă semnată de
  autorizare cu expirare, verificări la mount/evenimente și revocare la schimbarea
  credențialelor. Comenzile malformate nu mai termină sesiunea.
- SEC-03/04: ferestre comune pe instanță, identitate din IP prin proxy local de
  încredere, bugete globale pentru acțiuni, plafon de 50 în DynamicSupervisor,
  limită de 10 canale/transport și throttling pentru mounts/evenimente. Nginx
  limitează cereri și conexiuni; rescrie header-ele de identitate.
- SEC-05/08: Secure/HttpOnly/SameSite=Lax confirmate pe răspuns HTTPS; parsere fără
  multipart, limite HTTP/WebSocket de 64 KiB; HTTP/2 dezactivat la backendul local.
- SEC-06: ETF cu `:safe`, maximum 4 MB, ETF comprimat respins, validarea întregii
  structuri înainte de restore; snapshot invalid oprește startupul în loc să fie
  suprascris de o lume nouă. Fișier sincronizat pe disc, mod 0600 și rename atomic.
- SEC-09: cheia din istoricul Git a fost schimbată direct în configurația protejată
  și activată prin restart. Verificare criptografică pe un cookie emis de server:
  cheia istorică este respinsă, cea runtime este acceptată. Secretul nu a fost
  afișat sau comis. Obiectul istoric rămâne, cu o cheie revocată.
- OPS-01/02: deploy separat de release-ul activ, snapshot final după oprire,
  backup, readiness real și rollback. Prima migrare a demonstrat revenirea la
  release-ul anterior când RPC-ul vechi nu a răspuns; următoarele deployuri au
  trecut. systemd folosește SIGTERM pentru oprire și păstrează sandboxul existent.
- Admin nu mai primește scriptul injectat de analytics și are CSP exclusiv pentru
  scripturi/conexiuni proprii. Izolarea și funcționarea LiveDashboard au fost
  verificate prin sesiune autenticată, fără comenzi care modifică lumea.
  Scripturile bootstrap ale LiveDashboard sunt autorizate prin nonce-uri noi la
  fiecare răspuns. Proxyul păstrează politica aplicației pentru admin, cu fallback
  strict pentru erori. Un beacon adăugat ulterior de edge este blocat de această CSP.
- UX-01/02: observator nou, focus trap/Escape, mișcare redusă, formulare etichetate,
  căutare extinsă, favorite, comparație, vizualizări și genealogie paginată.

## Dovezi de verificare

- 49 teste core, 64 teste web, 25 teste JavaScript, 6 teste Python și 20 teste Chromium: **164 trecute**.
  Fluxurile laboratorului au fost reverificate după ajustarea comparațiilor.
- Build de producție și mix release reușite; serviciul activ are readiness 200.
- Pagini verificate la 360, 390, 768, 1440 și 1920 px; fără overflow orizontal.
- Verificate în browser: favorite după reload, comparații/dosare, Escape/focus,
  harta și rețeaua, sortarea DOM după actualizarea energiei, genealogia și laboratorul.
- Laborator: seed/export reproductibil, save/load, import invalid respins fără a
  schimba experimentul, reluare deterministă și pas individual fără conexiune.
  Importul este local, limitat la 500 KB, cu schemă explicită și copiere doar a
  câmpurilor permise. Datele importate sunt inserate prin textContent/Option.
- Biblioteca locală: recuperarea salvării vechi, șase sloturi fără eliminare automată,
  comparații, redenumire și Undo verificate. Numele cu markup rămân text; CSV-ul
  neutralizează formulele și escapează ghilimelele. Datele locale corupte nu sunt
  suprascrise automat. Misiunile sunt realizări educaționale locale, nu scoruri de
  încredere pentru competiții. Linkurile validate reproduc numai condițiile inițiale.
- Accesibilitate: eticheta logo-ului și semantica barei pe triburi corectate;
  pictogramele butoanelor etichetate sunt decorative pentru cititoarele de ecran.
  Scanări axe-core pentru 15 combinații de pagină/stare/lățime fără erori automate
  detectabile. Contrastul peste gradiente și unele pictograme cer verificare umană;
  acest rezultat nu reprezintă o certificare WCAG. Navigarea prin Tab/skip link,
  focusul și Escape au fost verificate separat.
- CI: acțiuni oficiale fixate la SHA, runtime Node 24, credențiale Git nepersistate,
  token cu contents:read și artefacte numai din fixture-urile de browser, cu retenție
  de șapte zile. Etichetele și action.yml au fost verificate upstream; workflowul
  nu a fost rulat pe GitHub în această sesiune.
- Dinastii: filtre combinate pentru o familie, rădăcini absente, cicluri legacy și
  un lanț de 2.000 de înregistrări verificate. Structurile genealogice sunt calculate
  la încărcare/refresh, evitând reconstruirea lor la fiecare schimbare de filtru.
- Runtime dedicat și release-uri read-only verificate în producție. Panoul admin
  afișează trei stări Healthy pentru persistență și copii; cititorul statusului are
  limite de dimensiune și respinge înregistrări invalide sau din viitor.
- Offsite: UID separat, credențiale private, upload/download prin crypt și SHA-256
  verificate; arhiva recuperată a pornit cu succes în izolare. Rollbackul instalării
  a trecut trei scenarii de verificare locală a fișierelor/stării timerului, cu
  apelurile systemd simulate; nu s-a injectat o eroare în jobul de producție.
  După activarea stagingului privat, un nou transfer real din 2026-11-04 15:36 UTC
  a verificat prin download arhiva de 78.429 bytes, cu Result=success. Helperul și
  scriptul instalate sunt root-owned; serviciul web a rămas activ fără restarturi
  automate. Pagini și fluxuri au fost reverificate prin Cloudflare după deploy.
- HTTP public prin Cloudflare: `/`, `/tree`, `/lab`, `/healthz`, robots și sitemap
  funcționale; admin anonim 401, `/.env` și `/.git/config` 403, snapshot public 404.
- Backup local din 2026-11-04: checksum și gzip valide; pornire izolată reușită,
  cu restaurarea a 7 minți și a registrului genealogic de 1.873 înregistrări.
  Lumea live nu a fost înlocuită de acest exercițiu.
- Nginx: configurație validată înainte de reload; numai acest vhost și configurația
  sa specifică au fost modificate. Configurațiile anterioare sunt păstrate pentru rollback.

## Verificări suplimentare pentru laboratorul finalizat

- `/lab` rulează direct în browser și nu emite sesiune de aplicație sau bootstrap
  LiveView. Shellul offline este identic între cereri fără stare de vizitator.
  Laboratorul și shellul au CSP strict și nu primesc transformarea de analytics.
- CacheStorage are o listă de șapte resurse publice, verificată în Chromium după
  cereri reale spre admin/API și după reload offline. Nici HTML-ul live, nici datele
  API nu sunt salvate de worker. Inputul cache-ului omite credențiale, impune tipul,
  versiunea, 1 MB/fișier și un timeout de 15 secunde. Tokenurile în HTML sunt respinse.
- Politica no-cache pentru vechiul worker .js era rescrisă de Cloudflare la patru
  ore. Endpointul canonic fără extensie, cu versiune și directive no-store pentru
  browser/CDN, a fost verificat pe domeniul real. Nu s-au modificat regulile globale
  Cloudflare sau vhosturile altor aplicații.
- Bibliotecile se importă prin merge validat, atomic, cu deduplicare și fără a
  înlocui salvările existente. Coliziunile de ID primesc identități noi. Resetarea
  datelor corupte cere acțiune explicită și permite întâi descărcarea originalului.
- Recuperarea la reload este separată per tab, cu schemă și dimensiune limitate.
  Datele corupte sunt păstrate; quota/accesul blocat nu opresc simulatorul. Un update
  real de worker a fost testat cu checkpoint și restaurarea experimentului în pauză.
- Inspectorul de istoric nu schimbă starea experimentului. Pașii duplicați sunt
  respinși pentru a evita selectarea unor măsurători ambigue. Selectorul temporal,
  graficele și layoutul mobil au trecut testele de regresie și inspecția capturilor.
- Uptime Kuma existent a fost inspectat read-only pentru acest domeniu: nu exista
  un monitor al aplicației. Canalul de notificare a fost cerut proprietarului și
  rămâne neales; nu se afirmă că alertele externe sunt active.

## Riscuri și limite rămase

| Prioritate | Limită reală | Următorul pas |
| --- | --- | --- |
| Rezolvat 2026-11-04 | Copiile sunt acum trimise și în Google Drive criptat, într-un prefix separat, la șase ore, cu retenție de 30 de zile. | Upload/download și SHA-256 verificate; o arhivă recuperată de la distanță a pornit într-o instanță izolată. Recuperarea completă a infrastructurii pe alt host rămâne un exercițiu separat. |
| Rezolvat 2026-11-04 | Identitatea Unix comună a fost înlocuită cu `evolving-minds`, fără login/grupuri privilegiate. | Runtime și backup local migrate; release-uri read-only prin ACL, date 0700/0600, env și Git inaccesibile din sandbox. |
| P1 | Readiness și loguri există, dar nu a fost conectat un serviciu extern de alertare. | Monitor și rută de alertare către proprietar, cu pragurile din runbook. |
| P2 | Bugetele aplicației sunt locale unui nod, iar un atac distribuit poate ocoli limite per IP. | Buget distribuit la scalare, politici edge și teste de capacitate separate. |
| P2 | Scannerul de secrete folosește tipare limitate. Istoricul cu cheia revocată nu a fost rescris. | Scanner dedicat și procedură separată pentru curățarea istoricului partajat, dacă este necesar. |

Acesta este un audit al repository-ului și al integrării sale locale de producție.
Nu reprezintă un pentest distructiv, o certificare sau un audit al întregului VPS,
al tuturor celorlalte domenii ori al contului Cloudflare. Workflowul GitHub a fost
configurat și verificat local; nu se afirmă că a rulat deja remote în această sesiune.
