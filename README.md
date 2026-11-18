# wetter

Wetter-Widget für **Omarchy** (Quickshell-Leiste `omarchy-shell`): in der Leiste nur das Wettersymbol, per Klick ein
Popup mit Temperatur (Kelvin groß, °C klein), Regenvorschau, Stundenverlauf, 7-Tage-Prognose und einem
**Föhn-Block** (Luftdruckdifferenz Bozen − Innsbruck). Ersetzt das eingebaute `omarchy.weather`.

| Bereich | Inhalt |
|---|---|
| Jetzt | Temperatur in K und °C, gefühlt, Wind mit Richtung und Böen, Feuchte, Druck, Bewölkung, UV, Sonnenzeiten |
| Föhn | Δp = Druck Bozen − Druck Innsbruck (beide auf Meereshöhe reduziert), Einordnung als Text |
| Regenvorschau | Niederschlag der nächsten 3 h im 15-Minuten-Raster |
| Stunden | nächste 24 h: Icon, K, °C, Regenwahrscheinlichkeit |
| 7 Tage | Min/Max als Balken, Regenwahrscheinlichkeit |

**Föhn-Einordnung:** ab +4 hPa „Südföhn", ab +2 „möglich", ab +6 „stark"; negativ spiegelbildlich (Nordföhn-Lage).
Das sind **Faustwerte**, keine Warnung. Die Daten sind **Modellwerte** (Open-Meteo), keine Stationsmessungen.

## Installation

```
./install.sh
omarchy restart shell      # einmal, damit die Leiste das Plugin neu lädt
```

Das Skript prüft das Manifest, legt einen Link nach `~/.config/omarchy/plugins/wetter` an, setzt den Leisten-Eintrag
anstelle von `omarchy.weather` (das nur deaktiviert wird) und sichert vorher `shell.json` als `shell.json.bak.<zeit>`.
Zurück zum Original: `omarchy plugin enable omarchy.weather` und `omarchy plugin disable wetter`.

## Ort

Der Ort kommt aus der Omarchy-Einstellung (`~/.local/state/omarchy/settings/weather.json`):

```
omarchy-weather-location --set Innsbruck 47.2692,11.4041
omarchy-weather-location --clear      # zurück zur Erkennung per IP
```

## Datenschutz und Sicherheit

- Abgefragt werden nur `api.open-meteo.com` und, für einen Ort ohne Koordinaten, `geocoding-api.open-meteo.com`. Kein
  API-Key, keine Konten, kein Tracking, alles per HTTPS.
- Ohne gesetzten Ort wird **per IP** über `geo.omarchy.org` geortet (wie das Omarchy-eigene Widget). Wer das nicht will,
  setzt den Ort fest (siehe oben).
- Der Streamer (`plugin/weather.py`) nutzt nur die Standardbibliothek, läuft mit `python3 -I`, erlaubt nur https,
  begrenzt die Antwortgröße auf 2 MB und prüft Koordinaten, bevor sie in eine URL gelangen. Ein Fehler zeigt „Wetter nicht
  erreichbar" im Popup, die Leiste bleibt unberührt.
- Im Repo stehen keine Zugangsdaten und keine persönlichen Daten.

## Tests

```
python3 -I -m unittest discover -s tests     # offline
```

Lizenz: MIT.
