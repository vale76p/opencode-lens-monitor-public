#!/bin/bash
# Test di LensMonitorCore (Swift Testing, bastano i Command Line Tools).
# - La build va fuori dal repo: se il repo sta in una cartella sincronizzata con iCloud
#   (es. ~/Documents), gli attributi estesi aggiunti da File Provider fanno fallire la
#   firma ad-hoc del bundle dei test.
# - Il percorso dei plugin delle macro di Swift Testing è passato esplicitamente: con i
#   soli Command Line Tools a volte il compilatore non lo trova ("plugin for module
#   'TestingMacros' not found").
# Uso: scripts/test.sh [argomenti di swift test, es. --filter LensClientTests]
set -euo pipefail
cd "$(dirname "$0")/../LensMonitorCore"
args=(--scratch-path "${LENS_MONITOR_BUILD:-$HOME/Library/Caches/opencode-lens-monitor/LensMonitorCore}")
plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$plugins" ]]; then
  args+=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi
exec swift test "${args[@]}" "$@"
