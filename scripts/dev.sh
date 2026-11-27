#!/bin/bash
# Ciclo di sviluppo dell'app: a ogni modifica dei sorgenti rifà la build Debug e rilancia l'app.
# - Polling ogni secondo invece di fswatch/watchexec, per non chiedere dipendenze in più.
# - La build va fuori dal repo, come in scripts/test.sh (iCloud e firma del codice), e in una
#   DerivedData sua: due xcodebuild sulla stessa cartella falliscono con "database is locked".
# - Dopo una modifica aspetta che i file restino fermi per un secondo: un salvataggio di più file
#   (o un editor che scrive a pezzi) non deve far compilare uno stato a metà.
# - XcodeGen elenca i file uno per uno nel progetto: se l'elenco dei sorgenti cambia (file
#   aggiunti o tolti) il progetto va rigenerato, altrimenti un file nuovo non si compila e uno
#   tolto rompe la build. Un file tolto non ha data di modifica: lo si vede dall'elenco.
# - L'app installata (in ~/Applications da install.sh, o in /Applications per le versioni fino
#   alla 0.4.0) va chiusa: ha lo stesso bundle id e la stessa App Group,
#   e aperte insieme comparirebbero due icone nella barra. All'uscita (Ctrl-C, chiusura del
#   terminale) si chiude l'app Debug e si riapre quella installata se era aperta. Con --once
#   l'app Debug resta aperta dopo lo script, quindi quella installata resta chiusa: riaprila tu.
# - L'app Debug parte dall'eseguibile, non con `open`: i suoi log restano in questo terminale e
#   l'ambiente passa così com'è (es. LENS_MONITOR_PORT=4778 scripts/dev.sh).
# Uso: scripts/dev.sh [--once]   (--once: una build e un avvio, senza restare in ascolto)
set -uo pipefail
# senza set -e (una build fallita non deve chiudere il ciclo): il cd va controllato a mano
cd "$(dirname "$0")/.." || exit 1

derived="${LENS_MONITOR_DERIVED:-$HOME/Library/Caches/opencode-lens-monitor/DerivedData-dev}"
app="$derived/Build/Products/Debug/OpenCode Lens Monitor.app"
installed="$HOME/Applications/OpenCode Lens Monitor.app"
[[ -d "$installed" ]] || installed="/Applications/OpenCode Lens Monitor.app"
stamp="$(mktemp -t opencode-lens-monitor-dev)"
watched=(OpenCodeLensMonitor OpenCodeLensWidget Shared LensMonitorCore/Sources project.yml)
pid=""
reopen=false
sources=""

# Un'app Debug lasciata aperta da --once: due istanze scriverebbero la stessa App Group.
# Il pattern di -f è una regex sull'intera riga di comando, non ancorata e con i punti del
# percorso come jolly: senza ^ un `tail -f` o un debugger con quel percorso tra gli argomenti
# riceverebbe il SIGTERM. L'app parte sempre con argv[0] = percorso completo (qui e con open).
if pgrep -qf "^${app}/Contents/MacOS/"; then
  echo "→ chiudo l'app Debug rimasta aperta"
  pkill -f "^${app}/Contents/MacOS/" || true
fi
# Per percorso e non per bundle id, che è lo stesso dell'app Debug.
if pgrep -qf "^${installed}/Contents/MacOS/"; then
  reopen=true
  echo "→ chiudo l'app installata"
  pkill -f "^${installed}/Contents/MacOS/" || true
fi

# Impronta dell'elenco dei sorgenti seguiti.
sources_list() {
  find "${watched[@]}" -type f \
    \( -name '*.swift' -o -name '*.plist' -o -name '*.entitlements' -o -name 'project.yml' \) 2>/dev/null | sort | shasum | cut -d' ' -f1
}

stop_app() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  fi
  pid=""
}

cleaned=false
cleanup() {
  $cleaned && return
  cleaned=true
  stop_app
  rm -f "$stamp"
  if $reopen; then
    echo "→ riapro l'app installata"
    open "$installed"
  fi
  exit 0
}
trap cleanup INT TERM HUP EXIT

build_and_run() {
  touch "$stamp"
  local current
  current="$(sources_list)"
  if [[ ! -d OpenCodeLensMonitor.xcodeproj || project.yml -nt OpenCodeLensMonitor.xcodeproj || "$current" != "$sources" ]]; then
    echo "→ xcodegen generate"
    xcodegen generate --quiet || return
    sources="$current"
  fi
  echo "→ build Debug ($(date +%H:%M:%S))"
  local log
  log="$(mktemp -t opencode-lens-monitor-build)"
  if ! xcodebuild -project OpenCodeLensMonitor.xcodeproj -scheme OpenCodeLensMonitor -configuration Debug \
      -derivedDataPath "$derived" build >"$log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$log" | sort -u | head -20
    echo "✘ build fallita: l'app di prima resta aperta (log completo: $log)"
    return
  fi
  rm -f "$log"
  stop_app
  "$app/Contents/MacOS/OpenCode Lens Monitor" &
  pid=$!
  echo "✔ avviata (pid $pid)"
}

# Il primo file sorgente modificato dopo `$1`, o niente.
changed_since() {
  find "${watched[@]}" -newer "$1" -type f \
    \( -name '*.swift' -o -name '*.plist' -o -name '*.entitlements' -o -name 'project.yml' \) -print -quit 2>/dev/null
}

# Torna quando per un secondo intero nessun sorgente è cambiato.
wait_until_quiet() {
  local mark
  while true; do
    mark="$(mktemp -t opencode-lens-monitor-quiet)"
    sleep 1
    if [[ -z "$(changed_since "$mark")" ]]; then
      rm -f "$mark"
      return
    fi
    rm -f "$mark"
  done
}

build_and_run
if [[ "${1:-}" == "--once" ]]; then
  # build fallita: nessuna app Debug, si riapre subito quella installata
  [[ -z "$pid" ]] && cleanup
  # l'app Debug deve sopravvivere allo script: niente cleanup all'uscita
  trap - INT TERM HUP EXIT
  rm -f "$stamp"
  if $reopen; then
    echo "L'app installata resta chiusa finché è aperta quella Debug: riaprila quando hai finito."
  fi
  exit 0
fi

echo "In ascolto sulle modifiche (Ctrl-C per uscire)…"
while true; do
  sleep 1
  changed="$(changed_since "$stamp")"
  if [[ -n "$changed" ]]; then
    echo "→ modificato $changed"
  elif [[ "$(sources_list)" != "$sources" ]]; then
    echo "→ file aggiunti o tolti"
  else
    continue
  fi
  wait_until_quiet
  build_and_run
done
