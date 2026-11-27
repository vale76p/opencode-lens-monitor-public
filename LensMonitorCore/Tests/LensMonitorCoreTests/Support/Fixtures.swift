/// Output di launchctl scritti a mano con valori finti: l'output reale
/// contiene l'environment ereditato dal servizio e non va mai committato.
enum Fixtures {
    static let printRunning = """
    gui/501/local.opencode-lens = {
    \tactive count = 1
    \tpath = /Users/test/Library/LaunchAgents/local.opencode-lens.plist
    \ttype = LaunchAgent
    \tstate = running

    \tprogram = /opt/homebrew/bin/node
    \tinherited environment = {
    \t\tSECRET_TOKEN => non-un-segreto-vero
    \t}

    \tenvironment = {
    \t\tLENS_PORT => 4777
    \t}

    \tdomain = gui/501 [100021]
    \truns = 5
    \tpid = 85289
    \tlast exit code = 0

    \tresource coalition = {
    \t\tID = 61571
    \t\ttype = resource
    \t\tstate = active
    \t\tactive count = 1
    \t}
    }
    """

    static let printNotRunning = """
    gui/501/local.opencode-lens = {
    \tactive count = 0
    \tpath = /Users/test/Library/LaunchAgents/local.opencode-lens.plist
    \ttype = LaunchAgent
    \tstate = not running

    \tprogram = /opt/homebrew/bin/node
    \truns = 2
    \tlast exit code = 1
    }
    """

    /// Primo livello non in esecuzione, blocco annidato con "state = running" e un pid.
    static let printNestedRunning = """
    gui/501/local.opencode-lens = {
    \tstate = not running
    \tjetsam coalition = {
    \t\tstate = running
    \t\tpid = 4242
    \t}
    }
    """

    static let disabledWithLens = """
    \tdisabled services = {
    \t\t"com.example.other" => enabled
    \t\t"local.opencode-lens-monitor" => enabled
    \t\t"local.opencode-lens" => disabled
    \t}

    \tlogin item associations = {
    \t}
    """

    static let enabledWithLens = """
    \tdisabled services = {
    \t\t"local.opencode-lens" => enabled
    \t}
    """

    /// Solo un'etichetta che inizia allo stesso modo: non deve corrispondere.
    static let disabledWithoutLens = """
    \tdisabled services = {
    \t\t"com.example.other" => disabled
    \t\t"local.opencode-lens-monitor" => disabled
    \t}
    """
}
