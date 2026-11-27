# OpenCode Monitor

**Versione 0.8.0** <!-- x-release-please-version --> (beta) · [novità](CHANGELOG.md) · [release](https://github.com/vale76p/opencode-lens-monitor-public/releases) · licenza [MIT](LICENSE)

App nella barra dei menu di macOS per tenere d'occhio [opencode-lens](https://github.com/vale76p/opencode-lens-public): uso di oggi contro i budget per modello nel pannello e nei widget, più avvio e arresto del servizio e scelta tra la lens di produzione e una di sviluppo. Solo OpenCode. Il repository e il bundle si chiamano ancora `opencode-lens-monitor` / `OpenCode Lens Monitor.app`.

**Etichetta nella barra**: logo, pallino colorato e percentuale di oggi (`● 40%`), la stessa della card Oggi: media dei budget giornalieri dei modelli, pesata su quanto li hai usati negli ultimi 7 giorni. Il pallino prende il colore del modello messo peggio, così un budget sforato non si nasconde nella media: verde se tutti sono in linea, arancio se almeno uno è proiettato oltre il budget a fine giornata, rosso se almeno uno l'ha già superato, grigio senza budget per modello o con la lens ferma; un triangolo giallo se la lens non è installata o è in errore.

**Pannello** (clic sull'etichetta), a card in Liquid Glass:

- **Oggi** con la data (`17/10/2026`): media delle percentuali dei modelli con un budget in `LENS_MODEL_LIMITS`, pesata sull'uso: ogni modello conta quanto è stato usato rispetto al suo budget negli ultimi 7 giorni più oggi, così un modello leggero usato apposta poco non abbassa il totale e uno mai usato non conta (senza questa storia è la media semplice, anche dei modelli non ancora usati, a 0%) e, con lo stesso carattere, i token di oggi di tutti i modelli (cache compresa), più la barra (colorata dal ritmo della media) e il badge del modello messo peggio (In linea, Sopra il ritmo, Superato). Senza budget per modello mostra solo i token e la variabile da impostare;
- **Modelli** di oggi (giorno di budget della lens, da `LENS_RESET_HOUR`), dal più recente, varianti insieme: token in (senza cache) e out (ragionamento compreso) e, per i modelli con un budget in `LENS_MODEL_LIMITS`, la % del budget giornaliero con una barra colorata dal ritmo e i token usati / budget (`7,1M / 100M`). Un modello con budget non ancora usato oggi compare a 0%. Se lo stesso modello arriva da due provider, le righe mostrano anche il provider (`anthropic/…`, `github-copilot/…`). In fondo, una sola riga per tutti: "Reset in 04h 12m alle 06:00" (ora in formato 24 ore);
- "Prossimo aggiornamento tra 46 s" (i dati si rileggono ogni minuto, o con l'intervallo scelto in Impostazioni → Generale → Dati da 15 s a 5 min, e a ogni apertura del pannello) con un pulsante ⓘ su versione della lens, fonte e ora dell'ultimo dato;
- piè di pagina: **OpenCode Monitor vX.Y.Z** (la versione del Monitor), pulsanti **dashboard** della lens (nell'[app OpenCode Lens](#con-lapp-opencode-lens) se è installata, altrimenti nel browser), **impostazioni** e **spegnimento** (Avvia/Ferma lens, Esci dal Monitor).

Nell'intestazione, il pallino accanto a **OpenCode** dice se la lens è collegata a OpenCode (verde) o no (arancio); con la lens non attiva il pallino è grigio o giallo e al posto di "OpenCode" c'è lo stato della lens.

Con la lens ferma, in avvio o in errore, al posto dei dati c'è una card di stato con Avvia o Ferma; con una lens di sviluppo che non risponde, con **Torna a Produzione**. Se la lens è attiva ma il suo database non si apre (schema più nuovo dopo un ritorno a una versione precedente, file rovinato), dalla 0.30.0 resta su e lo dice: la card "Errore della lens" mostra "database non utilizzabile: *motivo*" al primo controllo, senza aspettare i 15 secondi dell'avvio, anche per una lens di sviluppo. All'avvio e subito dopo un cambio di lens l'intestazione dice "verifica…" finché il primo controllo non risponde. Un errore resta nel pannello per un minuto.

**Impostazioni**, in due schede che stanno nella finestra senza scorrere: **Generale** (stato della lens con pallino, Avvia/Ferma, Dashboard, Log, ogni quanto rileggere i dati, e all'accesso: avvia la lens, apri OpenCode Monitor) e **Server** (la lens da seguire: Produzione, cioè il LaunchAgent, o una lens di sviluppo trovata in ascolto su questo Mac, con **Cerca di nuovo**). Il nome mostrato da macOS è **OpenCode Monitor**; il bundle resta `OpenCode Lens Monitor.app`.

**Widget** sulla scrivania, sui budget giornalieri per modello come il pannello:

- **Modello oggi**, piccolo: anello con al centro la % del giorno di un modello (token di oggi su budget giornaliero, senza contare quanto manca al reset), colorato dal ritmo, con nome e "Reset in 04h 12m alle 06:00";
- **Modello oggi**, medio: pallino, nome, % e badge del ritmo; sotto, il grafico dei token ora per ora dal reset (area sfumata) con la linea tratteggiata del ritmo medio (budget diviso le ore del giorno) e la riga del reset;
- **Modelli oggi**, medio: fino a 4 modelli, ognuno con nome, barra colorata dal ritmo con la % scritta sopra e usati / budget (`13,3M / 15M`); un modello oltre il budget o sopra il ritmo resta sempre visibile. In fondo la riga del reset.

Il modello di **Modello oggi** si sceglie con clic destro → **Modifica widget**, tra quelli con un budget giornaliero; senza scelta il widget segue quello messo peggio (prima il ritmo, poi la percentuale). Un modello senza budget mostra i token di oggi e l'anello grigio. I widget rileggono la lens ogni 15 minuti, un secondo dopo il reset del giorno e quando l'app vede cambiare percentuali o modelli; il tempo al reset si aggiorna ogni minuto. Il clic apre la dashboard se la lens risponde, altrimenti le impostazioni.

L'app usa gli stessi comandi `launchctl` di `opencode-lens service` sul LaunchAgent `local.opencode-lens`: avvia e ferma il servizio, ma non lo installa né lo rimuove.

## Requisiti

- macOS 26 o successivo, Apple silicon o Intel.
- [opencode-lens](https://github.com/vale76p/opencode-lens-public) installato come servizio: dallo zip della sua release, con `bash ~/Downloads/opencode-lens/install.sh`. Provato con la 0.44.0, minima la 0.38: con una lens più vecchia il pannello dice di aggiornarla. Un aggiornamento della lens dalla sua dashboard riattiva l'avvio al login (lo rimette a posto lei, non il Monitor).
- Facoltativa: l'[app OpenCode Lens](#con-lapp-opencode-lens) della lens (0.37.0 o successiva), per aprire la dashboard in una finestra invece che nel browser.

Xcode e XcodeGen servono solo per sviluppare (sotto).


## Installazione

L'app va in `~/Applications`. Tutto resta nella tua cartella utente, senza `sudo`, senza permessi di amministratore e senza Xcode: va bene anche su un Mac aziendale.

1. Dalla [pagina delle release](https://github.com/vale76p/opencode-lens-monitor-public/releases) scarica `opencode-lens-monitor-<versione>.zip`, non «Source code»: solo il primo contiene l'app compilata.
2. Fai doppio clic sullo zip nella cartella Download (Safari di solito lo estrae da solo): ottieni la cartella `opencode-lens-monitor`.
3. Apri il Terminale e lancia `install.sh` della cartella estratta. Il comando è uno solo: scrivi `bash `, trascina `install.sh` nella finestra e premi Invio. Oppure:

   ```bash
   bash ~/Downloads/opencode-lens-monitor/install.sh
   ```

Per vedere prima cosa c'è già installato senza cambiare niente (copie dell'app e versioni, app aperta, avvio al login, widget, altre copie, lens): `bash …/install.sh --check`.

`install.sh`:

- controlla la firma dell'app (team `HS87DR6TBX`) e la versione di macOS;
- chiude il Monitor se è aperto;
- copia l'app in `~/Applications/OpenCode Lens Monitor.app`, sostituendo per intero quella che c'era, toglie la quarantena del download e la apre;
- se non parte, rimette la versione di prima; se parte, sposta nel Cestino la copia precedente di `~/Applications` e quella in `/Applications` delle versioni fino alla 0.4.0. Senza i permessi per `/Applications` la lascia lì e spiega come toglierla;
- controlla che widget e avvio al login vengano dall'app nuova, e stampa i passi a mano quando servono; se chronod, il processo di macOS che fa girare i widget, li lancia ancora dalla copia tolta, lo riavvia (senza, i widget resterebbero fermi fino al logout);
- dice se la lens non è installata e come installarla, ma installa comunque il Monitor.

Impostazioni (App Group e UserDefaults), widget già sulla scrivania e servizio della lens non vengono toccati. Per passare da una versione installata in un altro modo, per la pulizia e per tornare indietro vedi [docs/aggiornamento.md](docs/aggiornamento.md).

**Aggiornamento**: stessi passi con lo zip nuovo.

Con la GitHub CLI i passi 1-3 diventano:

```bash
D="$(mktemp -d)" && gh release download -R vale76p/opencode-lens-monitor-public -p 'opencode-lens-monitor-*.zip' -D "$D" && ditto -x -k "$D"/opencode-lens-monitor-*.zip "$D" && bash "$D"/opencode-lens-monitor/install.sh
```

**Se lo zip è bloccato** (per esempio da un DLP aziendale): scarica il **«Source code (zip)»** della stessa release e lancia allo stesso modo `bash ~/Downloads/opencode-lens-monitor-<versione>/install.sh`. Senza l'app compilata, `install.sh` la compila dai sorgenti con `scripts/build-clt.sh`, con i soli Command Line Tools (bastano quelli con l'SDK di macOS 26 o successivo, niente Xcode), e poi installa come sempre. Firma con un certificato «Apple Development» del team `HS87DR6TBX`, se ce n'è uno nel portachiavi: puoi crearne uno apposta per quel Mac, senza amministratore ([docs/aggiornamento.md](docs/aggiornamento.md#installare-dal-source-code)). Senza certificato firma ad-hoc: Monitor e widget funzionano, ma i widget non leggono le impostazioni dell'app e seguono sempre la lens del LaunchAgent (porta e `LENS_TOKEN` dal suo plist). `--check` dice quale firma userebbe.

**Firma e Gatekeeper.** L'app è firmata "Apple Development" (team `HS87DR6TBX`) ma non è notarizzata. Un'app scaricata dal browser ha l'attributo di quarantena e Gatekeeper la blocca; `install.sh` lo toglie dalla copia in `~/Applications`, che appartiene all'utente, quindi non serve `sudo`. Se macOS la blocca comunque: Impostazioni di Sistema → Privacy e sicurezza → **Apri comunque**. Un Mac gestito può avere regole che bloccano le app non notarizzate anche così: in quel caso serve l'IT.

## Budget

Pannello, etichetta e widget usano i **budget giornalieri per modello** della lens, `LENS_MODEL_LIMITS` (`provider/modello=token`, separati da virgola), sul giorno di budget che si azzera all'ora di `LENS_RESET_HOUR`. Contano solo i modelli ancora nella configurazione di OpenCode.

Vanno in `EnvironmentVariables` di `~/Library/LaunchAgents/local.opencode-lens.plist` ([configurazione della lens](https://github.com/vale76p/opencode-lens-public/blob/main/docs/configurazione.md#budget)); poi ricarica il servizio (Ferma e Avvia dal pannello).

Il grafico di **Modello oggi** medio chiede alla lens i token ora per ora del solo modello scelto (`/api/timeseries?model=…`).

Serve la lens 0.38 o successiva: con una versione precedente il pannello dice "Aggiorna opencode-lens: serve la 0.38 o successiva".

## Limiti noti

- **Solo i budget per modello.** Il Monitor segue `LENS_MODEL_LIMITS` e basta: i limiti `LENS_LIMIT_*` di costo o di token giornalieri, settimanali e mensili non li mostra. Con soli quelli il pallino resta grigio e si vedono solo i token di oggi. Un modello con budget che la lens non ha mai visto (di solito un nome sbagliato in `LENS_MODEL_LIMITS`) compare come «mai visto: controlla il nome» e non entra nella media né nel colore.
- **Non notarizzata.** L'app delle release è firmata "Apple Development" (team `HS87DR6TBX`) e `install.sh` toglie la quarantena. Per la notarizzazione servirebbero un certificato Developer ID e il notary service di Apple.
- **I test non girano in CI.** I test Swift si lanciano in locale con `scripts/test.sh`; la CI controlla solo gli script.
- **Nessun avviso di nuova versione.** L'app non controlla se esce una release: si aggiorna rilanciando `install.sh` dallo zip nuovo ([docs/aggiornamento.md](docs/aggiornamento.md)).
- **Dopo un crash non riparte da sola.** Non ha un LaunchAgent con `KeepAlive`: l'app si riapre a mano o al prossimo login (se "Apri Monitor al login" è attivo).
- **Il widget non verifica la porta.** Il token della lens è letto dal widget (sandbox) e mandato a chi ascolta su quella porta; il controllo che sia il processo del job lo fa solo l'app.

## Con l'app OpenCode Lens

Dalla 0.37.0 la lens ha un'app macOS facoltativa, **OpenCode Lens** (`~/Applications/OpenCode Lens.app`, bundle id `local.opencode-lens.app`, si installa con `bash ~/Applications/opencode-lens/extras/macos/app.sh install`; vedi [docs/app-macos.md](https://github.com/vale76p/opencode-lens-public/blob/main/docs/app-macos.md) della lens). È una finestra sulla dashboard con l'icona nel Dock, le notifiche (budget superato, lens che non risponde) e l'avvio al login della finestra. Le due app convivono e nessuna serve all'altra:

| | OpenCode Monitor | OpenCode Lens (app) |
|---|---|---|
| Barra dei menu, percentuale di oggi, pannello, widget | ✓ | |
| Avvia e Ferma la lens, "Avvia la lens all'accesso" | ✓ | |
| Finestra della dashboard, icona nel Dock | | ✓ |
| Notifiche | | ✓ |
| Avvio al login | del Monitor | della finestra |

Il Monitor non manda notifiche: sono compito dell'app. Con l'app installata, **Apri la dashboard** (piè di pagina del pannello, Impostazioni → Generale → Dashboard, clic sui widget) la porta in primo piano invece di aprire il browser; se la finestra era chiusa (⌘W) la riapre. Con una lens di sviluppo scelta in **Server** si apre sempre il browser: l'app segue solo porta e token del plist del LaunchAgent e mostrerebbe la produzione. Senza l'app non cambia niente: la dashboard si apre nel browser.

## Versioni e rilasci

Versioni [SemVer](https://semver.org/lang/it/), con una sola fonte: `MARKETING_VERSION` in `project.yml`, che finisce nel bundle e nel piè di pagina del pannello. Finché la versione è 0.x, un cambio incompatibile alza la *minor*.

I rilasci li prepara [release-please](https://github.com/googleapis/release-please) dai [commit convenzionali](https://www.conventionalcommits.org/it/v1.0.0/) su `main`:

| Commit | Sezione del changelog | Versione |
|---|---|---|
| `feat(opencode-lens-monitor): …` | Aggiunto | *minor* |
| `fix(opencode-lens-monitor): …` | Corretto | *patch* |
| `perf:` / `refactor:` | Modificato | *patch* |
| `docs:` | Documentazione | *patch* |
| `!` dopo il tipo, o `BREAKING CHANGE:` nel corpo | | *major* (*minor* finché è 0.x) |
| `test:`, `ci:`, `build:`, `chore:` | non compaiono | |

A ogni push su `main` il workflow `.github/workflows/release-please.yml` tiene aggiornata una PR «chore(main): release X.Y.Z» con la versione in `project.yml` e in questo README e la voce nuova in `CHANGELOG.md`; le voci si possono rifinire a mano nella PR prima del merge. Al merge release-please crea il tag `vX.Y.Z` e la release GitHub.

Lo zip con l'app lo crea chi rilascia, sul Mac con il certificato del team, perché la firma non può stare in una CI senza mettere la chiave privata in un secret:

```bash
git checkout main && git pull --tags
git checkout vX.Y.Z
scripts/package.sh --upload
```

Oltre allo zip, `package.sh` controlla che il Source code del tag si compili con i soli Command Line Tools (`scripts/build-clt.sh`) e che i metadati AppIntents in `scripts/clt/` coincidano con quelli generati da Xcode; se il widget cambia intent o parametri, lo script dice come aggiornarli. `scripts/package.sh` si ferma con modifiche non committate e controlla che `project.yml`, il README e la prima voce di `CHANGELOG.md` dicano la stessa versione (con `--upload` anche che il tag sia HEAD e la release esista). Poi lancia i test, builda in Release da `git archive HEAD` in una cartella temporanea, verifica firma, team, versione e architetture (arm64 e x86_64) e crea `dist/opencode-lens-monitor-X.Y.Z.zip` con `ditto`. Con `--upload` lo allega alla release. Il numero di build (`CFBundleVersion`) del pacchetto viene dalla versione, *major*·10000 + *minor*·100 + *patch* (0.5.0 → 500): cresce a ogni rilascio, così macOS preferisce sempre la copia più nuova e rilegge l'elenco dei widget. Senza `--upload` lo zip resta in `dist/`, utile per provarlo prima.

Prima di allegare lo zip, provalo da una cartella estratta: `bash install.sh --check` deve riconoscere l'installazione che c'è, e `bash install.sh` deve installarlo.

L'installazione fa parte della compatibilità: bundle id `local.opencode-lens-monitor`, App Group `HS87DR6TBX.local.opencode-lens-monitor`, il nome `OpenCode Lens Monitor.app` e la cartella `~/Applications` non cambiano, e `install.sh` aggiorna da qualsiasi versione precedente. Cambiarne uno, o richiedere un passo a mano per aggiornare, è un cambio incompatibile.

Il workflow ha bisogno di «Allow GitHub Actions to create and approve pull requests» in *Settings → Actions → General → Workflow permissions* del repository. Il workflow `script.yml` controlla a ogni push la sintassi degli script e le variabili seguite da caratteri non ASCII.

## Build (sviluppo)

Servono Xcode con la licenza accettata, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) e il certificato "Apple Development" del team `HS87DR6TBX` nel portachiavi. Al primo build macOS può chiedere l'accesso alla chiave del certificato: scegli "Consenti sempre". Per i soli test del package bastano i Command Line Tools.

```bash
xcodegen generate
xcodebuild -project OpenCodeLensMonitor.xcodeproj -scheme OpenCodeLensMonitor -configuration Release \
  -derivedDataPath "$HOME/Library/Caches/opencode-lens-monitor/DerivedData" build
osascript -e 'quit app id "local.opencode-lens-monitor"' 2>/dev/null || true
rm -rf ~/Applications/"OpenCode Lens Monitor.app"
mkdir -p ~/Applications
ditto "$HOME/Library/Caches/opencode-lens-monitor/DerivedData/Build/Products/Release/OpenCode Lens Monitor.app" \
  ~/Applications/"OpenCode Lens Monitor.app"
open ~/Applications/"OpenCode Lens Monitor.app"
```

L'app va in `~/Applications`, come con `install.sh`: due copie (una in `/Applications`) confondono widget e avvio al login. Prima della copia l'app va chiusa e il bundle vecchio tolto: `cp -R` su un `.app` esistente lo fonderebbe con quello nuovo, lasciando file della versione precedente. Per provare l'installazione come la fa un utente: `scripts/package.sh`, poi `ditto -x -k dist/opencode-lens-monitor-X.Y.Z.zip "$(mktemp -d)"` e `bash …/opencode-lens-monitor/install.sh`.

La build va fuori dal repo: se il repo sta in una cartella sincronizzata con iCloud (es. `~/Documents`), gli attributi estesi aggiunti da File Provider fanno fallire la firma. Da Xcode non serve: usa già `~/Library/Developer/Xcode/DerivedData`.

Quando aggiungi, togli o cambi tipo e dimensioni di un widget, nelle build di sviluppo alza anche `CURRENT_PROJECT_VERSION` (lo zip della release ha già un numero di build nuovo a ogni versione): macOS rilegge l'elenco dei widget di un'app solo con un numero di build nuovo, altrimenti la galleria resta quella vecchia. Un widget già sulla scrivania che passa da senza configurazione a configurabile (come il widget della settimana della 0.3.0) va rimosso e aggiunto di nuovo.

Il progetto `.xcodeproj` è generato da `project.yml` e non è committato: dopo ogni modifica a `project.yml`, e dopo aver aggiunto o tolto file, rilancia `xcodegen generate`. Impostazioni del progetto (firma, versione, target) vanno in `project.yml`, non nell'editor di Xcode. Da Xcode: apri `OpenCodeLensMonitor.xcodeproj` e avvia lo schema `OpenCodeLensMonitor`.

App e widget sono firmati con il team `HS87DR6TBX` (firma manuale, senza provisioning profile): serve per l'App Group `HS87DR6TBX.local.opencode-lens-monitor`, da cui il widget legge host, porta e token, perché dal sandbox non può leggere il plist della lens. L'app resta fuori dal sandbox: deve eseguire `launchctl`.

"Apri Monitor al login" funziona in modo affidabile solo con l'app in `/Applications` o `~/Applications`. Se macOS chiede l'approvazione, le impostazioni mostrano **Approva in Impostazioni di Sistema…**. L'app annota da dove l'ha registrato (`defaults read local.opencode-lens-monitor loginItemPath`, letto anche da `install.sh`) e al primo avvio da un'altra cartella lo registra di nuovo. Una build di sviluppo, fuori da quelle due cartelle, non lo tocca.

## Sviluppo

```bash
scripts/dev.sh            # build Debug e avvio a ogni modifica dei sorgenti (Ctrl-C per uscire)
scripts/dev.sh --once     # una build e un avvio
```

Lo script chiude l'app installata (stesso bundle id e stessa App Group) e la riapre all'uscita, anche chiudendo il terminale; con `--once` l'app Debug resta aperta dopo lo script, quindi quella installata va riaperta a mano. Avvia la build Debug da `~/Library/Caches/opencode-lens-monitor/DerivedData` senza installarla (DerivedData separata, `DerivedData-dev`, per non scontrarsi con la build Release), con i log in quel terminale. Compila solo quando i file restano fermi per un secondo, e rigenera il progetto Xcode quando aggiungi o togli un file. All'avvio chiude anche un'app Debug rimasta aperta da `--once`. Dopo una modifica il giro dura pochi secondi. Accetta le stesse variabili d'ambiente dell'app (es. `LENS_MONITOR_PORT=4778 scripts/dev.sh`). I widget restano quelli dell'app installata: per provare modifiche al widget serve installarla.

## Prove con un'altra lens

Il modo più semplice è il menu **Server** delle impostazioni: elenca le lens in ascolto su questo Mac (processi `node` con `src/main.js`, assoluto o relativo come con `npm start`, che rispondono a `/healthz` senza token), con il nome del clone o del worktree, ad esempio "Sviluppo — lens-live — 127.0.0.1:4790". Scelta una lens di sviluppo, pannello e widget mostrano i suoi dati, l'intestazione del pannello porta la scritta **DEV**, e Avvia/Ferma spariscono perché il Monitor controlla solo il LaunchAgent. Una lens di sviluppo con `LENS_TOKEN` risponde 401 e non compare nel menu. Una lens il cui database non si apre (risponde 503) compare con "(database non utilizzabile)": scelta, il pannello mostra il motivo.

In alternativa, per provare una lens da un clone di opencode-lens senza toccare il servizio installato avviala su un'altra porta (meglio con una copia del database) e apri l'app con `LENS_MONITOR_PORT`, che ha la precedenza sulla porta del plist e passa anche al widget:

```bash
cd ../opencode-lens
sqlite3 "$HOME/Library/Application Support/opencode-lens/lens.db" ".backup /tmp/lens-prova.db"
LENS_PORT=4778 LENS_DB=/tmp/lens-prova.db npm start
open --env LENS_MONITOR_PORT=4778 ~/Applications/"OpenCode Lens Monitor.app"
```

Lo stato del servizio (Avvia/Ferma) resta quello del LaunchAgent vero.

Se la lens ascolta su un altro indirizzo (`LENS_HOST` nel plist), l'app e il widget la chiamano lì; con `0.0.0.0` o `::` usano 127.0.0.1. Un indirizzo non locale va aggiunto anche a `LENS_ALLOWED_HOSTS` della lens come `host:porta`, altrimenti la lens risponde 403.

Con un host non di loopback le chiamate, `LENS_TOKEN` compreso, viaggiano in chiaro (http) su quella rete. Per esporre la lens sulla LAN usa `0.0.0.0` (il Monitor resta su 127.0.0.1) o un indirizzo IP, non un nome `.local`: la risoluzione mDNS si può falsificare da qualunque macchina della stessa rete, che riceverebbe il token.

## Test

```bash
scripts/test.sh
scripts/test.sh --filter PanelStateTests
```

Tutta la logica (comandi `launchctl`, parsing, client HTTP, budget, formattazione, stato del pannello e dei widget, modello) è nel package `LensMonitorCore` ed è testata con Swift Testing, senza toccare il launchd reale né la rete. App e widget contengono solo le viste SwiftUI.

Gli stessi test lanciano `install.sh` (anche dal Source code, con un `build-clt.sh` finto) in una HOME temporanea, con una `/Applications` finta (`LENS_MONITOR_SYSTEM_APPS`) e un `PATH` fatto solo di comandi finti (`osascript`, `open`, `pgrep`, `pluginkit`, `lsregister`, `defaults`, `launchctl print`, `pkill`, `codesign`, `curl`) e di link a strumenti che leggono o copiano file: un comando vero che potrebbe chiudere, sostituire o registrare l'app installata, o toccare login item e launchd, non è nemmeno raggiungibile. Girano con `LC_ALL=en_US.UTF-8`, come il Terminale, e un controllo statico cerca le `$VARIABILI` seguite da un carattere non ASCII, che il bash 3.2 di macOS legge come parte del nome (vanno scritte `${VARIABILE}`).

Lo script lancia `swift test` con la build in `~/Library/Caches/opencode-lens-monitor` (stesso motivo della firma sopra) e con il percorso dei plugin delle macro di Swift Testing esplicito: con i soli Command Line Tools `swift test` a volte non lo trova ("plugin for module 'TestingMacros' not found").

## Verifica manuale

Con il servizio installato e l'app avviata:

1. Il servizio è attivo: il pannello mostra le card e l'intestazione ha il pallino verde accanto a "OpenCode" (arancio se OpenCode non è aperto).
2. **Ferma lens** (pulsante di spegnimento o impostazioni): entro pochi secondi il pannello mostra la card "Lens ferma", il pallino diventa grigio e `curl -s http://127.0.0.1:4777/healthz` non risponde.
3. **Avvia lens**: entro pochi secondi tornano le card e `/healthz` risponde.
4. In Impostazioni → Generale togli la spunta da **All'accesso → Avvia la lens**, ferma il servizio, esci e rientra nella sessione: il servizio resta fermo. Rimetti la spunta, ripeti: riparte da solo.
5. Con la spunta tolta, **Avvia lens** lo avvia e la spunta resta tolta (`launchctl print-disabled gui/$(id -u) | grep opencode-lens` dice `disabled`).
6. **Apri OpenCode Monitor** all'accesso: dopo logout/login l'app è nella barra.
7. Con `opencode-lens service uninstall` (senza `--purge`) il pannello dice "Lens non installata" e l'etichetta mostra il triangolo. Rilancia `bash …/install.sh` della lens per ripristinare.
8. Con un budget per modello (`LENS_MODEL_LIMITS`) l'etichetta mostra la percentuale di oggi e il pallino del colore del ritmo; percentuali e usati / budget del pannello coincidono con `periods.day.models` di `curl -s http://127.0.0.1:4777/api/budget`.
9. Senza budget per modello la card Oggi indica la variabile da impostare e l'etichetta non ha percentuale.
10. Con una lens più vecchia della 0.38 il pannello dice di aggiornare opencode-lens.
11. Clic destro sulla scrivania → **Modifica widget** → OpenCode Monitor: aggiungi **Modello oggi** piccolo e medio e **Modelli oggi**. Percentuali, usati / budget e riga del reset coincidono con il pannello; dopo un minuto il tempo al reset è sceso di un minuto. Il clic apre la dashboard (con la lens ferma, le impostazioni).
12. Su **Modello oggi**, clic destro → **Modifica widget**: il menu elenca i modelli con budget; scegline uno diverso da quello predefinito e il widget passa a quello. Nel medio il grafico arriva all'ora in corso.
13. Avvia una lens di prova (`LENS_PORT=4778 npm start` nel clone di opencode-lens): in Impostazioni → Server compare "Sviluppo — opencode-lens — 127.0.0.1:4778". Sceglila: l'intestazione dice "verifica…", poi mostra **DEV** e i dati della 4778, senza Avvia/Ferma. Ferma la lens di prova: la card "Server non raggiungibile" offre **Torna a Produzione**.
14. Installazione da zip (`scripts/package.sh`, poi lo zip estratto in una cartella): `bash install.sh --check` elenca copie, versioni, app aperta, avvio al login, widget e lens, e non cambia niente. Da una 0.4.0 in `/Applications` con "Apri OpenCode Monitor" acceso, `bash install.sh` chiude l'app, la installa in `~/Applications`, sposta la vecchia nel Cestino e stampa "Widget: OK" e "Avvio al login: OK"; se sulla scrivania c'erano i widget della copia in `/Applications`, stampa anche "ho riavviato chronod". I widget sulla scrivania si aggiornano e restano aggiornati anche dopo che è uscito il processo del widget partito da `/Applications` (`pgrep -lf OpenCodeLensWidget` lo mostra da `~/Applications`, e `/usr/bin/log show --last 10m --predicate 'process == "launchd"' | grep opencode-lens-monitor.widget` non ha "will use existing"); dopo logout/login il Monitor parte da `~/Applications`.
15. Con `/Applications` non scrivibile (utente standard), `install.sh` installa lo stesso e spiega come togliere la copia vecchia; su un Mac senza la lens dice come installarla.
16. Lens di sviluppo con un database dallo schema più nuovo: copia il database (`sqlite3 "$HOME/Library/Application Support/opencode-lens/lens.db" ".backup /tmp/lens-rotta.db"`), alza lo schema (`sqlite3 /tmp/lens-rotta.db "PRAGMA user_version = 999"`) e avvia `LENS_PORT=4791 LENS_DB=/tmp/lens-rotta.db npm start` nel clone della lens (mai sul database, sul plist o sulla porta 4777 veri). In Impostazioni → Server compare "Sviluppo — opencode-lens (database non utilizzabile) — 127.0.0.1:4791"; scelta, entro un refresh (5 s) la card "Errore della lens" dice "database non utilizzabile: database con schema 999, più nuovo di questa lens…", non "verifica…" né "Server non raggiungibile", e il piè di pagina non ha Avvia/Ferma. Ferma quella lens: "Server non raggiungibile" con **Torna a Produzione**.
17. **Apri la dashboard** (piè di pagina, Impostazioni → Generale → Dashboard, clic su un widget) senza `~/Applications/OpenCode Lens.app`: si apre il browser. Installa l'app (`bash ~/Applications/opencode-lens/extras/macos/app.sh install`) e ripeti: viene davanti l'app, anche con la sua finestra chiusa (⌘W). Scegli una lens di sviluppo in Server e ripeti: si apre il browser sulla sua porta. Togli l'app (`app.sh uninstall`): di nuovo il browser, senza riavviare il Monitor.
18. Con **Avvia lens al login** spento, salva le Impostazioni della lens dalla sua dashboard: la lens esce e launchd non la riavvia. Entro pochi secondi il Monitor dice "riavvio in corso…" per una ventina di secondi, poi "Lens ferma" con la nota che è disabilitata all'accesso, anche in Impostazioni → Generale; **Avvia** la riporta su.

## Struttura

```
opencode-lens-monitor/
├── CHANGELOG.md             # novità per versione (release-please)
├── install.sh               # installazione e aggiornamento dallo zip della release
├── docs/aggiornamento.md    # aggiornare, controllare, pulire, tornare indietro
├── project.yml              # XcodeGen: app e widget
├── scripts/test.sh          # test del package (e di install.sh e package.sh)
├── scripts/dev.sh           # build Debug e riavvio a ogni modifica
├── scripts/package.sh       # zip della release con l'app firmata
├── scripts/build-clt.sh     # build dai sorgenti con i soli Command Line Tools (install.sh dal Source code)
├── scripts/clt/             # metadati AppIntents del widget per build-clt.sh (li genera solo Xcode)
├── .github/                 # release-please e controllo degli script
├── LensMonitorCore/         # package Swift: logica e test
├── Shared/                  # viste comuni ad app e widget (colori, badge, riga dei modelli)
├── OpenCodeLensMonitor/     # app: etichetta, pannello, impostazioni, avvio al login
└── OpenCodeLensWidget/      # estensione WidgetKit
```

## Licenza

[MIT](LICENSE) © 2026 vale76p. Progetto indipendente, non affiliato a OpenCode.
