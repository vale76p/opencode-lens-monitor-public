import Foundation
import Testing

/// install.sh della radice del repo, lanciato da una cartella "estratta dallo zip" in una HOME
/// temporanea. Nel PATH ci sono solo comandi finti (bin/) e link a strumenti innocui (tools/):
/// un osascript, open, pluginkit, lsregister, defaults o launchctl veri danno "command not
/// found", così i test non possono chiudere, sostituire o registrare l'app installata su questo
/// Mac, né toccare login item o launchd. La /Applications di sistema è una cartella temporanea
/// (LENS_MONITOR_SYSTEM_APPS).
@Suite struct InstallScriptTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let script = root.appending(path: "install.sh").path
    static let name = "OpenCode Lens Monitor.app"

    /// Strumenti veri ammessi: leggono o copiano file, nient'altro.
    static let tools = [
        "awk", "basename", "bash", "cat", "chmod", "cp", "cut", "date", "dirname", "ditto", "find", "grep", "head",
        "id", "ls", "mkdir", "mktemp", "mv", "plutil", "rm", "sed", "tail", "tee", "tr", "xattr",
    ]

    static let fakes: [String: String] = [
        "pgrep": """
            if [[ " $* " == *" chronod "* ]]; then
              [[ -s "$STATE/chronod" ]] || exit 1
              cat "$STATE/chronod"
              exit 0
            fi
            [[ -s "$STATE/running" ]] || exit 1
            while IFS= read -r p; do echo "4242 $p/Contents/MacOS/OpenCode Lens Monitor"; done < "$STATE/running"
            """,
        "osascript": #"[[ -n "${FAKE_QUIT_FAILS:-}" ]] || : > "$STATE/running""#,
        "open": """
            [[ -z "${FAKE_OPEN_FAILS:-}" ]] || exit 1
            echo "$1" >> "$STATE/running"
            # the Monitor writes its login item status at launch (RecordedLoginItem)
            if [[ -f "$STATE/login" ]]; then
              cp "$STATE/login" "$STATE/defaults.loginItemStatus"
              if [[ "$(cat "$STATE/login")" != disabled ]]; then echo "$1" > "$STATE/defaults.loginItemPath"; fi
            fi
            """,
        "defaults": """
            [[ "$1" == read && "$2" == local.opencode-lens-monitor && -f "$STATE/defaults.$3" ]] || exit 1
            cat "$STATE/defaults.$3"
            """,
        "pluginkit": """
            line() { printf '     local.opencode-lens-monitor.widget(1.0)\\tUUID\\t2026-10-17 08:53:50 +0000\\t%s\\n' "$1"; }
            if [[ "$1" == -a ]]; then
              [[ -n "${FAKE_WIDGET_STAYS:-}" ]] || echo "$2" > "$STATE/widget"
              exit 0
            fi
            if [[ -f "$STATE/widget" ]]; then line "$(cat "$STATE/widget")"; fi
            if [[ " $* " == *" -A "* && -f "$STATE/widgets" ]]; then
              while IFS= read -r p; do line "$p"; done < "$STATE/widgets"
            fi
            exit 0
            """,
        "codesign": """
            case "$1" in
              --verify)
                for arg in "$@"; do
                  case "$arg" in -R=*) [[ "$arg" == *"${FAKE_TEAM:-HS87DR6TBX}"* ]] || exit 3 ;; esac
                done
                exit "${FAKE_CODESIGN_VERIFY:-0}" ;;
            esac
            """,
        // solo il `print` del job del widget di chronod, che registra da dove lo lancia
        "launchctl": """
            [[ "$1" == print && -f "$STATE/chronod" && -f "$STATE/widget-job" ]] || exit 113
            [[ "$2" == "pid/$(cat "$STATE/chronod")/local.opencode-lens-monitor.widget" ]] || exit 113
            printf 'pid/%s/local.opencode-lens-monitor.widget = {\n' "$(cat "$STATE/chronod")"
            printf '\tpath = %s\n\tstate = not running\n' "$(cat "$STATE/widget-job")"
            printf '\tprogram = %s/Contents/MacOS/OpenCodeLensWidget\n}\n' "$(cat "$STATE/widget-job")"
            """,
        // launchd riavvia chronod con un altro dominio pid: il job vecchio non c'è più
        "pkill": """
            [[ -z "${FAKE_PKILL_FAILS:-}" ]] || exit 1
            rm -f "$STATE/widget-job"
            echo 5151 > "$STATE/chronod"
            """,
        "lsregister": "",
        "curl": #"exit "${FAKE_CURL:-7}""#,
        "sw_vers": #"echo "${FAKE_MACOS:-26.1}""#,
        "sleep": "",
    ]

    final class Fixture {
        let dir: String
        let src: String
        let home: String
        let system: String
        let state: String
        var dest: String { home + "/Applications/" + InstallScriptTests.name }
        var systemApp: String { system + "/" + InstallScriptTests.name }
        var newApp: String { src + "/" + InstallScriptTests.name }
        var trash: String { home + "/.Trash" }

        init(app: Bool = true, sources: Bool = false) throws {
            let fm = FileManager.default
            let base = fm.temporaryDirectory.appending(path: "lens-monitor-install-\(UUID().uuidString)").path
            try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
            // /var/folders è un link simbolico a /private/var: ogni percorso stampato dallo script è
            // quello reale (realpath; URL.resolvingSymlinksInPath tiene /var)
            dir = String(cString: realpath(base, nil))
            src = dir + "/dl/opencode-lens-monitor"
            home = dir + "/home"
            system = dir + "/system-apps"
            state = dir + "/state"
            let bin = dir + "/bin"
            for d in [src, home + "/Downloads", home + "/Desktop", home + "/Documents", system, state, bin, dir + "/tools"] {
                try fm.createDirectory(atPath: d, withIntermediateDirectories: true)
            }
            try fm.copyItem(atPath: InstallScriptTests.script, toPath: src + "/install.sh")
            for (name, body) in InstallScriptTests.fakes {
                let text = "#!/bin/bash\necho \"\(name) $*\" >> \"$STATE/log\"\n\(body)\n"
                try write(text, to: bin + "/" + name, mode: 0o755)
            }
            for tool in InstallScriptTests.tools {
                let real = ["/usr/bin/" + tool, "/bin/" + tool].first { fm.isExecutableFile(atPath: $0) }!
                try fm.createSymbolicLink(atPath: dir + "/tools/" + tool, withDestinationPath: real)
            }
            if app { try makeApp(at: newApp, version: "9.9.9", build: "90909") }
            // lo zip «Source code»: i sorgenti e un build-clt.sh che "compila" un'app modello
            if sources {
                try makeApp(at: state + "/template.app", version: "9.9.9", build: "90909")
                try write("    MARKETING_VERSION: \"9.9.9\" # x-release-please-version\n", to: src + "/project.yml")
                try write(InstallScriptTests.fakeBuild, to: src + "/scripts/build-clt.sh", mode: 0o755)
            }
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: system)
            try? FileManager.default.removeItem(atPath: dir)
        }

        func write(_ text: String, to path: String, mode: Int = 0o644) throws {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: URL(filePath: path))
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
        }

        func makeApp(at path: String, version: String, build: String) throws {
            let info: [String: Any] = [
                "CFBundleIdentifier": "local.opencode-lens-monitor",
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try FileManager.default.createDirectory(atPath: path + "/Contents/MacOS", withIntermediateDirectories: true)
            try data.write(to: URL(filePath: path + "/Contents/Info.plist"))
            try write("versione \(version)", to: path + "/Contents/MacOS/OpenCode Lens Monitor", mode: 0o755)
            try write("widget", to: path + "/Contents/PlugIns/OpenCodeLensWidget.appex/Contents/MacOS/OpenCodeLensWidget", mode: 0o755)
        }

        /// Il servizio della lens come lo lascia `opencode-lens service install`, da una cartella con package.json.
        func installLens(version: String = "0.12.1") throws {
            let appDir = home + "/Applications/opencode-lens"
            try write("{\n  \"name\": \"opencode-lens\",\n  \"version\": \"\(version)\"\n}\n", to: appDir + "/package.json")
            let plist: [String: Any] = [
                "Label": "local.opencode-lens",
                "WorkingDirectory": appDir,
                "EnvironmentVariables": ["LENS_PORT": "4777", "LENS_TOKEN": "segreto-di-prova"],
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try write("", to: lensPlist)
            try data.write(to: URL(filePath: lensPlist))
        }

        var lensPlist: String { home + "/Library/LaunchAgents/local.opencode-lens.plist" }

        func setState(_ name: String, _ text: String) throws { try write(text, to: state + "/" + name) }

        func run(_ args: [String] = [], env: [String: String] = [:]) throws -> (status: Int32, out: String, err: String) {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/bash")
            process.arguments = [src + "/install.sh"] + args
            process.environment = [
                "HOME": home,
                "PATH": dir + "/bin:" + dir + "/tools",
                "STATE": state,
                // il locale del Terminale su macOS, dove bash 3.2 legge male `$VAR…`
                "LC_ALL": "en_US.UTF-8",
                "LENS_MONITOR_SYSTEM_APPS": system,
                "TMPDIR": dir,
            ].merging(env) { $1 }
            let out = dir + "/out.txt", err = dir + "/err.txt"
            FileManager.default.createFile(atPath: out, contents: nil)
            FileManager.default.createFile(atPath: err, contents: nil)
            process.standardOutput = try FileHandle(forWritingTo: URL(filePath: out))
            process.standardError = try FileHandle(forWritingTo: URL(filePath: err))
            try process.run()
            process.waitUntilExit()
            let read = { (p: String) in (try? String(contentsOfFile: p, encoding: .utf8)) ?? "" }
            return (process.terminationStatus, read(out), read(err))
        }

        var calls: [String] {
            ((try? String(contentsOfFile: state + "/log", encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }

        func version(_ app: String) -> String? {
            (NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleShortVersionString"]) as? String
        }

        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

        func trashed() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: trash)) ?? []).sorted() }

        /// Ogni file sotto HOME e nelle Applicazioni di sistema, con il contenuto.
        func snapshot() -> [String: Data] {
            var all: [String: Data] = [:]
            for base in [home, system] {
                guard let e = FileManager.default.enumerator(atPath: base) else { continue }
                while let rel = e.nextObject() as? String {
                    let path = base + "/" + rel
                    all[path] = FileManager.default.contents(atPath: path) ?? Data()
                }
            }
            return all
        }
    }

    static let fakeBuild = """
        #!/bin/bash
        echo "build-clt $*" >> "$STATE/log"
        if [[ "$1" == --check ]]; then
          echo "Command Line Tools: SDK macOS 27.0"
          echo "firma: ${FAKE_SIGN:-team}"
          exit 0
        fi
        [[ -z "${FAKE_BUILD_FAILS:-}" ]] || { echo "error: compilazione finta fallita" >&2; exit 1; }
        ditto "$STATE/template.app" "$1/OpenCode Lens Monitor.app"
        echo "OK: $1/OpenCode Lens Monitor.app"
        echo "firma: ${FAKE_SIGN:-team}"

        """

    /// Effetti sul sistema vero, se non ci fossero i finti.
    static let sideEffects = ["open ", "osascript ", "lsregister ", "pluginkit -a", "pkill "]

    static let appex = "/Contents/PlugIns/OpenCodeLensWidget.appex"
    static let pkillChronod = "pkill -U \(getuid()) -x chronod"

    // MARK: - static checks

    @Test func sintassiBash() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-n", Self.script]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// bash 3.2 (macOS) in un locale UTF-8 legge i byte di un carattere come «…» subito dopo
    /// `$NAME` come parte del nome: "APP…: unbound variable" con set -u.
    @Test func nessunaVariabileSeguitaDaUnCarattereNonASCII() throws {
        for file in ["install.sh", "scripts/package.sh", "scripts/build-clt.sh", "scripts/dev.sh", "scripts/test.sh"] {
            let text = try String(contentsOf: Self.root.appending(path: file), encoding: .utf8)
            let bad = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().filter { _, line in
                line.contains(/\$[A-Za-z_][A-Za-z0-9_]*[^\t -~]/)
            }.map { "\(file):\($0.offset + 1): \($0.element)" }
            #expect(bad.isEmpty, "\(bad)")
        }
    }

    @Test func niente_sudo_launchctl_cpR() throws {
        let text = try String(contentsOfFile: Self.script, encoding: .utf8)
        let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
        #expect(!code.contains(/(^|[;&|(]\s*)sudo\s/.anchorsMatchLineEndings()))
        // solo il `launchctl print` del job di chronod, che non cambia niente
        #expect(!code.replacingOccurrences(of: #"launchctl print "pid/"#, with: "").contains("launchctl"))
        // e nessun processo ucciso oltre al chronod dell'utente
        let kills = code.split(separator: "\n").filter { $0.contains(/(^|[;&|]|\$\()\s*(kill|killall|pkill)\s/) }
        #expect(kills == [#"  pkill -U "$(id -u)" -x chronod >/dev/null 2>&1 || true"#], "\(kills)")
        #expect(!code.contains("cp -R"))
        #expect(!code.contains("rm -rf \"$SYSTEM_APP\""))
    }

    /// scripts/build-clt.sh compila con i Command Line Tools, che non hanno il plugin delle macro
    /// di SwiftUI (c'è solo in Xcode): dall'SDK di macOS 27 @State è una di quelle macro.
    @Test func nessunaMacroDiSwiftUINeiSorgenti() throws {
        var bad: [String] = []
        for dir in ["OpenCodeLensMonitor", "OpenCodeLensWidget", "Shared"] {
            let base = Self.root.appending(path: dir).path
            for case let rel as String in FileManager.default.enumerator(atPath: base)! where rel.hasSuffix(".swift") {
                let text = try String(contentsOfFile: base + "/" + rel, encoding: .utf8)
                for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") && line.contains(/@(State|Entry|Previewable)\b|#Preview\b/) {
                    bad.append("\(dir)/\(rel):\(i + 1): \(line)")
                }
            }
        }
        #expect(bad.isEmpty, "\(bad)")
    }

    @Test func buildCLTEntraDaNSExtensionMain() throws {
        let path = Self.root.appending(path: "scripts/build-clt.sh").path
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-n", path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("-Xlinker -e -Xlinker _NSExtensionMain"), "senza, ExtensionFoundation ferma il widget all'avvio")
        #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: "scripts/clt/Metadata.appintents/extract.actionsdata").path))
    }

    // MARK: - --check

    @Test func checkSenzaNienteInstallato() throws {
        let f = try Fixture()
        let before = f.snapshot()
        let r = try f.run(["--check"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.err.isEmpty, "\(r.err)")
        #expect(r.out.contains("Versione da installare: 9.9.9 (build 90909), da \(f.src)"), "\(r.out)")
        #expect(r.out.contains("Non c'è: \(f.dest)"))
        #expect(r.out.contains("Non c'è: \(f.systemApp)"))
        #expect(r.out.contains("In esecuzione: no"))
        #expect(r.out.contains("Widget: nessuno registrato"))
        #expect(r.out.contains("Lens: non installata"))
        #expect(r.out.contains("Solo controllo: nessuna modifica."))
        #expect(f.snapshot() == before)
        #expect(!f.calls.contains { c in Self.sideEffects.contains { c.hasPrefix($0) } }, "\(f.calls)")
    }

    @Test func checkConVersioniCopieLensELoginItem() throws {
        let f = try Fixture()
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.makeApp(at: f.home + "/Downloads/vecchio/" + Self.name, version: "0.3.0", build: "4")
        try f.installLens()
        try f.setState("running", f.systemApp + "\n")
        try f.setState("widget", f.systemApp + "/Contents/PlugIns/OpenCodeLensWidget.appex")
        try f.setState("widgets", f.home + "/Library/Caches/dev/" + Self.name + "/Contents/PlugIns/OpenCodeLensWidget.appex\n")
        try f.setState("defaults.loginItemStatus", "enabled")
        try f.setState("defaults.loginItemPath", f.systemApp)
        let before = f.snapshot()
        let r = try f.run(["--check"], env: ["FAKE_CURL": "0"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.out.contains("Installata: \(f.systemApp), 0.4.0 (build 5)"))
        #expect(r.out.contains("In esecuzione: \(f.systemApp)"))
        #expect(r.out.contains("Avvio al login: attivo, da \(f.systemApp)"))
        #expect(r.out.contains("Widget: da \(f.systemApp)"))
        #expect(r.out.contains("  registrati anche da: \(f.home)/Library/Caches/dev/\(Self.name)"), "\(r.out)")
        #expect(r.out.contains("Altra copia, non usata: \(f.home)/Downloads/vecchio/\(Self.name), 0.3.0 (build 4)"))
        #expect(r.out.contains("Lens: 0.12.1, servizio local.opencode-lens da \(f.home)/Applications/opencode-lens, http://127.0.0.1:4777 risponde"))
        #expect(!r.out.contains("Altra copia, non usata: \(f.newApp)"), "la copia da installare non è un'altra copia")
        #expect(f.snapshot() == before)
        #expect(!f.calls.contains { c in Self.sideEffects.contains { c.hasPrefix($0) } }, "\(f.calls)")
    }

    /// Lo zip «Source code» di un tag ha install.sh ma non l'app compilata.
    @Test func senzaAppCompilata() throws {
        let f = try Fixture(app: false)
        let check = try f.run(["--check"])
        #expect(check.status == 0, "\(check.out)\(check.err)")
        let r = try f.run()
        #expect(r.status == 1)
        #expect(r.err.contains("Source code"))
        #expect(!f.exists(f.dest))
    }

    @Test func argomentiSbagliati() throws {
        let f = try Fixture()
        let r = try f.run(["--check", "altro"])
        #expect(r.status == 1)
        #expect(r.err.contains("uso: bash install.sh [--check]"))
    }

    @Test func checkDaiSorgenti() throws {
        let f = try Fixture(app: false, sources: true)
        let before = f.snapshot()
        let r = try f.run(["--check"], env: ["FAKE_SIGN": "ad-hoc"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.out.contains("Versione da installare: 9.9.9, dai sorgenti in \(f.src) (install.sh la compila)"), "\(r.out)")
        #expect(r.out.contains("  Command Line Tools: SDK macOS 27.0"))
        #expect(r.out.contains("  firma: ad-hoc"))
        #expect(r.out.contains("Per installare: bash"))
        #expect(f.calls.contains("build-clt --check"))
        #expect(!f.calls.contains { $0.hasPrefix("build-clt /") }, "--check non compila")
        #expect(f.snapshot() == before)
    }

    // MARK: - installation

    @Test func primaInstallazione() throws {
        let f = try Fixture()
        // un download porta il flag di quarantena su ogni file
        let xattr = Process()
        xattr.executableURL = URL(filePath: "/usr/bin/xattr")
        xattr.arguments = ["-w", "com.apple.quarantine", "0081;00000000;Safari;", f.newApp + "/Contents/MacOS/OpenCode Lens Monitor"]
        try xattr.run()
        xattr.waitUntilExit()
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.version(f.dest) == "9.9.9")
        #expect(getxattr(f.dest + "/Contents/MacOS/OpenCode Lens Monitor", "com.apple.quarantine", nil, 0, 0, 0) == -1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.home + "/Applications") == [Self.name], "nessuna cartella temporanea rimasta")
        #expect(f.calls.contains("lsregister -f \(f.dest)"))
        #expect(f.calls.contains("lsregister -u \(f.newApp)"), "\(f.calls)")
        #expect(f.calls.contains("open \(f.dest)"))
        #expect(!f.calls.contains { $0.hasPrefix("osascript") }, "niente da chiudere")
        #expect(r.out.contains("OpenCode Monitor è partito da \(f.dest)."))
        #expect(r.out.contains("Widget: OK, da \(f.dest)."))
        #expect(r.out.contains("Avvio al login: non verificato"))
        #expect(r.out.contains("Lens: non installata"))
        #expect(f.trashed().isEmpty)
        #expect(f.exists(f.newApp), "la cartella estratta resta com'è")
    }

    @Test func aggiornaDaApplicationsConImpostazioniELoginItem() throws {
        let f = try Fixture()
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.installLens()
        try f.setState("running", f.systemApp + "\n")
        try f.setState("login", "enabled")
        try f.setState("defaults.loginItemStatus", "enabled")
        try f.setState("defaults.loginItemPath", f.systemApp)
        let group = f.home + "/Library/Group Containers/HS87DR6TBX.local.opencode-lens-monitor/Library/Preferences/HS87DR6TBX.local.opencode-lens-monitor.plist"
        let prefs = f.home + "/Library/Preferences/local.opencode-lens-monitor.plist"
        try f.write("target=service", to: group)
        try f.write("finestra", to: prefs)
        let lens = try Data(contentsOf: URL(filePath: f.lensPlist))

        let r = try f.run(env: ["FAKE_CURL": "0"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.calls.contains("osascript -e quit app id \"local.opencode-lens-monitor\""))
        #expect(f.version(f.dest) == "9.9.9")
        #expect(!f.exists(f.systemApp))
        let trashed = f.trashed()
        #expect(trashed.count == 1)
        #expect(trashed.first?.hasPrefix("OpenCode Lens Monitor 0.4.0 ") == true)
        #expect(f.version(f.trash + "/" + (trashed.first ?? "")) == "0.4.0")
        #expect(f.calls.contains("lsregister -u \(f.trash)/\(trashed.first ?? "")"))
        #expect(r.out.contains("Copia in /Applications (0.4.0) spostata nel Cestino: \(f.systemApp)"))
        #expect(r.out.contains("Avvio al login: OK, da \(f.dest)."))
        #expect(r.out.contains("Widget: OK"))
        #expect(r.out.contains("Lens: 0.12.1"))
        // impostazioni e servizio della lens intatti
        #expect(try String(contentsOfFile: group, encoding: .utf8) == "target=service")
        #expect(try String(contentsOfFile: prefs, encoding: .utf8) == "finestra")
        #expect(try Data(contentsOf: URL(filePath: f.lensPlist)) == lens)
    }

    /// Il bundle vecchio è sostituito per intero: un file che aveva solo la versione vecchia non deve restare.
    @Test func sostituisceIlBundleSenzaFonderlo() throws {
        let f = try Fixture()
        try f.makeApp(at: f.dest, version: "0.5.0", build: "500")
        try f.write("vecchio", to: f.dest + "/Contents/Resources/solo-nella-vecchia.txt")
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.version(f.dest) == "9.9.9")
        #expect(!f.exists(f.dest + "/Contents/Resources/solo-nella-vecchia.txt"))
        let trashed = f.trashed()
        #expect(trashed.count == 1)
        #expect(f.exists(f.trash + "/" + (trashed.first ?? "") + "/Contents/Resources/solo-nella-vecchia.txt"))
        #expect(r.out.contains("Versione precedente (0.5.0) spostata nel Cestino."))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.home + "/Applications") == [Self.name])
    }

    @Test func applicationsSenzaPermessi() throws {
        let f = try Fixture()
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: f.system)
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.version(f.dest) == "9.9.9")
        #expect(f.version(f.systemApp) == "0.4.0")
        #expect(r.out.contains("serve un amministratore"))
        #expect(r.out.contains("Sposta nel Cestino"))
        #expect(f.trashed().isEmpty)
    }

    /// La versione nuova non parte: quella di prima torna dov'era e viene riaperta.
    @Test func installaDaiSorgentiConIlCertificato() throws {
        let f = try Fixture(app: false, sources: true)
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.version(f.dest) == "9.9.9")
        #expect(r.out.contains("la compilo dai sorgenti"))
        #expect(r.out.contains("certificato Apple Development del team HS87DR6TBX"))
        #expect(r.out.contains("Versione da installare: 9.9.9 (build 90909), compilata dai sorgenti in \(f.src)"), "\(r.out)")
        #expect(f.calls.contains { $0.hasPrefix("build-clt \(f.dir)/opencode-lens-monitor-app.") }, "\(f.calls)")
        #expect(f.calls.contains { $0.hasPrefix("codesign --verify") && $0.contains("-R=anchor apple generic") }, "con il certificato il team si controlla")
        #expect(!f.exists(f.systemApp))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: f.dir).filter { $0.hasPrefix("opencode-lens-monitor-app.") }
        #expect(leftovers.isEmpty, "la cartella della compilazione va tolta")
    }

    /// Senza il certificato del team l'app compilata qui è firmata ad-hoc: si installa comunque,
    /// con una nota su cosa i widget non possono fare.
    @Test func installaDaiSorgentiAdHoc() throws {
        let f = try Fixture(app: false, sources: true)
        let r = try f.run(env: ["FAKE_SIGN": "ad-hoc", "FAKE_TEAM": "not set"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.version(f.dest) == "9.9.9")
        #expect(r.out.contains("firma: ad-hoc"))
        #expect(!r.out.contains("\nfirma: ad-hoc"), "la riga di build-clt.sh non si ripete")
        #expect(r.out.contains("porta e LENS_TOKEN dal suo plist"))
        #expect(!f.calls.contains { $0.contains("-R=") }, "una firma ad-hoc non ha un team da controllare")
    }

    @Test func compilazioneFallitaNonCambiaNiente() throws {
        let f = try Fixture(app: false, sources: true)
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.setState("running", f.systemApp + "\n")
        let before = f.snapshot()
        let r = try f.run(env: ["FAKE_BUILD_FAILS": "1"])
        #expect(r.status == 1)
        #expect(r.err.contains("Compilazione non riuscita"))
        #expect(f.snapshot() == before)
        #expect(!f.calls.contains { $0.hasPrefix("osascript") }, "l'app aperta resta aperta")
    }

    @Test func nonParteRimetteLaVersioneDiPrima() throws {
        let f = try Fixture()
        try f.makeApp(at: f.dest, version: "0.5.0", build: "500")
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.setState("running", f.dest + "\n")
        let r = try f.run(env: ["FAKE_OPEN_FAILS": "1"])
        #expect(r.status == 1)
        #expect(r.err.contains("non è partito: ho rimesso le cose come prima"))
        #expect(f.version(f.dest) == "0.5.0")
        #expect(f.version(f.systemApp) == "0.4.0")
        #expect(f.trashed().isEmpty)
        #expect(f.calls.filter { $0 == "open \(f.dest)" }.count == 2, "\(f.calls)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.home + "/Applications") == [Self.name])
    }

    @Test func nonParteSenzaVersioneDiPrima() throws {
        let f = try Fixture()
        let r = try f.run(env: ["FAKE_OPEN_FAILS": "1"])
        #expect(r.status == 1)
        #expect(!f.exists(f.dest))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.home + "/Applications").isEmpty)
    }

    @Test func nonSiChiudeNonCambiaNiente() throws {
        let f = try Fixture()
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.setState("running", f.systemApp + "\n")
        let before = f.snapshot()
        let r = try f.run(env: ["FAKE_QUIT_FAILS": "1"])
        #expect(r.status == 1)
        #expect(r.err.contains("ancora aperto"))
        #expect(f.snapshot() == before)
        #expect(!f.calls.contains { $0.hasPrefix("open ") })
    }

    @Test func firmaNonValida() throws {
        let f = try Fixture()
        let r = try f.run(env: ["FAKE_CODESIGN_VERIFY": "1"])
        #expect(r.status == 1)
        #expect(r.err.contains("firma"))
        #expect(!f.exists(f.dest))
    }

    @Test func altroTeam() throws {
        let f = try Fixture()
        let r = try f.run(env: ["FAKE_TEAM": "ALTRO12345"])
        #expect(r.status == 1)
        #expect(r.err.contains("team HS87DR6TBX"))
        #expect(!f.exists(f.dest))
    }

    @Test func macOSTroppoVecchio() throws {
        let f = try Fixture()
        let r = try f.run(env: ["FAKE_MACOS": "15.6"])
        #expect(r.status == 1)
        #expect(r.err.contains("macOS 26"))
        #expect(!f.exists(f.dest))
    }

    @Test func widgetAncoraDallaCopiaVecchia() throws {
        let f = try Fixture()
        try f.setState("widget", f.systemApp + "/Contents/PlugIns/OpenCodeLensWidget.appex")
        let r = try f.run(env: ["FAKE_WIDGET_STAYS": "1"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.out.contains("Widget: macOS li prende ancora da \(f.systemApp)"))
        #expect(r.out.contains("toglili e rimettili"))
    }

    /// chronod tiene, finché non esce, il job del widget che launchd ha creato la prima volta che
    /// l'ha lanciato, con quel percorso: con la copia di /Applications nel Cestino launchd rifiuta
    /// il percorso nuovo ("will use existing") e non può eseguire il vecchio (errno 2): i widget si bloccano.
    @Test func widgetDallaCopiaTolta_riavviaChronod() throws {
        let f = try Fixture()
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.setState("widget", f.systemApp + Self.appex)
        try f.setState("chronod", "4711")
        try f.setState("widget-job", f.systemApp + Self.appex)
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(!f.exists(f.systemApp))
        #expect(f.calls.contains("launchctl print pid/4711/local.opencode-lens-monitor.widget"), "\(f.calls)")
        #expect(f.calls.contains(Self.pkillChronod), "\(f.calls)")
        #expect(r.out.contains("Widget: OK, da \(f.dest)."))
        #expect(r.out.contains("macOS faceva girare i widget ancora da \(f.systemApp): ho riavviato chronod"), "\(r.out)")
        // prima la copia nel Cestino: un chronod riavviato prima la rilancerebbe
        let trashed = f.calls.firstIndex { $0.hasPrefix("lsregister -u \(f.trash)/") } ?? Int.max
        #expect(trashed < (f.calls.firstIndex(of: Self.pkillChronod) ?? -1), "\(f.calls)")
    }

    @Test func widgetGiaDaApplicationsUtente_chronodResta() throws {
        let f = try Fixture()
        try f.makeApp(at: f.dest, version: "0.5.0", build: "500")
        try f.setState("widget", f.dest + Self.appex)
        try f.setState("chronod", "4711")
        try f.setState("widget-job", f.dest + Self.appex)
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.calls.contains("launchctl print pid/4711/local.opencode-lens-monitor.widget"), "\(f.calls)")
        #expect(!f.calls.contains { $0.hasPrefix("pkill") }, "stesso percorso: il job di chronod va bene")
        #expect(!r.out.contains("chronod"), "\(r.out)")
    }

    @Test func chronodSenzaWidget_restaComE() throws {
        let f = try Fixture()
        try f.setState("chronod", "4711")
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(!f.calls.contains { $0.hasPrefix("pkill") }, "\(f.calls)")
    }

    @Test func chronodNonSiRiavvia() throws {
        let f = try Fixture()
        try f.makeApp(at: f.systemApp, version: "0.4.0", build: "5")
        try f.setState("chronod", "4711")
        try f.setState("widget-job", f.systemApp + Self.appex)
        let r = try f.run(env: ["FAKE_PKILL_FAILS": "1"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(f.calls.contains(Self.pkillChronod), "\(f.calls)")
        #expect(r.out.contains("non sono riuscito a riavviare chronod"), "\(r.out)")
        #expect(r.out.contains("killall chronod"))
        #expect(r.out.contains("esci e rientri nella sessione"))
    }

    @Test func checkVedeIlJobVecchioDiChronod() throws {
        let f = try Fixture()
        try f.makeApp(at: f.dest, version: "0.5.0", build: "500")
        try f.setState("widget", f.dest + Self.appex)
        try f.setState("chronod", "4711")
        try f.setState("widget-job", f.systemApp + Self.appex)
        let before = f.snapshot()
        let r = try f.run(["--check"])
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.out.contains("Widget: da \(f.dest)"))
        #expect(r.out.contains("  ma macOS li fa girare ancora da \(f.systemApp)"), "\(r.out)")
        #expect(r.out.contains("killall chronod"))
        #expect(f.snapshot() == before)
        #expect(!f.calls.contains { c in Self.sideEffects.contains { c.hasPrefix($0) } }, "\(f.calls)")
    }

    @Test func loginItemDaApprovare() throws {
        let f = try Fixture()
        try f.setState("login", "requiresApproval")
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.out.contains("Avvio al login: da approvare"))
        #expect(r.out.contains("Elementi login"))
    }

    @Test func loginItemNonAttivo() throws {
        let f = try Fixture()
        try f.setState("login", "disabled")
        let r = try f.run()
        #expect(r.status == 0, "\(r.out)\(r.err)")
        #expect(r.out.contains("Avvio al login: non attivo"))
    }
}

@Suite struct PackageScriptTests {
    static let script = InstallScriptTests.root.appending(path: "scripts/package.sh").path

    @Test func sintassiERegole() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-n", Self.script]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = try String(contentsOfFile: Self.script, encoding: .utf8)
        #expect(text.contains(#"git archive --format=tar HEAD | tar -x -C "$WORK/src""#), "si builda da HEAD")
        #expect(text.contains("git status --porcelain --untracked-files=all"), "si ferma con modifiche non committate")
        #expect(text.contains("ditto -c -k"), "zip con ditto: symlink e firma del bundle restano validi")
        #expect(text.contains(#"CURRENT_PROJECT_VERSION="$BUILD""#))
        #expect(text.contains("scripts/clt/Metadata.appintents/extract.actionsdata"), "metadati AppIntents allineati alla build Xcode")
        #expect(text.contains(#"DEVELOPER_DIR="$CLT" bash "$WORK/src/scripts/build-clt.sh""#), "il Source code si compila senza Xcode")
        let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
        #expect(!code.contains("zip -"))
        #expect(!code.contains("sudo"))
    }

    /// Il controllo statico di InstallScriptTests trova il bug di bash 3.2 per cui esiste.
    @Test func ilControlloTrovaLaVariabileAttaccata() {
        #expect(#"echo "$APP…""#.contains(/\$[A-Za-z_][A-Za-z0-9_]*[^\t -~]/))
        #expect(!#"echo "${APP}…""#.contains(/\$[A-Za-z_][A-Za-z0-9_]*[^\t -~]/))
    }

    @Test func fuoriDaUnRepositorySiFermaPrimaDeiTest() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "lens-monitor-package-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base + "/scripts", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        let dir = String(cString: realpath(base, nil))
        try FileManager.default.copyItem(atPath: Self.script, toPath: dir + "/scripts/package.sh")
        // un test.sh che lascerebbe una traccia se lo script arrivasse fin lì
        try Data("#!/bin/bash\ntouch \"$(dirname \"$0\")/../test-lanciati\"\n".utf8).write(to: URL(filePath: dir + "/scripts/test.sh"))
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [dir + "/scripts/package.sh"]
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CEILING_DIRECTORIES": (dir as NSString).deletingLastPathComponent, "LC_ALL": "en_US.UTF-8"]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 1)
        #expect(!FileManager.default.fileExists(atPath: dir + "/test-lanciati"))
    }
}
