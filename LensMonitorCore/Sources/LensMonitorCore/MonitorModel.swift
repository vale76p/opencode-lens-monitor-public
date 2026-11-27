import Foundation
import Observation

/// Stato e azioni del menu. Orologio e attesa sono iniettabili per i test.
@MainActor
@Observable
public final class MonitorModel {
    /// Refresh massimi dopo Avvia/Ferma, uno al secondo.
    public static let convergeAttempts = 10
    /// Secondi dopo cui un errore sparisce dal pannello: il servizio può essersi ripreso da solo.
    public static let errorLifetime: TimeInterval = 60
    /// Secondi in cui un Ferma del Monitor può ancora arrivare a "non caricata" dopo `perform`
    /// (bootout in timeout, convergenza non raggiunta) senza passare per uno stop esterno.
    public static let ownStopGrace: TimeInterval = 60

    /// `.checking` finché il primo refresh (o quello dopo un cambio di lens) non dice com'è.
    public private(set) var state: ServiceState = .checking
    public private(set) var serviceAtLogin = false
    /// Il plist del LaunchAgent esiste: senza, "Avvia la lens all'accesso" non ha senso anche
    /// quando si segue una lens di sviluppo che risponde.
    public private(set) var serviceInstalled = false
    public private(set) var appLogin: LoginItemStatus = .disabled
    public private(set) var busy = false
    public private(set) var lastError: String?
    /// Sotto lo stato: la lens è stata fermata fuori dal Monitor e non è ripartita
    /// (`ExternalStop`); `nil` altrimenti.
    public private(set) var externalStopNote: String?
    public private(set) var usage: UsageSnapshot?
    /// Versione della lens seguita, letta una volta finché resta attiva (dopo un riavvio può essere
    /// un'altra: si rilegge); `nil` finché non si sa.
    public private(set) var lensVersion: String?
    /// Prossimo refresh dei dati; `nil` con il servizio non in esecuzione.
    public private(set) var nextUsageRefresh: Date?
    /// Secondi tra un refresh dei dati della lens e il successivo, scelti nelle impostazioni.
    public private(set) var usageInterval: TimeInterval
    /// Lens seguita da pannello e widget: il LaunchAgent o una lens di sviluppo, salvata nell'App Group.
    public private(set) var lensTarget: LensTarget
    /// Cresce quando va aperta la finestra delle impostazioni (clic sul widget con la lens giù);
    /// l'app la osserva dall'etichetta della barra, l'unica vista sempre presente.
    public private(set) var settingsRequests = 0
    /// Lens trovate dall'ultima ricerca, per il menu Server delle impostazioni.
    public private(set) var discoveredServers: [LensServer] = []
    /// Una ricerca è in corso (lsof, ps e /healthz possono metterci qualche secondo).
    public private(set) var discovering = false
    /// Chiamata quando cambia ciò che i widget mostrano o porta e token della lens;
    /// nell'app ricarica i widget. Non a ogni refresh: WidgetKit limita i reload giornalieri.
    @ObservationIgnored public var onUsageChange: (() -> Void)?
    @ObservationIgnored private var widgetKey: WidgetKey?
    /// Un refresh dei dati è in corso: una seconda richiesta (pannello aperto durante il poll) non parte.
    @ObservationIgnored private var refreshingUsage = false
    @ObservationIgnored private var lastErrorAt: Date?
    /// Inizio dell'ultimo refresh dei dati: cambiando intervallo il prossimo si conta da qui.
    @ObservationIgnored private var lastUsageStart: Date?
    /// Cresce a ogni cambio di lens: un refresh dei dati partito prima scarta il risultato e non
    /// blocca più quello della lens nuova (anche andando A → B → A durante la stessa lettura).
    @ObservationIgnored private var usageGeneration = 0
    /// Cresce a ogni refresh e a ogni azione: un refresh scrive solo se nel frattempo non ne è
    /// partito un altro, così un poll lento non riscrive uno stato vecchio sopra Avvia/Ferma.
    @ObservationIgnored private var refreshGeneration = 0

    @ObservationIgnored private let controller: any ServiceControlling
    @ObservationIgnored private let lens: any LensReading
    @ObservationIgnored private let discovery: any LensDiscovering
    @ObservationIgnored private let listener: any ListenerVerifying
    @ObservationIgnored private let loginItem: any LoginItemControlling
    @ObservationIgnored private let settings: any SharedSettingsStore
    @ObservationIgnored private let companionApp: () -> URL?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var startingSince: Date?
    /// Primo "non caricata" dopo uno stato caricato che il Monitor non ha fermato: da qui conta
    /// `ServiceState.externalRestartGrace`.
    @ObservationIgnored private var externalStopSince: Date?
    /// Ultimo Ferma del Monitor: il "non caricata" che ne segue non è uno stop esterno.
    @ObservationIgnored private var ownStopAt: Date?
    /// Ultimo stato di carico noto del LaunchAgent (un print `.unknown` lo lascia com'era). Lo stop
    /// esterno parte solo da un job caricato, non da `ServiceState`: al primo refresh un print
    /// muto passa da `resolve` e diventa `.failed`, e quel `.failed` non dice che il job c'era.
    @ObservationIgnored private var lastLoaded = false
    /// (pid, porta) di cui si è già verificato che ascolta il job: un solo `lsof` a ogni riavvio della
    /// lens invece di uno per giro. Gli esiti negativi non si memorizzano.
    @ObservationIgnored private var verifiedListener: [Int]?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// L'attesa tra due giri del poll: un'azione dell'utente la annulla per rifare subito il giro.
    @ObservationIgnored private var napTask: Task<Void, Never>?
    /// Un'azione dell'utente è arrivata mentre il poll faceva il suo refresh (non c'era attesa da
    /// annullare): il giro successivo parte senza dormire.
    @ObservationIgnored private var wakeRequested = false
    /// Famiglia di stati corrente e da quando (`PollPacing`): più resta uguale, più il poll rallenta.
    @ObservationIgnored private var pacingGroup = PollPacing.Group.waiting
    @ObservationIgnored private var pacingSince: Date?
    /// Ultima azione dell'utente (Avvia/Ferma/Riavvia, pannello aperto, cambio di Server).
    @ObservationIgnored private var lastUserActionAt: Date?

    public init(
        controller: any ServiceControlling,
        lens: any LensReading,
        discovery: any LensDiscovering,
        loginItem: any LoginItemControlling,
        settings: any SharedSettingsStore,
        listener: any ListenerVerifying = NoListenerCheck(),
        companionApp: @escaping () -> URL? = { nil },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.controller = controller
        self.lens = lens
        self.discovery = discovery
        self.loginItem = loginItem
        self.settings = settings
        self.listener = listener
        self.companionApp = companionApp
        self.now = now
        self.sleep = sleep
        let config = settings.load()
        self.lensTarget = config.target
        self.usageInterval = config.refreshInterval
    }

    public var dashboardURL: URL { lens.dashboardURL }

    /// «Apri la dashboard»: l'app OpenCode Lens se è installata e si segue il LaunchAgent, altrimenti
    /// il browser. L'app si cerca a ogni clic: può comparire o sparire mentre il Monitor è aperto.
    public var dashboardDestination: DashboardDestination {
        DashboardDestination.resolve(target: lensTarget, dashboardURL: lens.browserURL, companionApp: companionApp())
    }

    /// Host e porta della lens, per il popover della riga di refresh (es. 127.0.0.1:4777).
    public var lensAddress: String { dashboardURL.absoluteString.replacingOccurrences(of: "http://", with: "") }

    /// Voci del menu Server: Produzione, le lens trovate e la scelta corrente.
    public var serverOptions: [LensServerOption] {
        LensServerOption.list(service: lens.serviceEndpoint, discovered: discoveredServers, selected: lensTarget)
    }

    public var canToggleServiceAtLogin: Bool { serviceInstalled && !busy }

    /// Avvia e Ferma agiscono sul LaunchAgent: con una lens di sviluppo non c'è nulla da controllare.
    public var primaryAction: ServiceAction? {
        lensTarget == .service ? state.primaryAction : nil
    }

    /// Pannello ed etichetta calcolati adesso (il tempo al reset cambia a ogni lettura).
    public var panel: PanelState {
        PanelState.make(service: state, usage: usage, lensVersion: lensVersion, now: now())
    }

    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let installed = controller.isInstalled
        let followsService = lensTarget == .service
        // Con una lens di sviluppo lo stato del LaunchAgent non conta, solo se lei risponde.
        let load: LoadState = installed && followsService ? await controller.status() : .notLoaded
        var health = HealthFetch.unavailable
        var foreignListener = false
        if !followsService {
            health = await lens.health()
        } else if case .loaded(running: true, let pid) = load {
            // Il Bearer va solo al processo del job: prima si controlla chi ascolta sulla porta.
            switch await listenerCheck(pid: pid, port: lens.endpoint.port) {
            case .verified: health = await lens.health()
            case .foreign: foreignListener = true
            case .unverified: break
            }
        }
        let atLogin = installed ? await controller.isEnabledAtLogin() : false
        guard generation == refreshGeneration else { return }
        let wasLoaded = lastLoaded
        if followsService {
            switch load {
            case .loaded: lastLoaded = true
            case .notLoaded: lastLoaded = false
            case .unknown: break
            }
        }
        let wasRunning = state.isRunning
        let startingFor = startingSince.map { now().timeIntervalSince($0) } ?? 0
        var resolved: ServiceState
        // Con `launchctl print` muto lo stato resta quello di prima e lo stop esterno non si tocca:
        // un print intermittente farebbe altrimenti ripartire la finestra del riavvio.
        var detectsExternalStop = followsService
        if !followsService {
            resolved = ServiceState.resolve(local: health)
        } else if case .unknown = load, state != .checking, state != .notInstalled {
            detectsExternalStop = false
            // launchctl print non ha risposto: meglio lo stato di prima che un "fermo" falso.
            // Un avvio però non può durare all'infinito: scaduto il timeout si dichiara fallito,
            // come farebbe resolve (che qui non passa).
            if state == .starting && startingFor >= ServiceState.startTimeout {
                resolved = .failed("launchctl non risponde e l'avvio non finisce")
            } else if state == .restarting, let since = externalStopSince,
                      now().timeIntervalSince(since) >= ServiceState.externalRestartGrace {
                // Nemmeno il riavvio può durare all'infinito: scaduta la finestra la lens è ferma.
                resolved = .stopped
                externalStopNote = Self.externalStopNote(atLogin: atLogin)
            } else {
                resolved = state
            }
        } else {
            resolved = ServiceState.resolve(installed: installed, load: load, health: health, startingFor: startingFor)
        }
        if foreignListener {
            resolved = .failed(ServiceState.foreignListenerMessage)
        }
        if detectsExternalStop {
            resolved = resolveExternalStop(resolved, wasLoaded: wasLoaded, atLogin: atLogin)
        }
        if let at = lastErrorAt, now().timeIntervalSince(at) >= Self.errorLifetime {
            lastError = nil
            lastErrorAt = nil
        }
        switch resolved {
        case .starting:
            if startingSince == nil { startingSince = now() }
        case .failed:
            // Un errore di launchctl non è un avvio: se il timer partisse qui, il primo
            // "caricato ma non in esecuzione" andrebbe in errore prima dei 15 s.
            break
        default:
            startingSince = nil
        }
        state = resolved
        let group = PollPacing.Group(resolved)
        if group != pacingGroup || pacingSince == nil {
            pacingGroup = group
            pacingSince = now()
        }
        serviceInstalled = installed
        serviceAtLogin = atLogin
        appLogin = loginItem.status
        syncSharedSettings()
        if !state.isRunning {
            nextUsageRefresh = nil
            lensVersion = nil
        } else if !wasRunning || nextUsageRefresh.map({ now() >= $0 }) ?? true {
            await refreshUsage()
        }
    }

    /// Chi ascolta sulla porta è il job? Senza pid (print che non lo dà) non si può dire.
    private func listenerCheck(pid: Int?, port: Int) async -> ListenerCheck {
        guard let pid else { return .unverified }
        if verifiedListener == [pid, port] { return .verified }
        let check = await listener.check(pid: pid, port: port)
        verifiedListener = check == .verified ? [pid, port] : nil
        return check
    }

    /// Uno stop fuori dal Monitor (le Impostazioni della lens fanno bootout + bootstrap) è
    /// `.restarting` per `externalRestartGrace` secondi; se la lens non torna resta `.stopped`
    /// con una nota. `!busy` esclude il Ferma del Monitor in corso (`perform` arriva a `.stopped`
    /// con `busy` acceso), `ownStopAt` quello finito dopo `perform`. La finestra si apre solo se il
    /// job era caricato al giro prima (`wasLoaded`).
    private func resolveExternalStop(_ resolved: ServiceState, wasLoaded: Bool, atLogin: Bool) -> ServiceState {
        if let at = ownStopAt, now().timeIntervalSince(at) >= Self.ownStopGrace { ownStopAt = nil }
        guard resolved == .stopped else {
            externalStopSince = nil
            externalStopNote = nil
            return resolved
        }
        if ownStopAt != nil {
            ownStopAt = nil
        } else if externalStopSince == nil, !busy, wasLoaded {
            externalStopSince = now()
        }
        guard let since = externalStopSince else { return resolved }
        if now().timeIntervalSince(since) < ServiceState.externalRestartGrace { return .restarting }
        externalStopNote = Self.externalStopNote(atLogin: atLogin)
        return resolved
    }

    /// Si ricalcola a ogni refresh: segue il toggle "Avvia la lens all'accesso".
    private static func externalStopNote(atLogin: Bool) -> String {
        atLogin ? ExternalStop.otherNote : ExternalStop.disabledNote
    }

    /// Ricarica budget e modelli dalla lens; solo con il servizio in esecuzione.
    /// Un fallimento lascia i dati di prima, segnati come vecchi, senza `lastError`.
    public func refreshUsage() async {
        guard state.isRunning, !refreshingUsage else { return }
        let generation = usageGeneration
        refreshingUsage = true
        defer { if generation == usageGeneration { refreshingUsage = false } }
        let started = now()
        lastUsageStart = started
        nextUsageRefresh = started.addingTimeInterval(usageInterval)
        let budget = await lens.budget()
        // Modelli del giorno di budget della lens (da LENS_RESET_HOUR). Se /api/budget non risponde
        // vale il giorno del report di prima finché è in corso; mezzanotte solo senza /api/budget.
        var dayStart = Calendar.current.startOfDay(for: started)
        if case .ok(let report) = budget {
            dayStart = report.day.from
        } else if budget == .unavailable, let day = usage?.budget?.day, day.to > started {
            dayStart = day.from
        }
        // I pesi della percentuale di oggi: con un modello solo non cambiano nulla, e la chiamata si
        // risparmia.
        var history: [ModelUsage]?
        if case .ok(let report) = budget, report.day.countedModels.count >= 2,
           let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: dayStart) {
            history = await lens.models(since: weekAgo)
        }
        let models = await lens.models(since: dayStart)
        // Nel frattempo si è scelta un'altra lens: questi dati sono della precedente.
        guard generation == usageGeneration else { return }

        var next = usage ?? UsageSnapshot()
        switch budget {
        case .ok(let report):
            next.budget = report
            next.fetchedAt = started
            // Il giorno finito non è più "oggi" (PanelState lo toglie): il prossimo refresh non
            // può aspettare l'intervallo intero, come già fa il widget (WidgetContent.nextUpdate).
            nextUsageRefresh = Self.nextUsageRefresh(after: started, interval: usageInterval, dayEnd: report.day.to)
        case .unavailable:
            break
        }
        if let models {
            next.models = models
            next.modelsFetchedAt = started
        }
        if let history { next.history = history }
        next.stale = budget == .unavailable || models == nil
        if next != usage { usage = next }
        // A ogni giro: una lens aggiornata da un riavvio KeepAlive che il poll non ha visto
        // resterebbe altrimenti con la versione (e l'avviso) di prima.
        let version = await lens.version()
        // Un `/api/about` fallito una volta non toglie l'avviso della lens vecchia.
        if generation == usageGeneration { lensVersion = version ?? lensVersion }
        // Anche qui: durante la lettura della versione si può essere passati a un'altra lens, e la
        // sua chiave verrebbe sovrascritta da quella della precedente, con un reload in più.
        guard generation == usageGeneration else { return }
        let key = WidgetKey(next)
        guard key != widgetKey else { return }
        widgetKey = key
        onUsageChange?()
    }

    /// Host, porta e token del plist nell'App Group, per il widget; scrive solo quando cambiano.
    private func syncSharedSettings() {
        guard settings.reachesWidget else { return }
        let endpoint = lens.endpoint
        var config = settings.load()
        guard config.host != endpoint.host || config.port != endpoint.port || config.token != endpoint.token else { return }
        config.host = endpoint.host
        config.port = endpoint.port
        config.token = endpoint.token
        settings.save(config)
        onUsageChange?()
    }

    /// Segue un'altra lens: i dati della precedente spariscono e il refresh riparte subito,
    /// così pannello e widget non mostrano numeri di un server diverso.
    public func selectTarget(_ target: LensTarget) async {
        guard target != lensTarget, !busy else { return }
        userActed()
        pacingSince = nil
        var config = settings.load()
        config.target = target
        settings.save(config)
        lensTarget = target
        // Fino al refresh lo stato è della lens di prima: Ferma o Torna a Produzione sarebbero falsi.
        state = .checking
        refreshGeneration += 1
        usageGeneration += 1
        refreshingUsage = false
        startingSince = nil
        externalStopSince = nil
        externalStopNote = nil
        ownStopAt = nil
        lastLoaded = false
        usage = nil
        nextUsageRefresh = nil
        widgetKey = nil
        lensVersion = nil
        await refresh()
    }

    /// Nuovo intervallo dei dati, salvato nell'App Group. Il conto alla rovescia riparte
    /// dall'ultimo refresh: accorciandolo, se è già scaduto il dato arriva al giro di poll seguente.
    public func setUsageInterval(_ seconds: TimeInterval) {
        guard RefreshInterval.choices.contains(seconds), seconds != usageInterval else { return }
        var config = settings.load()
        config.refreshInterval = seconds
        settings.save(config)
        usageInterval = seconds
        if nextUsageRefresh != nil, let lastUsageStart {
            nextUsageRefresh = Self.nextUsageRefresh(after: lastUsageStart, interval: seconds, dayEnd: usage?.budget?.day.to)
        }
    }

    /// Tra `interval` secondi, o un secondo dopo il reset del giorno di budget se arriva prima.
    /// Un giorno già finito non conta: una lens ferma sul passato non deve far rileggere a ogni poll.
    static func nextUsageRefresh(after start: Date, interval: TimeInterval, dayEnd: Date?) -> Date {
        let regular = start.addingTimeInterval(interval)
        guard let dayEnd, dayEnd > start else { return regular }
        return min(regular, dayEnd.addingTimeInterval(1))
    }

    /// Clic sul widget: la dashboard se la lens risponde, altrimenti le impostazioni (Server e
    /// Servizio), invece di una pagina di errore nel browser.
    public func widgetClicked() -> DashboardDestination? {
        if state.isRunning { return dashboardDestination }
        settingsRequests += 1
        return nil
    }

    /// Cerca le lens in ascolto su questo Mac.
    public func discoverServers() async {
        guard !discovering else { return }
        discovering = true
        defer { discovering = false }
        discoveredServers = await discovery.servers()
    }

    public func start() async {
        userActed()
        ownStopAt = nil
        await perform({ try await controller.start() }, until: { $0.isRunning })
    }

    public func stop() async {
        userActed()
        // Prima di `perform`: il "non caricata" può arrivare anche dopo (bootout in timeout).
        ownStopAt = now()
        await perform({ try await controller.stop() }, until: { $0 == .stopped })
    }

    /// Passa dalla stessa guardia di Avvia/Ferma: durante Avvia da disabilitato il disable
    /// finale annullerebbe la scelta.
    public func setServiceAtLogin(_ enabled: Bool) async {
        guard !busy else { return }
        userActed()
        busy = true
        defer { busy = false }
        refreshGeneration += 1
        // Subito il valore scelto, poi quello vero: il toggle non torna indietro durante launchctl.
        serviceAtLogin = enabled
        do {
            try await controller.setEnabledAtLogin(enabled)
            report(nil)
        } catch {
            report(error)
        }
        serviceAtLogin = await controller.isEnabledAtLogin()
    }

    public func setAppAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            report(nil)
        } catch {
            report(error)
        }
        appLogin = loginItem.status
    }

    /// Secondi fino al prossimo giro del poll (`PollPacing`): 5 con la lens in avvio o un'azione in
    /// corso o appena fatta, 15 con la lens in esecuzione, sempre meno spesso quando fermo o in
    /// errore da un pezzo.
    public var pollInterval: TimeInterval {
        let current = now()
        return PollPacing.interval(
            group: pacingGroup,
            busy: busy,
            stableFor: pacingSince.map { current.timeIntervalSince($0) } ?? 0,
            sinceUserAction: lastUserActionAt.map { current.timeIntervalSince($0) },
            untilUsageRefresh: nextUsageRefresh.map { $0.timeIntervalSince(current) }
        )
    }

    /// Un'azione dell'utente riporta il poll a 5 s: sveglia l'attesa in corso, anche se era a 60 s,
    /// e il giro riparte subito.
    private func userActed() {
        lastUserActionAt = now()
        wakeRequested = true
        napTask?.cancel()
    }

    /// Il pannello si è aperto: dati freschi subito, e il poll torna a 5 s per un po' (non si sa
    /// quando si chiude, quindi la finestra è a tempo, `PollPacing.boostWindow`).
    public func panelOpened() async {
        userActed()
        await refreshUsage()
    }

    /// Refresh periodico a ritmo adattivo (`pollInterval`); salta il giro mentre è in corso un'azione.
    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.wakeRequested = false
                if !self.busy { await self.refresh() }
                if self.wakeRequested { continue }
                let nap = Task { await self.sleep(.seconds(self.pollInterval)) }
                self.napTask = nap
                await nap.value
            }
        }
    }

    /// Ferma il polling: lo usano solo i test per pulizia tra un caso e l'altro; l'app polla
    /// per tutta la vita del processo.
    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        napTask?.cancel()
        napTask = nil
    }

    private func report(_ error: (any Error)?) {
        lastError = error.map(Self.message(for:))
        lastErrorAt = error == nil ? nil : now()
    }

    /// Prima riga del messaggio, al massimo 120 caratteri.
    public static func message(for error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }

    /// Agisce solo sul LaunchAgent seguito: un clic partito prima di un cambio di Server arriva
    /// dopo che `lensTarget` è già una lens di sviluppo, e le viste non possono più fermarlo.
    private func perform(_ action: () async throws -> Void, until converged: (ServiceState) -> Bool) async {
        guard !busy, lensTarget == .service else { return }
        externalStopSince = nil
        externalStopNote = nil
        busy = true
        defer { busy = false }
        refreshGeneration += 1
        do {
            try await action()
            report(nil)
        } catch {
            report(error)
            await refresh()
            return
        }
        for attempt in 1...Self.convergeAttempts {
            await refresh()
            if converged(state) || attempt == Self.convergeAttempts { return }
            await sleep(.seconds(1))
        }
    }
}

/// Ciò che i widget mostrano, senza i token esatti né il tempo al reset, che cambiano a ogni
/// refresh: se resta uguale non serve ricaricarli (si aggiornano comunque da soli ogni 15 minuti).
private struct WidgetKey: Equatable {
    let day: Date?
    /// Percentuale e ritmo di ogni modello con budget: anello, grafico e barre.
    let budgets: [String]
    /// Modelli usati oggi: una riga nuova nel riepilogo.
    let models: Set<String>

    init?(_ usage: UsageSnapshot?) {
        guard let usage, usage.budget != nil else { return nil }
        day = usage.budget?.day.from
        budgets = (usage.budget?.day.models ?? []).map { "\($0.model) \($0.displayPercent ?? "-") \($0.pace.rawValue)" }
        models = Set((usage.models ?? []).map { Format.modelKey($0.key) })
    }
}
