# Novità

Il formato segue [Keep a Changelog](https://keepachangelog.com/it/1.1.0/); le versioni seguono il [versionamento semantico](https://semver.org/lang/it/). La versione è `MARKETING_VERSION` in `project.yml`.

Dalla 0.5.0 le voci le scrive [release-please](https://github.com/googleapis/release-please) dai commit convenzionali (`feat:` → Aggiunto, `fix:` → Corretto, …) nella PR di rilascio, dove si possono rifinire prima del merge. Ogni versione ha un tag git `vX.Y.Z` e una [release su GitHub](https://github.com/vale76p/opencode-lens-monitor-public/releases) con lo zip da installare con `install.sh`. Come si rilascia: [README](README.md#versioni-e-rilasci).

## [0.8.0] (2026-11-21)


### Aggiunto

* **opencode-lens-monitor:** percentuale di oggi pesata sull'uso abituale dei modelli
* **opencode-lens-monitor:** percentuale di oggi pesata sull'uso dei modelli
* **opencode-lens-monitor:** storia di 7 giorni per pesare la percentuale di oggi


### Corretto

* **opencode-lens-monitor:** testo al singolare con un solo modello usato e test delle varianti


### Documentazione

* **opencode-lens-monitor:** spec e piano del totale di oggi pesato sull'uso abituale

## [0.7.4] (2026-11-03)


### Corretto

* **opencode-lens-monitor:** conversioni a intero sicure con valori fuori scala dalla lens
* **opencode-lens-monitor:** correzioni dalla revisione avversaria (crash, budget mai visti, widget, polling, token)
* **opencode-lens-monitor:** i modelli mai visti dalla lens non contano nella media né nel colore
* **opencode-lens-monitor:** il token va solo al processo del job in ascolto sulla porta
* **opencode-lens-monitor:** il widget ritenta dopo due minuti e non inventa token a zero
* **opencode-lens-monitor:** polling a ritmo adattivo invece di 5 s fissi


### Documentazione

* **opencode-lens-monitor:** sezione «Limiti noti» nel README

## [0.7.3] (2026-10-29)

Serve opencode-lens 0.38 o successiva: con una lens più vecchia il pannello mostra «Aggiorna opencode-lens: serve la 0.38 o successiva».


### Corretto

* **opencode-lens-monitor:** Avvia non dà errore se la lens è già ripartita durante il bootstrap
* **opencode-lens-monitor:** il pannello e le Impostazioni spiegano quando la lens è stata fermata fuori dal Monitor e non è ripartita


### Modificato

* **opencode-lens-monitor:** lens minima 0.38 al posto dei rami per le lens senza /api/budget
* **opencode-lens-monitor:** via i resti di Homebrew e la migrazione del widget della 0.3.0


### Documentazione

* **opencode-lens-monitor:** allineati alla lens 0.44, lens minima 0.38 e stop esterno
* **opencode-lens-monitor:** analisi, spec e piano di F.2 (lens a moduli)

## [0.7.2] (2026-10-25)


### Corretto

* **opencode-lens-monitor:** con la firma ad-hoc i widget leggono porta e token dal plist della lens

## [0.7.1] (2026-10-24)


### Corretto

* **opencode-lens-monitor:** dashboard nel browser con il token della lens

## [0.7.0] (2026-10-24)


### Aggiunto

* **opencode-lens-monitor:** «Apri la dashboard» usa l'app OpenCode Lens se è installata


### Corretto

* **opencode-lens-monitor:** il motivo della lens in modalità diagnostica arriva subito nel pannello


### Documentazione

* **opencode-lens-monitor:** lens 0.37.0, modalità diagnostica e app OpenCode Lens

## [0.6.2] (2026-10-18)


### Corretto

* **opencode-lens-monitor:** il runner aspetta l'EOF dei pipe prima di waitUntilExit

## [0.6.1] (2026-10-18)


### Corretto

* **opencode-lens-monitor:** cicli di attesa di install.sh con {1..20} invece dell'elenco
* **opencode-lens-monitor:** dev.sh chiude le app con pattern ancorato
* **opencode-lens-monitor:** dev.sh esce se il cd nella radice del repo fallisce
* **opencode-lens-monitor:** Format.compact senza il return finale irraggiungibile
* **opencode-lens-monitor:** grafico del widget con le ore vere del giorno anche col cambio d'ora
* **opencode-lens-monitor:** la lettura dell'output del runner non resta appesa a un figlio
* **opencode-lens-monitor:** messaggio di timeout del runner con Format.seconds
* **opencode-lens-monitor:** orari del popover ⓘ in formato 24 ore con Format.clock
* **opencode-lens-monitor:** refresh dei dati subito dopo il reset del giorno di budget
* **opencode-lens-monitor:** regole di visualizzazione del budget scritte una volta sola
* **opencode-lens-monitor:** sessione HTTP dedicata con scadenza totale e tetto al corpo
* **opencode-lens-monitor:** un avvio scade anche se launchctl print non risponde
* **opencode-lens-monitor:** voci del menu di accensione decise in core e testate


### Documentazione

* **opencode-lens-monitor:** AGENTS.md allineato a CLAUDE.md (chronod, intervallo dati)
* **opencode-lens-monitor:** commenti in italiano in install.sh e negli script di build
* **opencode-lens-monitor:** commenti in italiano nei test, nelle viste e nei workflow
* **opencode-lens-monitor:** il marchio OpenCode è disegnato in due posti, detto in entrambi
* **opencode-lens-monitor:** perché stopPolling() esiste solo per i test
* **opencode-lens-monitor:** piè di pagina d'esempio senza numero di versione

## [0.6.0] (2026-10-17)


### Aggiunto

* **opencode-lens-monitor:** intervallo dei dati nelle impostazioni e hover dei pulsanti
* **opencode-lens-monitor:** intervallo di aggiornamento dei dati nelle impostazioni
* **opencode-lens-monitor:** pulsanti in fondo al pannello evidenziati al passaggio del mouse

## [0.5.2] (2026-10-17)


### Corretto

* **opencode-lens-monitor:** Hardened Runtime per app e widget, anche nella build CLT
* **opencode-lens-monitor:** install.sh lega il team della firma a un certificato Apple
* **opencode-lens-monitor:** install.sh riavvia chronod se fa girare i widget dalla copia tolta
* **opencode-lens-monitor:** niente reload né Avvia/Ferma verso la lens sbagliata dopo un cambio di Server
* **opencode-lens-monitor:** senza App Group il token non si copia nelle UserDefaults dell'app
* **opencode-lens-monitor:** un errore di launchctl print non fa partire il timeout di avvio


### Documentazione

* **opencode-lens-monitor:** con un LENS_HOST non di loopback il token viaggia in chiaro
* **opencode-lens-monitor:** punto 14 della verifica manuale in termini di percorso

## [0.5.1] (2026-10-17)


### Corretto

* **opencode-lens-monitor:** con la firma ad-hoc niente App Group né errori continui nel log
* **opencode-lens-monitor:** firma ad-hoc senza errori continui nel log
* **opencode-lens-monitor:** install.sh dal Source code non ripete la riga della firma

## [0.5.0] (2026-10-17)


### Aggiunto

* **opencode-lens-monitor:** install.sh compila il Monitor dal Source code, senza Xcode
* **opencode-lens-monitor:** installazione da zip con un solo comando, senza sudo né Xcode
* **opencode-lens-monitor:** l'avvio al login segue l'app quando cambia cartella


### Documentazione

* **opencode-lens-monitor:** installazione da zip, guida all'aggiornamento e rilasci
* **opencode-lens-monitor:** installazione dal Source code

## [0.4.0] - 2026-10-17 (beta)

### Aggiunto
- Widget **Modello oggi**, piccolo: anello con la % del giorno di un modello (token di oggi su budget giornaliero) e la riga del reset.
- Widget **Modello oggi**, medio: % e badge del ritmo, grafico dei token ora per ora dal reset con la linea tratteggiata del ritmo medio.
- Widget **Modelli oggi**, medio: fino a 4 modelli con barra colorata dal ritmo, % scritta sulla barra e usati / budget; un modello oltre il budget o sopra il ritmo resta sempre visibile.
- Scelta del modello di **Modello oggi** con **Modifica widget**, tra quelli con budget giornaliero; senza scelta, il modello messo peggio.
- Versione della lens (da `/api/about`) nel popover ⓘ, letta una volta finché la lens resta attiva.

### Modificato
- Riga del reset in pannello e widget: "Reset in 04h 12m alle 06:00", ora in formato 24 ore; nei widget il tempo si aggiorna ogni minuto.
- I widget si ricaricano quando cambiano percentuale o ritmo di un modello, o i modelli di oggi, e un secondo dopo il reset del giorno.
- Piè di pagina: "OpenCode Monitor v…" al posto del link "OpenCode" seguito dalla versione, che sembrava la versione di OpenCode o della lens; la dashboard resta sul pulsante accanto.

### Rimosso
- Widget della settimana (anello e grafico dell'uso cumulato) e la scheda **Widget** delle impostazioni con la metrica. I widget della 0.3.0 sulla scrivania restano vuoti: vanno rimossi e sostituiti con quelli nuovi.

## [0.3.0] - 2026-10-17 (beta)

### Aggiunto
- **Server** nelle impostazioni: elenca le lens in ascolto su questo Mac (anche avviate con `npm start` o da un worktree) e permette di seguire la produzione (LaunchAgent) o una lens di sviluppo. Con una lens di sviluppo l'intestazione mostra **DEV** e Avvia/Ferma spariscono; se non risponde, la card di stato offre **Torna a Produzione**.
- Card **Oggi**: data, media dei budget giornalieri per modello (`LENS_MODEL_LIMITS`), token totali di oggi, barra e badge del modello messo peggio.
- Card **Modelli** del giorno di budget: token in/out, % e usati / budget per i modelli con budget, riga unica "Reset tra HH.MM · alle HH:MM". Lo stesso modello da due provider ha due righe; un modello oltre il budget resta sempre visibile.
- Pallino di stato nell'intestazione (verde con OpenCode collegato, arancio se non collegato).
- Impostazioni in tre schede (Generale, Server, Widget), senza scorrimento.
- `scripts/dev.sh`: build Debug e riavvio a ogni modifica dei sorgenti.

### Modificato
- Il nome mostrato da macOS è **OpenCode Monitor** (il bundle resta `OpenCode Lens Monitor.app`).
- Etichetta della barra su oggi: percentuale media dei budget per modello, pallino del colore del modello messo peggio. Il widget resta sulla settimana; la metrica nelle impostazioni vale solo per il widget.
- Tolte le card Settimana, Limiti e la vecchia Oggi (messaggi e costo).
- Sotto il budget la percentuale arriva al massimo a 99%. Durate come "5h 12 min".
- Clic sul widget con la lens ferma: apre le impostazioni invece della dashboard.

### Corretto
- `LENS_HOST` con a capo, spazi o interfaccia IPv6 non fa più chiudere app e widget.
- Un `launchctl print` fallito o in timeout non fa più sembrare ferma una lens che gira; Avvia/Ferma danno un errore chiaro. Un `bootout` lento non dà più un falso errore; un bootstrap rifiutato riprova dopo `enable`.
- Al cambio di lens: stato "verifica in corso", dati della lens nuova subito, quelli della precedente scartati; URL e token di ogni richiesta dalla stessa lens, e nell'App Group il widget non vede mai l'host di sviluppo con il token di produzione.
- "Avvia la lens all'accesso" disponibile solo con il LaunchAgent installato; i toggle non rimbalzano; gli errori spariscono dopo un minuto.
- Modelli contati dal giorno di budget anche se `/api/budget` non risponde; un giorno già finito non è più mostrato come oggi.
- Grafico del widget medio coerente con il badge del ritmo.

## [0.2.0]

Prima versione come repository autonomo, estratto da `opencode-library`; le versioni precedenti sono nella storia di quel repository.

