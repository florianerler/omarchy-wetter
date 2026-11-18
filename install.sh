#!/bin/bash
# Installiert das Wetter-Plugin: Link nach ~/.config/omarchy/plugins, Leisten-Eintrag anstelle von omarchy.weather.
# Idempotent. Sichert shell.json vor der Aenderung.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID=wetter; OLD=omarchy.weather
SHELL_JSON="$HOME/.config/omarchy/shell.json"
omarchy plugin validate "$REPO/plugin"
mkdir -p "$HOME/.config/omarchy/plugins"
ln -sfn "$REPO/plugin" "$HOME/.config/omarchy/plugins/$ID"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6; do omarchy plugin list 2>/dev/null | grep -q "^$ID " && break; sleep 1; done
omarchy plugin list | grep -q "^$ID " || { echo "Plugin '$ID' nicht gefunden." >&2; exit 1; }
has() { jq -e --arg i "$1" '[.bar.layout[]|arrays[]|objects|.id]|index($i)' "$SHELL_JSON" >/dev/null 2>&1; }
cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
has "$ID" || omarchy bar put "$ID" --after "$OLD" >/dev/null
if has "$OLD"; then omarchy plugin disable "$OLD" >/dev/null 2>&1 || true; fi
if has "$OLD"; then   # Fallback: Eintrag direkt entfernen
  jq --arg i "$OLD" '.bar.layout |= with_entries(.value |= (if type=="array" then map(select((objects|.id)!=$i)) else . end))' "$SHELL_JSON" >"$SHELL_JSON.tmp" && mv "$SHELL_JSON.tmp" "$SHELL_JSON"
fi
echo "Fertig. Falls die Leiste nichts zeigt: omarchy restart shell"
