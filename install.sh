#!/bin/bash
# Installa (o aggiorna) OpenCode Lens Monitor in ~/Applications. Tutto resta nella
# cartella utente, senza sudo né Xcode: va bene anche su un Mac aziendale.
#
# Dalla cartella estratta dallo zip della release:
#   bash ~/Downloads/opencode-lens-monitor/install.sh
#   1. controlla la firma dell'app nello zip (team HS87DR6TBX)
#   2. chiude il Monitor se è aperto
#   3. copia l'app in ~/Applications, sostituendo per intero quella che c'era (mai fusa
#      col bundle vecchio), e toglie la quarantena del download
#   4. la apre e aspetta che parta; se non parte rimette la versione di prima
#   5. solo allora sposta nel Cestino la copia precedente di ~/Applications e quella in
#      /Applications (con mv: si possono rimettere a posto)
#   6. controlla da dove macOS prende widget e avvio al login; se chronod (il processo di
#      macOS che fa girare i widget) li lancia ancora dalla copia tolta, lo riavvia
# Impostazioni (App Group e UserDefaults del Monitor) e servizio della lens non vengono
# toccati. Per aggiornare si rilancia lo stesso comando dallo zip nuovo.
#
# Dal «Source code» (dove lo zip con l'app non si può scaricare, per esempio per un DLP)
# l'app non c'è: install.sh la compila prima con scripts/build-clt.sh, con i soli Command
# Line Tools, e la firma con il certificato "Apple Development" del team se è nel
# portachiavi, altrimenti ad-hoc. Poi procede allo stesso modo.
#
# Uso: bash install.sh            (installa o aggiorna)
#      bash install.sh --check    (mostra cosa c'è installato, non cambia niente)
set -euo pipefail

NAME="OpenCode Lens Monitor.app"
EXE="OpenCode Lens Monitor"
BUNDLE_ID="local.opencode-lens-monitor"
WIDGET_ID="local.opencode-lens-monitor.widget"
APPEX="Contents/PlugIns/OpenCodeLensWidget.appex"
TEAM="HS87DR6TBX"
SRC="$(cd "$(dirname "$0")" && pwd -P)"
NEW="$SRC/$NAME"
APPS="$HOME/Applications"
DEST="$APPS/$NAME"
# /Applications di sistema; la variabile esiste solo per i test, che non devono mai
# toccare l'app installata su questo Mac
SYSTEM_APP="${LENS_MONITOR_SYSTEM_APPS:-/Applications}/$NAME"
TRASH="$HOME/.Trash"
LENS_PLIST="$HOME/Library/LaunchAgents/local.opencode-lens.plist"
LENS_RELEASES="https://github.com/vale76p/opencode-lens-public/releases"
STAMP="$(date +%Y%m%d-%H%M%S)"
# lsregister (LaunchServices) non è nel PATH
PATH="$PATH:/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support"

die() {
  echo "$*" >&2
  exit 1
}

CHECK=0
case "$#:${1:-}" in
  0:) ;;
  1:--check) CHECK=1 ;;
  *) die "uso: bash install.sh [--check]" ;;
esac

[[ "$(id -u)" -ne 0 ]] || die "Non serve essere amministratore: rilancia come utente normale, con bash install.sh"

info_get() {
  plutil -extract "$2" raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

version_of() {
  local v b
  v="$(info_get "$1" CFBundleShortVersionString)"
  b="$(info_get "$1" CFBundleVersion)"
  echo "${v:-?} (build ${b:-?})"
}

real_path() {
  echo "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")"
}

# Copie del Monitor in esecuzione adesso, un percorso di bundle per riga (anche una build Debug
# o una copia lasciata in Download: hanno lo stesso bundle id e la stessa App Group).
running() {
  { pgrep -lf "/Contents/MacOS/$EXE" 2>/dev/null || true; } | sed -n "s|^[0-9]* \(/.*\.app\)/Contents/MacOS/$EXE\$|\1|p"
}

is_running() {
  local p
  while IFS= read -r p; do
    [[ "$p" == "$1" || "$p" == "$(real_path "$1")" ]] && return 0
  done < <(running)
  return 1
}

# L'app di cui macOS usa adesso l'estensione del widget (pluginkit elegge una copia per bundle id).
widget_app() {
  { pluginkit -m -v -i "$WIDGET_ID" 2>/dev/null || true; } | awk -F '\t' 'NF >= 4 { print $NF; exit }' | sed "s|/$APPEX\$||"
}

# Ogni copia registrata del widget, compresa quella eletta.
widget_apps() {
  { pluginkit -m -A -D -v -i "$WIDGET_ID" 2>/dev/null || true; } | awk -F '\t' 'NF >= 4 { print $NF }' | sed "s|/$APPEX\$||"
}

# chronod (fa girare i widget) chiede a launchd un job la prima volta che lancia il widget, con
# il percorso di quella copia, e lo tiene finché non esce: launchd rifiuta un altro percorso per
# lo stesso job ("will use existing"). Dopo lo spostamento in ~/Applications il job punta ancora
# alla copia nel Cestino: i widget funzionano finché vive quel vecchio processo, poi si bloccano (errno 2).
chronod_pid() {
  { pgrep -U "$(id -u)" -x chronod 2>/dev/null || true; } | head -n 1
}

# L'app da cui chronod lancia il widget; vuoto se non l'ha ancora fatto da quando è partito.
widget_job() {
  local pid
  pid="$(chronod_pid)"
  [[ -n "$pid" ]] || return 0
  { launchctl print "pid/$pid/$WIDGET_ID" 2>/dev/null || true; } | sed -n 's|^[[:space:]]*path = \(.*\)$|\1|p' | head -n 1 | sed "s|/$APPEX\$||"
}

# Scritti dal Monitor stesso dalla 0.5.0 (RecordedLoginItem), perché `sfltool dumpbtm` a volte
# si blocca: stato del login item e percorso da cui è stato registrato.
login_get() {
  defaults read "$BUNDLE_ID" "$1" 2>/dev/null || true
}

lens_get() {
  if [[ -f "$LENS_PLIST" ]]; then plutil -extract "$1" raw -o - "$LENS_PLIST" 2>/dev/null || true; fi
}

# --- cosa è installato adesso ------------------------------------------------

MACOS="$(sw_vers -productVersion 2>/dev/null || echo 0)"
MACOS_OK=1
[[ "${MACOS%%.*}" -ge 26 ]] || MACOS_OK=0

NEW_OK=0
[[ -d "$NEW" && "$(info_get "$NEW" CFBundleIdentifier)" == "$BUNDLE_ID" ]] && NEW_OK=1
# lo zip «Source code»: niente app compilata, ma i sorgenti per compilarla
FROM_SOURCE=0
[[ "$NEW_OK" -eq 0 && -f "$SRC/scripts/build-clt.sh" && -f "$SRC/project.yml" ]] && FROM_SOURCE=1
SIGNED_BY=team

sign_note() {
  case "$1" in
    team) echo "  firma: certificato Apple Development del team $TEAM nel portachiavi; widget e impostazioni condivise funzionano" ;;
    *)
      echo "  firma: ad-hoc, non c'è un certificato Apple Development del team $TEAM nel portachiavi."
      echo "  Monitor e widget funzionano, ma i widget non leggono le impostazioni dell'app: seguono"
      echo "  sempre la lens del LaunchAgent (porta e LENS_TOKEN dal suo plist), mai una lens di"
      echo "  sviluppo scelta in Server (docs/aggiornamento.md, «Installare dal Source code»)."
      ;;
  esac
}

OTHERS=()
while IFS= read -r a; do
  [[ "$(info_get "$a" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || continue
  [[ "$NEW_OK" -eq 1 && "$(real_path "$a")" == "$(real_path "$NEW")" ]] && continue
  OTHERS+=("$a")
done < <(find "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" -maxdepth 4 -type d -name "$NAME" -prune 2>/dev/null || true)

LENS_DIR="$(lens_get WorkingDirectory)"
LENS_VERSION=""
if [[ -n "$LENS_DIR" && -f "$LENS_DIR/package.json" ]]; then
  LENS_VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$LENS_DIR/package.json" | head -n 1)"
fi
LENS_HOST="$(lens_get EnvironmentVariables.LENS_HOST)"
case "${LENS_HOST:-}" in "" | 0.0.0.0 | :: | "[::]") LENS_HOST=127.0.0.1 ;; esac
[[ "$LENS_HOST" != *:* || "$LENS_HOST" == \[* ]] || LENS_HOST="[$LENS_HOST]"
LENS_PORT="$(lens_get EnvironmentVariables.LENS_PORT)"
LENS_URL="http://$LENS_HOST:${LENS_PORT:-4777}"

lens_report() {
  if [[ ! -f "$LENS_PLIST" ]]; then
    echo "Lens: non installata (manca $LENS_PLIST)."
    echo "  Il Monitor si installa lo stesso, ma senza lens non ha dati. Per installarla: scarica"
    echo "  opencode-lens-<versione>.zip da $LENS_RELEASES e lancia"
    echo "  bash ~/Downloads/opencode-lens/install.sh"
    return
  fi
  local answer="non risponde"
  if curl -fsS -m 2 "$LENS_URL/healthz" >/dev/null 2>&1; then answer="risponde"; fi
  echo "Lens: ${LENS_VERSION:-versione non nota}, servizio local.opencode-lens da ${LENS_DIR:-?}, $LENS_URL $answer"
}

login_report() {
  local status path
  status="$(login_get loginItemStatus)"
  path="$(login_get loginItemPath)"
  case "$status" in
    enabled) echo "Avvio al login: attivo, da $path" ;;
    requiresApproval) echo "Avvio al login: da approvare in Impostazioni di Sistema > Generale > Elementi login (registrato da $path)" ;;
    disabled) echo "Avvio al login: non attivo" ;;
    *) echo "Avvio al login: non noto (guarda Impostazioni > Generale del Monitor)" ;;
  esac
}

report() {
  if [[ "$NEW_OK" -eq 1 ]]; then echo "Versione da installare: $(version_of "$NEW"), da $SRC"; fi
  if [[ "$FROM_SOURCE" -eq 1 && -n "${BUILT:-}" ]]; then
    echo "Versione da installare: $(version_of "$NEW"), compilata dai sorgenti in $SRC"
  elif [[ "$FROM_SOURCE" -eq 1 ]]; then
    echo "Versione da installare: $(sed -n 's/^ *MARKETING_VERSION: *"\([^"]*\)".*/\1/p' "$SRC/project.yml" | head -n 1), dai sorgenti in $SRC (install.sh la compila)"
    local line
    while IFS= read -r line; do
      case "$line" in
        "firma: "*) sign_note "${line#firma: }" ;;
        *) echo "  $line" ;;
      esac
    done < <(bash "$SRC/scripts/build-clt.sh" --check 2>&1 || true)
  fi
  [[ "$MACOS_OK" -eq 1 ]] || echo "macOS: $MACOS, serve macOS 26 o successivo"
  for a in "$DEST" "$SYSTEM_APP"; do
    if [[ -d "$a" ]]; then echo "Installata: $a, $(version_of "$a")"; else echo "Non c'è: $a"; fi
  done
  local r found=0
  while IFS= read -r r; do
    echo "In esecuzione: $r"
    found=1
  done < <(running)
  [[ "$found" -eq 1 ]] || echo "In esecuzione: no"
  login_report
  local w
  w="$(widget_app)"
  if [[ -n "$w" ]]; then echo "Widget: da $w"; else echo "Widget: nessuno registrato"; fi
  while IFS= read -r r; do
    [[ "$r" == "$w" ]] || echo "  registrati anche da: $r"
  done < <(widget_apps)
  local j
  j="$(widget_job)"
  if [[ -n "$j" && "$j" != "$w" ]]; then
    echo "  ma macOS li fa girare ancora da $j: si aggiornano solo riavviando chronod"
    echo "  (killall chronod nel Terminale) o uscendo e rientrando nella sessione"
  fi
  for o in ${OTHERS[@]+"${OTHERS[@]}"}; do echo "Altra copia, non usata: $o, $(version_of "$o")"; done
  lens_report
}

if [[ "$CHECK" -eq 1 ]]; then
  report
  echo
  echo "Solo controllo: nessuna modifica."
  if [[ "$NEW_OK" -eq 1 || "$FROM_SOURCE" -eq 1 ]]; then echo "Per installare: bash \"$SRC/install.sh\""; fi
  exit 0
fi

[[ "$NEW_OK" -eq 1 || "$FROM_SOURCE" -eq 1 ]] || die "In $SRC non c'è $NAME né i sorgenti per compilarla: lancia install.sh dalla cartella estratta da opencode-lens-monitor-<versione>.zip o dal «Source code» della release."
[[ "$MACOS_OK" -eq 1 ]] || die "OpenCode Monitor richiede macOS 26 o successivo (questo Mac ha macOS $MACOS)."

if [[ "$FROM_SOURCE" -eq 1 ]]; then
  BUILT="$(mktemp -d "${TMPDIR:-/tmp}/opencode-lens-monitor-app.XXXXXX")"
  trap 'rm -rf "${BUILT:?}"' EXIT
  echo "Qui non c'è l'app compilata: la compilo dai sorgenti con i Command Line Tools (un minuto circa)…"
  # la riga "firma: …" è per questo script: sign_note più sotto la spiega a parole
  bash "$SRC/scripts/build-clt.sh" "$BUILT" | tee "$BUILT/build.log" | { grep -v '^firma: ' || true; } ||
    die "Compilazione non riuscita (messaggi qui sopra). Non ho cambiato niente."
  SIGNED_BY="$(sed -n 's/^firma: //p' "$BUILT/build.log" | tail -n 1)"
  NEW="$BUILT/$NAME"
  [[ -d "$NEW" && "$(info_get "$NEW" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || die "La compilazione non ha prodotto $NAME. Non ho cambiato niente."
  sign_note "$SIGNED_BY"
  echo
fi

codesign --verify --deep --strict "$NEW" >/dev/null 2>&1 || die "La firma di $NEW non è valida: lo zip è danneggiato o incompleto. Scaricalo di nuovo."
# un'app compilata qui senza il certificato è firmata ad-hoc apposta. Il requirement lega il team
# a un certificato emesso da Apple: TeamIdentifier da solo è solo una stringa nella firma.
if [[ "$SIGNED_BY" != ad-hoc ]]; then
  codesign --verify --deep --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"${TEAM}\"" "$NEW" >/dev/null 2>&1 ||
    die "$NEW non è firmata dal team $TEAM: non la installo."
fi

report
echo

# --- chiusura del Monitor ---------------------------------------------------------

WAS_RUNNING=()
while IFS= read -r r; do WAS_RUNNING+=("$r"); done < <(running)
if [[ ${#WAS_RUNNING[@]} -gt 0 ]]; then
  echo "Chiudo OpenCode Monitor…"
  for _ in {1..20}; do  # mezzo secondo l'uno: al massimo 10 s
    [[ -n "$(running)" ]] || break
    # una chiusura per chiamata: con due copie aperte (una build Debug) ne serve più di una
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    sleep 0.5
  done
  [[ -z "$(running)" ]] || die "OpenCode Monitor è ancora aperto: chiudilo (pannello > pulsante di spegnimento > Esci dal Monitor) e rilancia bash \"$SRC/install.sh\". Non ho cambiato niente."
fi

# --- copy -------------------------------------------------------------------------

echo "Installo OpenCode Monitor $(info_get "$NEW" CFBundleShortVersionString) in ${DEST}…"
mkdir -p "$APPS"
# il bundle nuovo si prepara accanto alla destinazione e poi si scambia con mv: mai copiato
# sopra quello vecchio (cp -R fonderebbe i due bundle)
STAGE="$(mktemp -d "$APPS/.opencode-lens-monitor.XXXXXX")"
ditto "$NEW" "$STAGE/$NAME" || {
  rm -rf "$STAGE"
  die "Copia di $NEW non riuscita. Non ho cambiato niente."
}
# l'app estratta da uno zip scaricato porta il flag di quarantena: senza toglierlo Gatekeeper
# blocca un'app non notarizzata. I file sono dell'utente, niente sudo.
xattr -dr com.apple.quarantine "$STAGE/$NAME" 2>/dev/null || true

PREV=""
if [[ -e "$DEST" ]]; then
  PREV="$STAGE/previous.app"
  PREV_VERSION="$(info_get "$DEST" CFBundleShortVersionString)"
  mv "$DEST" "$PREV" || {
    rm -rf "$STAGE"
    die "Non riesco a spostare $DEST. Non ho cambiato niente."
  }
fi
if ! mv "$STAGE/$NAME" "$DEST"; then
  if [[ -n "$PREV" ]]; then mv "$PREV" "$DEST"; fi
  rm -rf "$STAGE"
  die "Non riesco a copiare l'app in $DEST. Ho rimesso la versione di prima."
fi

# LaunchServices: subito la copia nuova, e dimenticare quella nella cartella estratta (stesso
# bundle id e stessa versione: macOS potrebbe prendere i widget da lì, poi perderli quando la
# cartella viene cancellata)
lsregister -f "$DEST" >/dev/null 2>&1 || true
if [[ "$(real_path "$NEW")" != "$(real_path "$DEST")" ]]; then lsregister -u "$NEW" >/dev/null 2>&1 || true; fi

# --- start ------------------------------------------------------------------------

open "$DEST" 2>/dev/null || true
STARTED=0
for _ in {1..20}; do  # mezzo secondo l'uno: al massimo 10 s
  if is_running "$DEST"; then
    STARTED=1
    break
  fi
  sleep 0.5
done

if [[ "$STARTED" -eq 0 ]]; then
  rm -rf "$DEST"
  if [[ -n "$PREV" ]]; then
    mv "$PREV" "$DEST"
    lsregister -f "$DEST" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE"
  for r in ${WAS_RUNNING[@]+"${WAS_RUNNING[@]}"}; do
    if [[ -d "$r" ]]; then open "$r" 2>/dev/null || true; fi
  done
  echo "OpenCode Monitor $(info_get "$NEW" CFBundleShortVersionString) non è partito: ho rimesso le cose come prima." >&2
  if [[ "$FROM_SOURCE" -eq 0 ]]; then echo "Per vedere il messaggio di macOS: open \"$NEW\"" >&2; fi
  echo "Se macOS dice che l'app è danneggiata o non verificata: Impostazioni di Sistema > Privacy e sicurezza > Apri comunque." >&2
  exit 1
fi
echo "OpenCode Monitor è partito da $DEST."

# --- copie precedenti nel Cestino ---------------------------------------------------

# mv, non rm: dal Cestino si possono rimettere in Applicazioni
to_trash() {
  local target="$TRASH/OpenCode Lens Monitor $2 $STAMP.app"
  mkdir -p "$TRASH" 2>/dev/null || true
  mv "$1" "$target" 2>/dev/null || return 1
  lsregister -u "$target" >/dev/null 2>&1 || true
}

if [[ -n "$PREV" ]]; then
  if to_trash "$PREV" "${PREV_VERSION:-prima}"; then
    echo "Versione precedente (${PREV_VERSION:-?}) spostata nel Cestino."
  else
    # una seconda copia con lo stesso bundle id confonderebbe widget e login item
    rm -rf "$PREV"
    echo "Cestino non accessibile: versione precedente (${PREV_VERSION:-?}) eliminata."
  fi
fi
rm -rf "$STAGE"

if [[ -d "$SYSTEM_APP" ]]; then
  SYSTEM_VERSION="$(info_get "$SYSTEM_APP" CFBundleShortVersionString)"
  if to_trash "$SYSTEM_APP" "${SYSTEM_VERSION:-prima}"; then
    echo "Copia in /Applications (${SYSTEM_VERSION:-?}) spostata nel Cestino: $SYSTEM_APP"
  else
    echo
    echo "Non posso spostare nel Cestino $SYSTEM_APP (${SYSTEM_VERSION:-?}): serve un amministratore"
    echo "(o il permesso «Gestione app» per il Terminale in Impostazioni di Sistema > Privacy e sicurezza)."
    echo "Finché resta, macOS potrebbe prendere i widget da quella copia. Toglila dal Finder:"
    echo "Applicazioni > clic destro su OpenCode Monitor > Sposta nel Cestino (chiede la password"
    echo "di un amministratore), oppure chiedi all'IT. Il Monitor in ~/Applications funziona comunque."
  fi
fi

# --- widget e login item --------------------------------------------------------------

echo
pluginkit -a "$DEST/$APPEX" >/dev/null 2>&1 || true
W=""
for _ in {1..20}; do  # mezzo secondo l'uno: al massimo 10 s
  W="$(widget_app)"
  [[ "$W" != "$DEST" && "$W" != "$(real_path "$DEST")" ]] || break
  sleep 0.5
done
if [[ "$W" == "$DEST" || "$W" == "$(real_path "$DEST")" ]]; then
  echo "Widget: OK, da $DEST. Quelli già sulla scrivania restano; se uno resta vuoto, toglilo e"
  echo "  rimettilo (clic destro sulla scrivania > Modifica widget > OpenCode Monitor)."
else
  echo "Widget: macOS li prende ancora da ${W:-nessuna copia}. Esci e rientra nella sessione; se i"
  echo "  widget restano vuoti, toglili e rimettili (clic destro sulla scrivania > Modifica widget)."
fi
# solo adesso, con le copie vecchie nel Cestino: riavviato prima, chronod potrebbe rilanciarle.
# chronod è un LaunchAgent dell'utente, launchd lo riavvia su richiesta (in meno di un secondo)
J="$(widget_job)"
if [[ -n "$J" && "$J" != "$DEST" && "$J" != "$(real_path "$DEST")" ]]; then
  OLD_CHRONOD="$(chronod_pid)"
  pkill -U "$(id -u)" -x chronod >/dev/null 2>&1 || true
  RESTARTED=0
  for _ in {1..20}; do  # mezzo secondo l'uno: al massimo 10 s
    if [[ "$(chronod_pid)" != "$OLD_CHRONOD" ]]; then
      RESTARTED=1
      break
    fi
    sleep 0.5
  done
  if [[ "$RESTARTED" -eq 1 ]]; then
    echo "  macOS faceva girare i widget ancora da $J: ho riavviato chronod, il processo di macOS"
    echo "  che li gestisce (riparte da solo). I widget si ricaricano in qualche secondo."
  else
    echo "  macOS fa girare i widget ancora da $J e non sono riuscito a riavviare chronod: i widget"
    echo "  restano fermi finché non esci e rientri nella sessione (o lanci killall chronod nel Terminale)."
  fi
fi

LOGIN=""
for _ in {1..20}; do  # mezzo secondo l'uno: al massimo 10 s
  LOGIN="$(login_get loginItemStatus)"
  if [[ -n "$LOGIN" && ("$LOGIN" == disabled || "$(login_get loginItemPath)" == "$DEST" || "$(login_get loginItemPath)" == "$(real_path "$DEST")") ]]; then break; fi
  sleep 0.5
done
case "$LOGIN" in
  enabled)
    if [[ "$(login_get loginItemPath)" == "$DEST" || "$(login_get loginItemPath)" == "$(real_path "$DEST")" ]]; then
      echo "Avvio al login: OK, da $DEST."
    else
      echo "Avvio al login: registrato ancora da $(login_get loginItemPath). Nel Monitor apri Impostazioni >"
      echo "  Generale, togli e rimetti la spunta su «Apri OpenCode Monitor»."
    fi
    ;;
  requiresApproval)
    echo "Avvio al login: da approvare. Impostazioni di Sistema > Generale > Elementi login: attiva"
    echo "  OpenCode Monitor (oppure, nel Monitor, Impostazioni > Generale > Approva in Impostazioni di Sistema)."
    ;;
  disabled) echo "Avvio al login: non attivo. Per attivarlo: Impostazioni > Generale > Apri OpenCode Monitor." ;;
  *) echo "Avvio al login: non verificato. Controllalo nel Monitor, Impostazioni > Generale." ;;
esac

echo
lens_report
for o in ${OTHERS[@]+"${OTHERS[@]}"}; do echo "Altra copia, non usata, puoi cancellarla: $o"; done
echo
echo "Fatto: OpenCode Monitor è nella barra dei menu. Lo zip e la cartella $SRC si possono cancellare."
