# Audit de securitate — Evolving Minds

Data: 2026-11-04. Audit de cod și configurație locală, verificări HTTP neintruzive.
Nu s-au făcut teste de epuizare de resurse sau atacuri destructive în producție.

## Inventar verificat

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
| OPS-01 | Ridicată pentru deploy | Scriptul și unitatea versionate indică vechiul director/serviciu, nu instalarea activă. Rularea lor ar putea crea un serviciu concurent sau eșua. | Deploy parametrizat pentru unitatea reală, verificări și backup înainte de restart. |
| OPS-02 | Medie | /healthz întoarce mereu ok, chiar dacă procesele simulării lipsesc. | Readiness real, răspuns minimal și 503 la indisponibilitate. |
| UX-01 | Produs | Header cu lățime minimă cumulată mare, texte de 7–9px, select fără etichete, dialoguri fără focus trap/Escape, lipsesc reconectare și accesibilitate pentru mișcare redusă. | Layout mobil și componente/feedback accesibile. |
| UX-02 | Produs | Căutarea filtrează doar ID, genealogia încarcă întregul arbore, nu există favorite, comparație sau linkuri către un dosar. | Funcții de explorare și structură de navigare. |

## Puncte solide

HEEx escapează textul; euristicile sunt funcții construite din trăsături, fără eval.
CSRF și verificarea Origin există. ETS protejat, memorii/evenimente limitate,
snapshot prin rename atomic și state store care curăță procesele terminate.
Nu s-au găsit secrete în fișierele urmărite la inspecția inițială; aceasta nu
înlocuiește un scanner al întregului istoric Git sau rotația secretelor compromise.

## Model de amenințări și limite

Principalele riscuri sunt escaladarea public→admin, DoS pe conexiuni/acțiuni și
alterarea stării persistente prin acces local. Compromiterea procesului `micu`
trebuie evaluată și față de celelalte servicii ale VPS-ului: același utilizator
deține mai multe proiecte; un utilizator dedicat ar reduce raza de impact.

Limitarea aplicației este pentru o singură instanță BEAM; la scalare trebuie
un buget comun între noduri. Un atac distribuit necesită protecții și la edge.
Nu există suficiente date pentru a estima cost financiar, MTTD real sau numărul
vizitatorilor afectați. Verificarea altor domenii și testarea restaurării remote
nu fac parte din acest audit al repository-ului.

## Surse tehnice

- Model LiveView: https://phoenix-live-view.hexdocs.pm/security-model.html
- ETF și :safe: https://www.erlang.org/docs/27/apps/erts/erlang.html#binary_to_term/2
- Advisory-urile exacte sunt returnate de `mix hex.audit`; disponibilitatea unui
  patch și relevanța pentru aplicație se verifică la actualizare.

Starea remedierilor și rezultatele verificărilor se completează la livrare.
