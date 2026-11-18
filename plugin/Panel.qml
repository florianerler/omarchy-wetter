import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Wetter: Icon + Temperatur in der Leiste, Popup mit Jetzt-Wetter, Regenvorschau (15-min-Raster),
// Stundenverlauf und 7-Tage-Prognose. Daten liefert weather.py (eine JSON-Zeile pro Abruf, alle 10 min).
Panel {
  id: root
  moduleName: "wetter"
  ipcTarget: "wetter"

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property var weekdays: ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

  property var wx: ({ ok: false, error: "" })
  property bool loaded: false

  function r(v) { return Math.round(v) }
  function d1(v) { return (Math.round(v * 10) / 10).toString().replace(".", ",") }
  function deg(v) { return r(v) + " °C" }
  function kel(v) { return Math.round(v + 273.15) + " K" }
  function sgn(v) { return (v > 0 ? "+" : v < 0 ? "−" : "±") + d1(Math.abs(v)) }
  // Foehn-Faustwerte fuer Delta p (Bozen − Innsbruck, auf Meereshoehe reduziert): ab ca. +4 hPa Suedfoehn, ab +2 moeglich;
  // stark negativ = Nordstau/Nordfoehn-Lage (Druck in Innsbruck hoeher).
  function foehnText(d) {
    if (d >= 6) return "Starker Südföhn"
    if (d >= 4) return "Südföhn"
    if (d >= 2) return "Südföhn möglich"
    if (d <= -4) return "Nordföhn-Lage (Südtirol)"
    if (d <= -2) return "Nordföhn möglich"
    return "Kein Föhn"
  }
  function dayName(iso, i) { return i === 0 ? "Heute" : weekdays[new Date(iso + "T12:00:00").getDay()] }

  readonly property string barIcon: loaded && wx.ok ? wx.now.icon : "󰖑"
  readonly property string tooltip: !loaded ? "Wetter lädt …" : !wx.ok ? "Wetter nicht erreichbar" :
    wx.place + "\n" + wx.now.text + ", " + kel(wx.now.temp) + " (" + deg(wx.now.temp) + ")\n" +
    "Wind " + r(wx.now.wind) + " km/h " + wx.now.dir + (wx.foehn ? "\nFöhn Δp " + sgn(wx.foehn.diff) + " hPa · " + foehnText(wx.foehn.diff) : "")

  // Regenvorschau: Zeile fuer die Kopfzeile des Regen-Blocks
  readonly property string rainSummary: {
    if (!loaded || !wx.ok || !wx.rain || wx.rain.length === 0) return ""
    var firstWet = -1, total = 0
    for (var i = 0; i < wx.rain.length; i++) { total += wx.rain[i]; if (firstWet < 0 && wx.rain[i] >= 0.05) firstWet = i }
    if (firstWet < 0) return "Trocken in den nächsten 3 Stunden"
    if (firstWet === 0) return "Regnet jetzt · " + d1(total) + " mm in 3 h"
    return "Regen ab " + wx.rain_t[firstWet] + " · " + d1(total) + " mm in 3 h"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: streamer
    command: ["python3", "-I", root.pluginDir + "/weather.py"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try { root.wx = JSON.parse(line); root.loaded = true } catch (e) {}
      }
    }
    onExited: restartTimer.restart()
  }
  Timer { id: restartTimer; interval: 5000; onTriggered: streamer.running = true }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    tooltipText: root.tooltip
    dimmed: root.loaded && !root.wx.ok
    onPressed: function(b) { root.toggle() }
  }

  component Lbl: Text {
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  component Muted: Lbl {
    color: Qt.darker(Commons.Color.foreground, 1.5)
    font.pixelSize: Style.font.caption
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(1000))

    content: PanelKeyCatcher {
      implicitHeight: Math.min(col.implicitHeight, Style.space(1000))
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        Connections { target: root; function onOpenedChanged() { if (root.opened) scroller.contentY = 0 } }

        Column {
          id: col
          width: scroller.width
          spacing: Style.space(14)

          // ---- Fehler / Laden ----
          Lbl {
            visible: !root.loaded || !root.wx.ok
            width: parent.width
            wrapMode: Text.Wrap
            text: !root.loaded ? "Wetter lädt …" : "Wetter nicht erreichbar" + (root.wx.error ? "\n" + root.wx.error : "")
          }

          // ---- Jetzt ----
          Item {
            visible: root.loaded && root.wx.ok
            width: parent.width
            height: nowRow.implicitHeight
            Row {
              id: nowRow
              spacing: Style.space(14)
              Lbl { text: root.wx.now ? root.wx.now.icon : ""; font.pixelSize: Style.font.displayLarge * 2; anchors.verticalCenter: parent.verticalCenter }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Row {
                  spacing: Style.space(8)
                  Lbl { id: bigK; text: root.wx.now ? root.kel(root.wx.now.temp) : ""; font.pixelSize: Style.font.displayLarge * 1.5; font.bold: true }
                  Muted { text: root.wx.now ? root.deg(root.wx.now.temp) : ""; anchors.baseline: bigK.baseline }
                }
                Lbl { text: root.wx.now ? root.wx.now.text : "" }
                Muted { text: root.wx.now ? root.wx.place + " · gefühlt " + root.kel(root.wx.now.feels) + " (" + root.deg(root.wx.now.feels) + ")" : "" }
              }
            }
          }

          Grid {
            visible: root.loaded && root.wx.ok
            width: parent.width
            columns: 2
            columnSpacing: Style.space(14)
            rowSpacing: Style.space(6)
            Muted { text: "Wind" }
            Lbl { text: root.wx.now ? root.r(root.wx.now.wind) + " km/h " + root.wx.now.dir + " (Böen " + root.r(root.wx.now.gust) + ")" : "" }
            Muted { text: "Luftfeuchte" }
            Lbl { text: root.wx.now ? root.wx.now.hum + " %" : "" }
            Muted { text: "Luftdruck" }
            Lbl { text: root.wx.now ? root.r(root.wx.now.press) + " hPa" : "" }
            Muted { text: "Bewölkung" }
            Lbl { text: root.wx.now ? root.wx.now.cloud + " %" : "" }
            Muted { text: "UV heute" }
            Lbl { text: root.wx.today ? root.d1(root.wx.today.uv) : "" }
            Muted { text: "Sonne" }
            Lbl { text: root.wx.today ? "↑ " + root.wx.today.sunrise + "   ↓ " + root.wx.today.sunset : "" }
          }

          PanelSeparator { width: parent.width; visible: root.loaded && root.wx.ok }

          // ---- Föhn ----
          Column {
            visible: root.loaded && root.wx.ok && !!root.wx.foehn
            width: parent.width
            spacing: Style.space(6)
            Lbl { text: "Föhn"; font.bold: true; font.pixelSize: Style.font.subtitle }
            Row {
              spacing: Style.space(10)
              Lbl {
                id: dpLabel
                text: root.wx.foehn ? "Δp " + root.sgn(root.wx.foehn.diff) + " hPa" : ""
                font.pixelSize: Style.font.title; font.bold: true
                color: root.wx.foehn && Math.abs(root.wx.foehn.diff) >= 4 ? Commons.Color.accent : Commons.Color.foreground
              }
              Lbl { text: root.wx.foehn ? root.foehnText(root.wx.foehn.diff) : ""; anchors.baseline: dpLabel.baseline }
            }
            Muted { text: root.wx.foehn ? "Bozen " + root.d1(root.wx.foehn.bozen) + " hPa − Innsbruck " + root.d1(root.wx.foehn.innsbruck) + " hPa (auf Meereshöhe)" : "" }
            Muted { text: "Faustwerte: ab +4 hPa Südföhn, ab +2 möglich" }
          }

          PanelSeparator { width: parent.width; visible: root.loaded && root.wx.ok && !!root.wx.foehn }

          // ---- Regenvorschau ----
          Column {
            id: rainCol
            readonly property real maxMm: Math.max(1.0, Math.max.apply(null, root.wx.rain || [0]))
            visible: root.loaded && root.wx.ok && root.wx.rain && root.wx.rain.length > 0
            width: parent.width
            spacing: Style.space(6)
            Lbl { text: "Regenvorschau"; font.bold: true; font.pixelSize: Style.font.subtitle }
            Muted { text: root.rainSummary }
            Row {
              id: bars
              width: parent.width
              height: Style.space(44)
              spacing: Style.space(3)
              Repeater {
                model: root.wx.rain || []
                Item {
                  width: (bars.width - bars.spacing * 11) / 12
                  height: bars.height
                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    radius: Style.space(2)
                    height: modelData >= 0.05 ? Math.max(Style.space(4), parent.height * modelData / rainCol.maxMm) : Style.space(2)
                    color: modelData >= 0.05 ? Commons.Color.accent : Qt.darker(Commons.Color.foreground, 2.2)
                  }
                }
              }
            }
            Item {
              width: parent.width
              height: tick1.implicitHeight
              Muted { id: tick1; anchors.left: parent.left; text: root.wx.rain_t ? root.wx.rain_t[0] : "" }
              Muted { anchors.horizontalCenter: parent.horizontalCenter; text: root.wx.rain_t ? root.wx.rain_t[6] : "" }
              Muted { anchors.right: parent.right; text: root.wx.rain_t ? root.wx.rain_t[11] : "" }
            }
          }

          PanelSeparator { width: parent.width; visible: root.loaded && root.wx.ok }

          // ---- Stunden ----
          Column {
            visible: root.loaded && root.wx.ok
            width: parent.width
            spacing: Style.space(6)
            Lbl { text: "Nächste Stunden"; font.bold: true; font.pixelSize: Style.font.subtitle }
            Flickable {
              width: parent.width
              height: hourRow.implicitHeight
              contentWidth: hourRow.implicitWidth
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.HorizontalFlick
              Row {
                id: hourRow
                spacing: Style.space(4)
                Repeater {
                  model: root.wx.hours || []
                  Column {
                    width: Style.space(46)
                    spacing: Style.space(3)
                    Muted { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t }
                    Lbl { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.pixelSize: Style.font.title }
                    Lbl { anchors.horizontalCenter: parent.horizontalCenter; text: root.kel(modelData.temp) }
                    Muted { anchors.horizontalCenter: parent.horizontalCenter; text: root.deg(modelData.temp) }
                    Muted {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.pop > 0 ? modelData.pop + "%" : " "
                      color: modelData.pop >= 50 ? Commons.Color.accent : Qt.darker(Commons.Color.foreground, 1.7)
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width; visible: root.loaded && root.wx.ok }

          // ---- 7 Tage ----
          Column {
            id: week
            visible: root.loaded && root.wx.ok
            width: parent.width
            spacing: Style.space(5)
            readonly property real lo: Math.min.apply(null, (root.wx.days || [{ min: 0 }]).map(function(d) { return d.min }))
            readonly property real hi: Math.max.apply(null, (root.wx.days || [{ max: 1 }]).map(function(d) { return d.max }))
            Lbl { text: "7 Tage"; font.bold: true; font.pixelSize: Style.font.subtitle }
            Repeater {
              model: root.wx.days || []
              Item {
                width: week.width
                height: Style.space(24)
                Lbl { x: 0; anchors.verticalCenter: parent.verticalCenter; text: root.dayName(modelData.date, index); width: Style.space(46) }
                Lbl { x: Style.space(46); anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; font.pixelSize: Style.font.title }
                Muted {
                  x: Style.space(80); anchors.verticalCenter: parent.verticalCenter; width: Style.space(40)
                  text: modelData.pop > 0 ? modelData.pop + "%" : ""
                  color: modelData.pop >= 50 ? Commons.Color.accent : Qt.darker(Commons.Color.foreground, 1.7)
                }
                Muted { x: Style.space(112); anchors.verticalCenter: parent.verticalCenter; width: Style.space(44); text: root.kel(modelData.min); horizontalAlignment: Text.AlignRight }
                Item {
                  x: Style.space(164); width: parent.width - Style.space(164) - Style.space(50); height: parent.height
                  Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: Style.space(4); radius: height / 2; color: Qt.darker(Commons.Color.foreground, 3) }
                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * (modelData.min - week.lo) / Math.max(1, week.hi - week.lo)
                    width: Math.max(Style.space(6), parent.width * (modelData.max - modelData.min) / Math.max(1, week.hi - week.lo))
                    height: Style.space(4); radius: height / 2; color: Commons.Color.accent
                  }
                }
                Lbl { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: Style.space(46); text: root.kel(modelData.max); horizontalAlignment: Text.AlignRight }
              }
            }
          }

          Muted {
            visible: root.loaded && root.wx.ok
            text: "Open-Meteo · Aktualisierung alle 10 min"
          }
        }
      }
    }
  }
}
