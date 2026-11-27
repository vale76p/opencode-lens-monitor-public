#!/bin/bash
# Crea lo zip della release di OpenCode Lens Monitor, con l'app già compilata e firmata, su
# questo Mac. Servono Xcode con la licenza accettata, XcodeGen e il certificato "Apple
# Development" del team HS87DR6TBX nel portachiavi; niente sudo.
#   scripts/package.sh            → test + dist/opencode-lens-monitor-<versione>.zip
#   scripts/package.sh --upload   → … e lo allega alla release v<versione> (gh release upload)
# Lo zip contiene una cartella opencode-lens-monitor/ con l'app, install.sh, README.md,
# CHANGELOG.md, LICENSE e docs/aggiornamento.md, pronta per `bash install.sh`.
#
# - Si builda da `git archive HEAD` in una cartella temporanea fuori dal repo: XcodeGen prende
#   tutti i file delle cartelle dei sorgenti, quindi un file non tracciato finirebbe nell'app, e
#   gli attributi estesi di iCloud (~/Documents) fanno fallire la firma. Con modifiche non
#   committate o file non tracciati lo script si ferma: lo zip contiene esattamente HEAD.
# - CFBundleVersion viene dalla versione (major*10000 + minor*100 + patch): cresce a ogni
#   rilascio, così LaunchServices preferisce la copia più nuova e chronod rilegge i widget.
# - Lo zip si fa con ditto, non con zip: conserva i symlink del bundle e la firma resta valida.
#   Senza attributi estesi né quarantena: la firma non ne dipende.
# - App firmata "Apple Development", non notarizzata: install.sh toglie la quarantena.
# - Controlla anche che il «Source code» del tag si compili con i soli Command Line Tools
#   (scripts/build-clt.sh, per install.sh dove lo zip è bloccato) e che i metadati AppIntents
#   in scripts/clt/ siano quelli della build Xcode.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$HERE"

die() {
  echo "$*" >&2
  exit 1
}

UPLOAD=0
case "$#:${1:-}" in
  0:) ;;
  1:--upload) UPLOAD=1 ;;
  *) die "uso: scripts/package.sh [--upload]" ;;
esac

TEAM="HS87DR6TBX"
NAME="OpenCode Lens Monitor.app"
FILES=(install.sh README.md CHANGELOG.md LICENSE docs/aggiornamento.md)

[[ "$(git rev-parse --show-toplevel 2>/dev/null)" == "$HERE" ]] || die "$HERE non è la radice di un repository git: il pacchetto si crea dai file tracciati."
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  git status --short >&2
  die "Modifiche non committate o file non tracciati: fai commit (o toglili) prima di creare il pacchetto."
fi

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -n 1)"
[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "MARKETING_VERSION in project.yml non è x.y.z: ${VERSION:-vuota}"
MAJOR=$((10#${BASH_REMATCH[1]}))
MINOR=$((10#${BASH_REMATCH[2]}))
PATCH=$((10#${BASH_REMATCH[3]}))
[[ "$MINOR" -lt 100 && "$PATCH" -lt 100 ]] || die "minor e patch oltre 99: il numero di build $VERSION non sarebbe crescente."
BUILD=$((MAJOR * 10000 + MINOR * 100 + PATCH))
TAG="v$VERSION"
OUT="$HERE/dist/opencode-lens-monitor-$VERSION.zip"

grep -q "^\*\*Versione $VERSION\*\*" README.md || die "README.md non dice «Versione ${VERSION}»."
TOP="$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' CHANGELOG.md | head -n 1)"
[[ "$TOP" == "$VERSION" ]] || die "La prima versione di CHANGELOG.md è ${TOP:-nessuna}, project.yml dice $VERSION."
for f in "${FILES[@]}"; do
  git cat-file -e "HEAD:$f" 2>/dev/null || die "Manca $f nel commit HEAD: pacchetto non creato."
done
if [[ "$UPLOAD" -eq 1 ]]; then
  [[ "$(git rev-parse -q --verify "refs/tags/$TAG^{commit}" || true)" == "$(git rev-parse HEAD)" ]] ||
    die "Il tag $TAG non c'è o non è HEAD: fai git fetch --tags e git checkout $TAG (la release la crea release-please)."
  gh release view "$TAG" >/dev/null 2>&1 || die "La release $TAG non c'è su GitHub: la crea release-please al merge della PR di rilascio."
fi

echo "Test…"
scripts/test.sh >/dev/null || die "Test non riusciti: rilancia scripts/test.sh per vedere quali."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/opencode-lens-monitor-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/src"
git archive --format=tar HEAD | tar -x -C "$WORK/src"

echo "Build Release $VERSION (build $BUILD)…"
(cd "$WORK/src" && xcodegen generate --quiet) || die "xcodegen non riuscito (brew install xcodegen)."
xcodebuild -project "$WORK/src/OpenCodeLensMonitor.xcodeproj" -scheme OpenCodeLensMonitor -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$WORK/DerivedData" CURRENT_PROJECT_VERSION="$BUILD" -quiet build ||
  die "Build non riuscita: servono Xcode con la licenza accettata e il certificato Apple Development del team $TEAM nel portachiavi."
APP="$WORK/DerivedData/Build/Products/Release/$NAME"

verify() {
  local app="$1" exe
  codesign --verify --deep --strict "$app" || die "Firma non valida: $app"
  # come install.sh: TeamIdentifier da solo lo può impostare qualunque certificato autofirmato
  codesign --verify --deep --strict -R="anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\"" "$app" ||
    die "$app non è firmata dal team $TEAM con un certificato Apple."
  for p in "$app" "$app/Contents/PlugIns/OpenCodeLensWidget.appex"; do
    [[ "$(codesign -dv "$p" 2>&1 | sed -n 's/^CodeDirectory .* flags=[^(]*(\([^)]*\)).*/\1/p')" == *runtime* ]] || die "$p non ha l'Hardened Runtime."
    [[ "$(plutil -extract CFBundleShortVersionString raw "$p/Contents/Info.plist")" == "$VERSION" ]] || die "Versione sbagliata in $p"
    [[ "$(plutil -extract CFBundleVersion raw "$p/Contents/Info.plist")" == "$BUILD" ]] || die "Numero di build sbagliato in $p"
  done
  # Intel e Apple silicon: un Mac aziendale può essere l'uno o l'altro
  exe="$app/Contents/MacOS/OpenCode Lens Monitor"
  [[ " $(lipo -archs "$exe") " == *" arm64 "* && " $(lipo -archs "$exe") " == *" x86_64 "* ]] || die "L'app non è universale: $(lipo -archs "$exe")"
}
verify "$APP"

# I metadati AppIntents che scripts/build-clt.sh copia nel widget: li genera solo
# appintentsmetadataprocessor di Xcode, quindi stanno in scripts/clt/ e devono coincidere.
META="$APP/Contents/PlugIns/OpenCodeLensWidget.appex/Contents/Resources/Metadata.appintents"
if ! cmp -s "$META/extract.actionsdata" "$WORK/src/scripts/clt/Metadata.appintents/extract.actionsdata"; then
  rm -rf "$HERE/dist/Metadata.appintents"
  mkdir -p "$HERE/dist"
  ditto "$META" "$HERE/dist/Metadata.appintents"
  die "I metadati AppIntents del widget sono cambiati: rm -rf scripts/clt/Metadata.appintents && cp -R dist/Metadata.appintents scripts/clt/, poi commit e rilancia."
fi

# Il «Source code» del tag deve compilare senza Xcode: lo fa install.sh dove lo zip è bloccato.
CLT=/Library/Developer/CommandLineTools
if [[ -d "$CLT/SDKs" ]]; then
  echo "Build con i soli Command Line Tools…"
  DEVELOPER_DIR="$CLT" bash "$WORK/src/scripts/build-clt.sh" "$WORK/clt" >/dev/null ||
    die "Il Source code non si compila con i soli Command Line Tools: install.sh fallirebbe dove lo zip è bloccato."
  nm -u "$WORK/clt/$NAME/Contents/PlugIns/OpenCodeLensWidget.appex/Contents/MacOS/OpenCodeLensWidget" | grep -q _NSExtensionMain ||
    die "Il widget compilato con i Command Line Tools non entra da _NSExtensionMain."
else
  echo "Command Line Tools non installati: salto la build senza Xcode." >&2
fi

PKG="$WORK/pkg/opencode-lens-monitor"
mkdir -p "$PKG/docs"
ditto "$APP" "$PKG/$NAME"
for f in "${FILES[@]}"; do cp "$WORK/src/$f" "$PKG/$f"; done
chmod 755 "$PKG/install.sh"
mkdir -p "$HERE/dist"
rm -f "$OUT"
(cd "$WORK/pkg" && ditto -c -k --norsrc --noextattr --noqtn --keepParent opencode-lens-monitor "$OUT")

echo "Verifica del pacchetto…"
mkdir "$WORK/check"
ditto -x -k "$OUT" "$WORK/check"
verify "$WORK/check/opencode-lens-monitor/$NAME"
for f in "${FILES[@]}"; do
  [[ -f "$WORK/check/opencode-lens-monitor/$f" ]] || die "Nel pacchetto manca $f"
done
[[ -x "$WORK/check/opencode-lens-monitor/install.sh" ]] || die "install.sh non eseguibile nel pacchetto"
bash -n "$WORK/check/opencode-lens-monitor/install.sh"

echo "OK: dist/opencode-lens-monitor-$VERSION.zip ($(du -h "$OUT" | cut -f 1 | tr -d ' '), sha256 $(shasum -a 256 "$OUT" | cut -d ' ' -f 1))"

if [[ "$UPLOAD" -eq 1 ]]; then
  gh release upload "$TAG" "$OUT" --clobber
  echo "Allegato alla release $TAG."
fi
