# Aggiornare da una versione precedente

Dalla 0.5.0 OpenCode Monitor si installa con `install.sh` dallo zip della release, in `~/Applications`, senza `sudo` e senza Xcode. Questa guida spiega come passare da una versione installata in un altro modo, cosa fa da solo `install.sh`, cosa controllare dopo e cosa si può togliere senza perdere impostazioni e widget.

## Dove stanno le cose

| Cosa | Percorso | Da tenere |
|---|---|---|
| App | `~/Applications/OpenCode Lens Monitor.app` (fino alla 0.4.0 `/Applications/OpenCode Lens Monitor.app`) | la sostituisce `install.sh` |
| Impostazioni condivise con il widget (App Group) | `~/Library/Group Containers/HS87DR6TBX.local.opencode-lens-monitor/` | sì: contiene la lens scelta in Impostazioni → **Server**; host, porta e token li riscrive l'app a ogni avvio dal plist della lens |
| Impostazioni dell'app (UserDefaults) | `~/Library/Preferences/local.opencode-lens-monitor.plist` | sì: finestra delle impostazioni e, dalla 0.5.0, stato e percorso dell'avvio al login |
| Widget sulla scrivania | li tiene macOS, legati al bundle id `local.opencode-lens-monitor.widget` e non al percorso dell'app | sì |
| Avvio al login ("Apri OpenCode Monitor") | Elementi login di macOS (SMAppService), registrato dal percorso dell'app | dalla 0.5.0 il Monitor lo registra di nuovo da `~/Applications` al primo avvio |
| Servizio della lens | `~/Library/LaunchAgents/local.opencode-lens.plist` | sì: il Monitor lo legge e lo avvia o ferma, non lo installa |

Bundle id (`local.opencode-lens-monitor`), App Group e servizio della lens non sono mai cambiati dalla 0.1.0: un'installazione nuova ritrova tutto. Cambia solo **dove sta l'app**:

| Installazione | Cartella dell'app | Versioni |
|---|---|---|
| build con Xcode e copia a mano (vecchia sezione «Build» del README) | `/Applications` | 0.1.0–0.4.0 |
| `install.sh` dallo zip della release | `~/Applications` | 0.5.0 → |
| build di sviluppo (`scripts/dev.sh`, Xcode, `scripts/package.sh`) | `~/Library/Caches/opencode-lens-monitor/…` o `~/Library/Developer/Xcode/DerivedData/…` | solo sul Mac di chi sviluppa |

## 1. Controlla cosa c'è installato

Estrai lo zip nuovo e lancia `install.sh` con `--check`. Mostra la situazione e **non cambia niente**:

```bash
bash ~/Downloads/opencode-lens-monitor/install.sh --check
```

```text
Versione da installare: 0.5.0 (build 500), da /Users/tu/Downloads/opencode-lens-monitor
Non c'è: /Users/tu/Applications/OpenCode Lens Monitor.app
Installata: /Applications/OpenCode Lens Monitor.app, 0.4.0 (build 5)
In esecuzione: /Applications/OpenCode Lens Monitor.app
Avvio al login: non noto (fino alla 0.4.0 il Monitor non lo annota: guarda Impostazioni > Generale del Monitor)
Widget: da /Applications/OpenCode Lens Monitor.app
Altra copia, non usata: /Users/tu/Desktop/OpenCode Lens Monitor.app, 0.3.0 (build 4)
Lens: 0.12.1, servizio local.opencode-lens da /Users/tu/Applications/opencode-lens, http://127.0.0.1:4777 risponde
```

- **Installata** / **Non c'è**: le copie in `~/Applications` e in `/Applications`, con versione e numero di build.
- **In esecuzione**: da dove gira il Monitor adesso.
- **Avvio al login**: come l'ha annotato il Monitor dalla 0.5.0.
- **Widget**: la copia da cui macOS prende i widget. Le righe **registrati anche da** sono altre copie che macOS conosce, di solito build di sviluppo. Una riga **ma macOS li fa girare ancora da …** vuol dire che chronod, il processo di macOS che fa girare i widget, li lancia ancora da un'altra copia (vedi la sezione 3).
- **Altra copia**: un `OpenCode Lens Monitor.app` trovato in Download, Scrivania o Documenti, che non viene usato.
- **Lens**: versione e cartella del servizio, e se risponde. Se la lens non è installata, il controllo lo dice e indica come installarla.

La prima volta macOS può chiedere se il Terminale può accedere a Download, Scrivania e Documenti: servono solo per cercare le altre copie. Se rifiuti, l'elenco resta vuoto e il resto funziona.

Senza lo zip nuovo, gli stessi controlli si fanno a mano:

```bash
plutil -extract CFBundleShortVersionString raw "/Applications/OpenCode Lens Monitor.app/Contents/Info.plist"
plutil -extract CFBundleShortVersionString raw ~/Applications/"OpenCode Lens Monitor.app"/Contents/Info.plist
pgrep -lf "/Contents/MacOS/OpenCode Lens Monitor"                  # copie aperte
pluginkit -m -v -i local.opencode-lens-monitor.widget              # copia da cui macOS prende i widget
pluginkit -m -A -D -v -i local.opencode-lens-monitor.widget        # tutte le copie registrate
launchctl print "pid/$(pgrep -U "$(id -u)" -x chronod)/local.opencode-lens-monitor.widget" | grep -m 1 'path ='   # copia da cui chronod lancia il widget
defaults read local.opencode-lens-monitor loginItemStatus          # avvio al login (dalla 0.5.0)
defaults read local.opencode-lens-monitor loginItemPath
find ~/Downloads ~/Desktop ~/Documents -maxdepth 4 -name "OpenCode Lens Monitor.app" -prune
plutil -extract WorkingDirectory raw ~/Library/LaunchAgents/local.opencode-lens.plist   # cartella della lens
```

## 2. Installa con `install.sh`

```bash
bash ~/Downloads/opencode-lens-monitor/install.sh
```

Non serve chiudere il Monitor prima, e non serve essere amministratore. Ecco cosa fa, in quest'ordine:

1. Controlla che l'app nello zip abbia una firma valida del team `HS87DR6TBX` e che il Mac abbia macOS 26 o successivo. Se qualcosa non va, si ferma prima di toccare altro.
2. Chiude il Monitor se è aperto (anche più copie). Se non si chiude, si ferma senza cambiare niente.
3. Copia l'app in una cartella temporanea dentro `~/Applications` e poi la scambia con quella che c'era. Il bundle vecchio viene sostituito per intero, mai fuso con quello nuovo. Toglie la quarantena del download (`xattr -dr com.apple.quarantine`): l'app non è notarizzata e senza questo passo Gatekeeper la bloccherebbe.
4. Apre l'app nuova e aspetta che parta. Se non parte, rimette la versione di prima, riapre quella che era aperta e si ferma.
5. Solo a quel punto sposta nel **Cestino** le copie precedenti:

| Copia precedente | `install.sh` |
|---|---|
| `~/Applications/OpenCode Lens Monitor.app` | la sposta nel Cestino come `OpenCode Lens Monitor <versione> <data>.app`; se il Cestino non è accessibile, la cancella |
| `/Applications/OpenCode Lens Monitor.app` | la sposta nel Cestino; senza permessi (Mac aziendale senza amministratore) la lascia e spiega come toglierla |
| altre copie in Download, Scrivania, Documenti | le elenca soltanto |
| la copia nella cartella estratta dallo zip | la toglie dall'elenco delle app di macOS, così i widget non restano legati a una cartella che cancellerai |

6. Controlla da dove macOS prende i widget e l'avvio al login (vedi sotto). Se chronod, il processo di macOS che fa girare i widget, li lancia ancora dalla copia appena tolta, lo riavvia (vedi sotto).

App Group, UserDefaults e servizio della lens non vengono mai toccati.

## 3. Widget e avvio al login

Alla fine `install.sh` stampa due righe:

- **Widget: OK, da ~/Applications/…**: i widget già sulla scrivania restano e si aggiornano dall'app nuova. Se uno resta vuoto, toglilo e rimettilo: clic destro sulla scrivania → **Modifica widget** → OpenCode Monitor. I widget della settimana della 0.3.0 vanno comunque sostituiti (vedi [CHANGELOG](../CHANGELOG.md)).
- **Widget: macOS li prende ancora da …**: di solito è la copia in `/Applications` che non si è potuta spostare. Toglila (sotto), esci e rientra nella sessione; se i widget restano vuoti, toglili e rimettili.
- **macOS faceva girare i widget ancora da …: ho riavviato chronod**: succede passando da `/Applications` a `~/Applications` con i widget già sulla scrivania. chronod si ricorda la copia da cui ha lanciato il widget la prima volta e non accetta un percorso nuovo finché non si riavvia: con la copia vecchia nel Cestino i widget resterebbero fermi. `install.sh` lo riavvia (macOS lo fa ripartire da solo, in meno di un secondo): tutti i widget della scrivania, anche delle altre app, si ricaricano.
- **… non sono riuscito a riavviare chronod**: i widget restano fermi finché non esci e rientri nella sessione, oppure lancia `killall chronod` nel Terminale.
- **Avvio al login: OK**: il Monitor ha registrato di nuovo l'avvio al login da `~/Applications`. Al primo avvio macOS può mostrare la notifica "Elemento di login aggiunto".
- **Avvio al login: da approvare**: apri Impostazioni di Sistema → Generale → Elementi login e attiva OpenCode Monitor, oppure nel Monitor Impostazioni → Generale → **Approva in Impostazioni di Sistema…**.
- **Avvio al login: non attivo**: era spento, oppure la nuova registrazione non è riuscita. Per attivarlo: Impostazioni → Generale → **Apri OpenCode Monitor**.

## 4. Pulizia

Quando il Monitor nuovo mostra i tuoi dati:

- **Cestino**: `OpenCode Lens Monitor <versione> <data>.app` si può svuotare.
- **Zip scaricato e cartella estratta** da cui hai lanciato `install.sh`: si possono cancellare.
- **Altre copie** elencate da `--check`: si possono cancellare.
- **Copia in `/Applications`** rimasta perché serviva un amministratore: nel Finder, Applicazioni → clic destro su OpenCode Monitor → **Sposta nel Cestino**. macOS chiede la password di un amministratore; se non ce l'hai, chiedi all'IT. Finché resta, il Monitor in `~/Applications` funziona, ma macOS potrebbe prendere i widget da quella copia.
- **Build di sviluppo** (solo sul Mac di chi sviluppa): `rm -rf ~/Library/Caches/opencode-lens-monitor` toglie DerivedData e cache dei test; si ricreano alla prossima build.

### Da non fare

- Non copiare l'app con `cp -R` sopra un'altra: fonde i due bundle e lascia file della versione precedente. Usa `install.sh`, oppure togli prima la copia vecchia e usa `ditto`.
- Non tenere aperte due copie del Monitor insieme: scrivono la stessa App Group.
- Non cancellare `~/Library/Group Containers/HS87DR6TBX.local.opencode-lens-monitor`: non serve, e perderesti la lens scelta in **Server**. Aprire quella cartella dal Terminale fa chiedere a macOS il permesso di accedere ai dati di altre app: `install.sh` non la legge.
- `install.sh` del Monitor non installa né aggiorna la lens: per quella c'è il suo `install.sh` ([opencode-lens](https://github.com/vale76p/opencode-lens-public/blob/main/docs/aggiornamento.md)). Non usare `--purge` della lens: cancella il suo database.

## Lens minima e lens ferma dopo un salvataggio

Il Monitor segue la lens dalla 0.38 in su (provato con la 0.44.0): con una più vecchia il pannello dice di aggiornarla.

Se hai **Avvia lens al login** spento e salvi le Impostazioni della lens dalla sua dashboard, la lens esce per ripartire e launchd, con il servizio disabilitato, non la riavvia. Il Monitor mostra "riavvio in corso…" per una ventina di secondi, poi "Lens ferma" con una nota: premi **Avvia**. Il rimedio vero arriva con una versione della lens che tratta il servizio disabilitato come il Monitor.

## Installare dal Source code

Se lo zip con l'app non si può scaricare (un DLP aziendale blocca gli archivi con eseguibili), scarica il **«Source code (zip)»** della stessa release ed estrailo. `install.sh` vede che l'app compilata manca e la compila con `scripts/build-clt.sh`:

```bash
bash ~/Downloads/opencode-lens-monitor-<versione>/install.sh --check
bash ~/Downloads/opencode-lens-monitor-<versione>/install.sh
```

Servono solo i **Command Line Tools** con l'SDK di macOS 26 o successivo, niente Xcode. `--check` mostra SDK e firma che userebbe: se mancano, `xcode-select --install`, che può richiedere un amministratore. La compilazione dura circa un minuto ed è solo per l'architettura di quel Mac. Il resto (chiusura, copia, Cestino, controlli) è identico.

La **firma** decide cosa funziona:

| Firma | Quando | Cosa funziona |
|---|---|---|
| certificato «Apple Development» del team `HS87DR6TBX` | c'è nel portachiavi «login» | tutto, come con lo zip |
| ad-hoc | non c'è | Monitor nella barra e widget; i widget però non leggono le impostazioni dell'app: seguono sempre la lens del LaunchAgent, con porta e `LENS_TOKEN` del suo plist, anche quando in **Server** è scelta una lens di sviluppo |

Perché: macOS valida l'App Group `HS87DR6TBX.…`, da cui il widget legge le impostazioni dell'app, solo per un'app firmata da quel team. Senza, il widget legge il plist del LaunchAgent (solo quel file, in sola lettura). Fino alla 0.7.1 usava `127.0.0.1:4777` senza token, e dalla lens 0.38, che ha sempre un `LENS_TOKEN`, restava vuoto.

## Tornare alla versione precedente

La versione precedente è nel Cestino. Chiudi il Monitor (pannello → pulsante di spegnimento → **Esci dal Monitor**), poi nel Finder:

1. Vai → Inizio → Applicazioni: sposta `OpenCode Lens Monitor.app` nel Cestino.
2. Apri il Cestino e trascina `OpenCode Lens Monitor <versione> <data>.app` nella cartella Applicazioni della tua home.
3. Rinominala `OpenCode Lens Monitor.app` e aprila.

Se hai lo zip della versione precedente, è più semplice lanciare il suo `install.sh`. Una versione fino alla 0.4.0 non registra di nuovo l'avvio al login: se serve, togli e rimetti la spunta in Impostazioni → Generale.

## Disinstallare

1. Nel Monitor, Impostazioni → Generale: togli **Apri OpenCode Monitor**, così macOS non tiene un elemento di login senza app.
2. Esci dal Monitor e sposta `~/Applications/OpenCode Lens Monitor.app` nel Cestino. I widget spariscono dalla scrivania.
3. Facoltativo: `defaults delete local.opencode-lens-monitor` per le impostazioni dell'app; la cartella dell'App Group (vedi sopra) si toglie dal Finder.

La lens resta installata e continua a girare: per toglierla vedi la sua [guida](https://github.com/vale76p/opencode-lens-public/blob/main/docs/disinstallazione.md).
