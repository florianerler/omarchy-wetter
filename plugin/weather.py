#!/usr/bin/env python3
"""Wetter-Streamer fuer das Leisten-Plugin: holt Open-Meteo und schreibt je Abruf EINE JSON-Zeile auf stdout.

Ort: ~/.local/state/omarchy/settings/weather.json (wie omarchy-weather-location), sonst geo.omarchy.org.
Nur stdlib. Fehler -> {"ok": false, "error": ...}; der Abruf wird bald wiederholt.
"""
import json, os, sys, time, urllib.parse, urllib.request

LOC_FILE = os.path.expanduser("~/.local/state/omarchy/settings/weather.json")
EVERY_OK, EVERY_ERR = 600, 60
UA = {"User-Agent": "omarchy-wetter-plugin"}

# WMO-Wettercode -> (Material-Design-Icon Tag, Icon Nacht, Text)
ICONS = {"sun": "\U000F0599", "moon": "\U000F0594", "part": "\U000F0595", "cloud": "\U000F0590", "fog": "\U000F0591",
         "rain": "\U000F0597", "pour": "\U000F0596", "snow": "\U000F0598", "sleet": "\U000F067F",
         "storm": "\U000F067E", "hail": "\U000F0592"}
CODES = {0: ("sun", "Klar"), 1: ("sun", "Überwiegend klar"), 2: ("part", "Teils bewölkt"), 3: ("cloud", "Bedeckt"),
         45: ("fog", "Nebel"), 48: ("fog", "Reifnebel"), 51: ("rain", "Leichter Nieselregen"), 53: ("rain", "Nieselregen"),
         55: ("rain", "Starker Nieselregen"), 56: ("sleet", "Gefrierender Nieselregen"), 57: ("sleet", "Gefrierender Nieselregen"),
         61: ("rain", "Leichter Regen"), 63: ("rain", "Regen"), 65: ("pour", "Starkregen"), 66: ("sleet", "Gefrierender Regen"),
         67: ("sleet", "Gefrierender Regen"), 71: ("snow", "Leichter Schneefall"), 73: ("snow", "Schneefall"),
         75: ("snow", "Starker Schneefall"), 77: ("snow", "Schneegriesel"), 80: ("rain", "Leichte Schauer"),
         81: ("rain", "Schauer"), 82: ("pour", "Heftige Schauer"), 85: ("snow", "Schneeschauer"), 86: ("snow", "Starke Schneeschauer"),
         95: ("storm", "Gewitter"), 96: ("hail", "Gewitter mit Hagel"), 99: ("hail", "Schweres Gewitter mit Hagel")}
COMPASS = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]


MAX_BYTES = 2_000_000       # Antworten sind klein (<100 kB); alles Groessere ist ein Fehler


def get(url, timeout=15):
    if not url.startswith("https://"):
        raise ValueError("nur https erlaubt")
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        raw = r.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError("Antwort zu gross")
    return json.loads(raw)


def coords(lat, lon):
    """Breite/Laenge pruefen, bevor sie in eine URL wandern (Datei und Geo-Dienst sind nicht vertrauenswuerdig)."""
    lat, lon = float(lat), float(lon)
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError("Koordinaten ausserhalb des Bereichs")
    return lat, lon


def location():
    try:
        with open(LOC_FILE) as f:
            d = json.load(f)
        if d.get("latitude") is not None and d.get("longitude") is not None:
            return str(d.get("name") or "")[:60], *coords(d["latitude"], d["longitude"])
        if d.get("name"):                                   # nur Name: ueber Open-Meteo-Geocoding aufloesen
            g = get("https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + urllib.parse.quote(d["name"]))
            r = g["results"][0]
            return str(d["name"])[:60], *coords(r["latitude"], r["longitude"])
    except (OSError, ValueError, KeyError, IndexError):
        pass
    d = get("https://geo.omarchy.org/")        # Fallback: Ort per IP (wie das Omarchy-eigene Wetter-Widget)
    return str(d.get("name") or "")[:60], *coords(d["latitude"], d["longitude"])


def icon(code, night=False):
    key, text = CODES.get(code, ("cloud", "Unbekannt"))
    if night and key == "sun":
        key = "moon"
    return ICONS[key], text


def hhmm(iso):
    return iso[11:16]


def fetch():
    name, lat, lon = location()
    q = urllib.parse.urlencode({
        "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 8, "wind_speed_unit": "kmh",
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,"
                   "wind_direction_10m,wind_gusts_10m,surface_pressure,pressure_msl,precipitation,cloud_cover",
        "hourly": "temperature_2m,precipitation_probability,precipitation,weather_code,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,"
                 "sunrise,sunset,uv_index_max,wind_gusts_10m_max",
        "minutely_15": "precipitation", "forecast_minutely_15": 12})
    d = get("https://api.open-meteo.com/v1/forecast?" + q)
    c, h, dl = d["current"], d["hourly"], d["daily"]
    ic, text = icon(c["weather_code"], not c["is_day"])
    now_iso = c["time"][:13]
    start = max(0, next((i for i, t in enumerate(h["time"]) if t[:13] >= now_iso), 0))
    hours = []
    for i in range(start, min(start + 24, len(h["time"]))):
        hours.append({"t": hhmm(h["time"][i]), "temp": h["temperature_2m"][i], "pop": h["precipitation_probability"][i] or 0,
                      "mm": h["precipitation"][i] or 0, "icon": icon(h["weather_code"][i], not h["is_day"][i])[0]})
    days = []
    for i in range(min(7, len(dl["time"]))):
        days.append({"date": dl["time"][i], "min": dl["temperature_2m_min"][i], "max": dl["temperature_2m_max"][i],
                     "pop": dl["precipitation_probability_max"][i] or 0, "mm": dl["precipitation_sum"][i] or 0,
                     "icon": icon(dl["weather_code"][i])[0], "text": icon(dl["weather_code"][i])[1]})
    rain = [x or 0 for x in d.get("minutely_15", {}).get("precipitation", [])]
    rain_t = [hhmm(t) for t in d.get("minutely_15", {}).get("time", [])]
    return {"ok": True, "t": time.time(), "place": name,
            "now": {"temp": c["temperature_2m"], "feels": c["apparent_temperature"], "hum": c["relative_humidity_2m"],
                    "icon": ic, "text": text, "wind": c["wind_speed_10m"], "gust": c["wind_gusts_10m"],
                    "dir": COMPASS[int((c["wind_direction_10m"] + 22.5) // 45) % 8], "press": c["surface_pressure"],
                    "mm": c["precipitation"], "cloud": c["cloud_cover"], "night": not c["is_day"]},
            "foehn": foehn(c["pressure_msl"]),
            "today": {"uv": dl["uv_index_max"][0], "sunrise": hhmm(dl["sunrise"][0]), "sunset": hhmm(dl["sunset"][0]),
                      "min": dl["temperature_2m_min"][0], "max": dl["temperature_2m_max"][0]},
            "rain": rain, "rain_t": rain_t, "hours": hours, "days": days}


BOZEN = (46.4983, 11.3548)


def foehn(msl_innsbruck):
    """Foehn-Index: auf Meereshoehe reduzierter Luftdruck Bozen minus Innsbruck (Open-Meteo, Modellwerte).
    Positiv = Druck im Sueden hoeher -> Suedfoehn. Bei Fehler None (Rest des Widgets laeuft weiter)."""
    try:
        b = get("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=pressure_msl&timezone=auto" % BOZEN)
        bz = b["current"]["pressure_msl"]
        return {"bozen": float(bz), "innsbruck": float(msl_innsbruck), "diff": round(float(bz) - float(msl_innsbruck), 1)}
    except Exception:
        return None


def main():
    while True:
        try:
            out, wait = fetch(), EVERY_OK
        except Exception as e:                       # offline, API-Fehler, kein Ort ...
            out, wait = {"ok": False, "error": type(e).__name__ + ": " + str(e)[:80]}, EVERY_ERR
        sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
        sys.stdout.flush()
        time.sleep(wait)


if __name__ == "__main__":
    if "--once" in sys.argv:
        print(json.dumps(fetch(), ensure_ascii=False, indent=1))
    else:
        main()
