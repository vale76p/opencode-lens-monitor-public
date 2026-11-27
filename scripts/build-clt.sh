#!/bin/bash
# Compila OpenCode Lens Monitor con i soli Command Line Tools, senza Xcode né XcodeGen: serve
# dove lo zip della release con l'app non si può scaricare (per esempio un DLP aziendale) e si
# installa dal «Source code». Lo lancia install.sh; a mano:
#   scripts/build-clt.sh <cartella>        → <cartella>/OpenCode Lens Monitor.app
#   scripts/build-clt.sh --check           → Command Line Tools e firma che userebbe, senza compilare
#
# - swiftc compila tre moduli come fa Xcode: LensMonitorCore (libreria statica), l'app e il
#   widget, con gli stessi nomi di modulo (i metadati AppIntents citano OpenCodeLensWidget).
#   Il widget entra da _NSExtensionMain, come ogni estensione fatta da Xcode.
# - Niente macro di SwiftUI (@State, @Entry, #Preview…): il loro plugin c'è solo in Xcode, e
#   con i Command Line Tools la compilazione fallisce. Un test lo controlla.
# - Info.plist ed entitlements sono quelli dei target, con le variabili di project.yml
#   sostituite; versione e numero di build come in scripts/package.sh.
# - I metadati AppIntents del widget (Metadata.appintents, senza i quali «Modifica widget» non
#   offre la scelta del modello) li genera solo appintentsmetadataprocessor di Xcode: sono in
#   scripts/clt/, e scripts/package.sh controlla che coincidano con quelli della build Xcode.
# - Firma con un certificato "Apple Development" del team HS87DR6TBX nel portachiavi,
#   come lo zip della release.
#   Senza, firma ad-hoc: app e widget funzionano, ma macOS non valida l'App Group HS87DR6TBX.…
#   di una firma senza team (cfprefsd rifiuta letture e scritture). App e widget lo vedono
#   dalla propria firma e usano le loro UserDefaults (UserDefaultsSettings.defaultSuite):
#   l'app ricorda la lens scelta, il widget legge host, porta e LENS_TOKEN dal plist del
#   LaunchAgent (WidgetSettings, con l'eccezione in sola lettura del suo entitlement).
#   Niente quarantena: i file nascono su questo Mac.
# - Solo l'architettura di questo Mac.
#
# Stampa nell'ultima riga "firma: team" o "firma: ad-hoc" per install.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
NAME="OpenCode Lens Monitor"
TEAM="HS87DR6TBX"

die() {
  echo "$*" >&2
  exit 1
}

[[ $# -eq 1 ]] || die "uso: scripts/build-clt.sh <cartella di uscita> | --check"

yml() {
  sed -n "s/^ *$1: *\"\([^\"]*\)\".*/\1/p" "$ROOT/project.yml" | head -n 1
}

VERSION="$(yml MARKETING_VERSION)"
[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "MARKETING_VERSION in project.yml non è x.y.z: ${VERSION:-vuota}"
BUILD=$((10#${BASH_REMATCH[1]} * 10000 + 10#${BASH_REMATCH[2]} * 100 + 10#${BASH_REMATCH[3]}))
MACOS_MIN="$(yml macOS)"
APP_ID="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(.*\)$/\1/p' "$ROOT/project.yml" | head -n 1)"
WIDGET_ID="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(.*\)$/\1/p' "$ROOT/project.yml" | sed -n 2p)"
[[ -n "$MACOS_MIN" && -n "$APP_ID" && -n "$WIDGET_ID" ]] || die "project.yml: non trovo deploymentTarget o i bundle id."

# SHA-1 di un'identità "Apple Development" valida il cui certificato è del team (OU), vuoto se
# non ce n'è. Il nome tra parentesi è la persona, non il team, e due certificati possono avere
# lo stesso nome (uno scaduto e il suo sostituto): si confronta l'hash.
team_identity() {
  local hash name
  while IFS='|' read -r hash name; do
    [[ "$name" == "Apple Development:"* ]] || continue
    security find-certificate -a -Z -p 2>/dev/null |
      awk -v h="$hash" '/^SHA-1 hash:/ { f = ($3 == h) } f && /BEGIN CERTIFICATE/ { p = 1 } p { print } p && /END CERTIFICATE/ { exit }' |
      openssl x509 -noout -subject 2>/dev/null | grep -q "OU *= *$TEAM\(,\|\$\)" || continue
    echo "$hash"
    return
  done < <(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(.*\)"$/\1|\2/p')
}

TOOLS=1
xcrun --show-sdk-path >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1 || TOOLS=0
# LENS_MONITOR_SIGN_IDENTITY: un'identità per codesign, o - per la firma ad-hoc anche con un certificato
IDENTITY="${LENS_MONITOR_SIGN_IDENTITY:-$(team_identity)}"
IDENTITY="${IDENTITY:--}"
SIGNED_BY="team"
[[ "$IDENTITY" != - ]] || SIGNED_BY="ad-hoc"

if [[ "$1" == --check ]]; then
  if [[ "$TOOLS" -eq 1 ]]; then echo "Command Line Tools: SDK macOS $(xcrun --show-sdk-version), $(xcrun swiftc --version 2>&1 | head -n 1)"
  else echo "Command Line Tools: mancano (xcode-select --install, può servire un amministratore)"
  fi
  echo "firma: $SIGNED_BY"
  exit 0
fi

[[ "$TOOLS" -eq 1 ]] || die "Mancano i Command Line Tools: installali con xcode-select --install (può servire un amministratore)."
mkdir -p "$1"
OUT="$(cd "$1" && pwd -P)"
APP="$OUT/$NAME.app"
APPEX="$APP/Contents/PlugIns/OpenCodeLensWidget.appex"
SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macos$MACOS_MIN"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode-lens-monitor-build.XXXXXX")"
trap 'rm -rf "${WORK:?}"' EXIT

swift_files() {
  find "$@" -name '*.swift' | LC_ALL=C sort
}

compile() {
  # stessa versione del linguaggio e stessa ottimizzazione della build Release di Xcode
  xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 6 -O -whole-module-optimization "$@"
}

echo "Compilo OpenCode Monitor $VERSION (build $BUILD) per $(uname -m) con $(xcrun swiftc --version 2>&1 | head -n 1)…"

CORE=()
while IFS= read -r f; do CORE+=("$f"); done < <(swift_files "$ROOT/LensMonitorCore/Sources/LensMonitorCore")
compile -parse-as-library -module-name LensMonitorCore -emit-module -emit-module-path "$WORK/LensMonitorCore.swiftmodule" \
  -emit-library -static -o "$WORK/libLensMonitorCore.a" "${CORE[@]}"

MAIN=()
while IFS= read -r f; do MAIN+=("$f"); done < <(swift_files "$ROOT/OpenCodeLensMonitor" "$ROOT/Shared")
WIDGET=()
while IFS= read -r f; do WIDGET+=("$f"); done < <(swift_files "$ROOT/OpenCodeLensWidget" "$ROOT/Shared")

rm -rf "${APP:?}"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
compile -parse-as-library -module-name OpenCode_Lens_Monitor -I "$WORK" -L "$WORK" -lLensMonitorCore \
  -o "$APP/Contents/MacOS/$NAME" "${MAIN[@]}"
# entry point _NSExtensionMain, come Xcode imposta per ogni estensione (LD_ENTRY_POINT): avvia
# ExtensionKit e poi chiama main. Entrando da main, ExtensionFoundation non trova gli argomenti
# di lancio e si blocca (un force unwrap, senza messaggio) alla prima chiamata a WidgetKit.
compile -parse-as-library -application-extension -module-name OpenCodeLensWidget -I "$WORK" -L "$WORK" -lLensMonitorCore \
  -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -application_extension \
  -o "$APPEX/Contents/MacOS/OpenCodeLensWidget" "${WIDGET[@]}"

# Info.plist con le impostazioni di build che sostituirebbe Xcode
plist() {
  sed -e "s|\$(EXECUTABLE_NAME)|$2|g" -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$3|g" -e "s|\$(PRODUCT_NAME)|$2|g" \
    -e "s|\$(MARKETING_VERSION)|$VERSION|g" -e "s|\$(CURRENT_PROJECT_VERSION)|$BUILD|g" \
    -e "s|\$(MACOSX_DEPLOYMENT_TARGET)|$MACOS_MIN|g" "$1"
}
# le chiavi di piattaforma che Xcode aggiunge a ogni bundle
platform_keys() {
  plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$1"
  plutil -insert DTPlatformName -string macosx "$1"
  plutil -insert DTPlatformVersion -string "$(xcrun --show-sdk-version)" "$1"
  plutil -insert DTSDKName -string "macosx$(xcrun --show-sdk-version)" "$1"
  plutil -insert DTSDKBuild -string "$(xcrun --show-sdk-build-version)" "$1"
}
plist "$ROOT/OpenCodeLensMonitor/Resources/Info.plist" "$NAME" "$APP_ID" >"$APP/Contents/Info.plist"
platform_keys "$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"
plist "$ROOT/OpenCodeLensWidget/Info.plist" OpenCodeLensWidget "$WIDGET_ID" >"$APPEX/Contents/Info.plist"
platform_keys "$APPEX/Contents/Info.plist"
cp -R "$ROOT/scripts/clt/Metadata.appintents" "$APPEX/Contents/Resources/"
for p in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
  if grep -q '\$(' "$p"; then die "$p: restano variabili non sostituite."; fi
  plutil -lint -s "$p"
done

# swiftc firma già ad-hoc ciò che linka: codesign --force dice ogni volta "replacing existing
# signature", quindi il suo output si mostra solo se fallisce. Hardened Runtime come nella build
# Xcode (ENABLE_HARDENED_RUNTIME), anche ad-hoc: il core è linkato staticamente, la library
# validation non ha dylib da rifiutare.
sign() {
  local out
  out="$(codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$@" 2>&1)" || die "$out"
}
# dall'interno: prima il widget, poi l'app che lo sigilla
sign --entitlements "$ROOT/OpenCodeLensWidget/OpenCodeLensWidget.entitlements" "$APPEX"
sign --entitlements "$ROOT/OpenCodeLensMonitor/Resources/OpenCodeLensMonitor.entitlements" "$APP"
codesign --verify --deep --strict "$APP" || die "Firma non valida: $APP"
echo "OK: $APP"
echo "firma: $SIGNED_BY"
