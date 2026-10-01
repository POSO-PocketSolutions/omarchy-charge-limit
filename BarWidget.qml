import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property string mode: panelLoader.item ? panelLoader.item.mode : "unknown"
  readonly property bool supported: panelLoader.item ? panelLoader.item.supported === true : true
  readonly property int percentage: panelLoader.item ? Number(panelLoader.item.percentage || -1) : -1
  readonly property string batteryState: panelLoader.item ? panelLoader.item.batteryState : ""
  readonly property color limitedColor: String(setting("limitedColor", "#3fb950"))
  readonly property color fullColor: String(setting("fullColor", "#d29922"))

  readonly property color iconColor: {
    if (!root.supported) return bar ? bar.urgent : Color.urgent
    return bar ? bar.barForeground : Color.foreground
  }

  readonly property color badgeColor: {
    if (!root.supported) return bar ? bar.urgent : Color.urgent
    if (root.mode === "full") return root.fullColor
    if (root.mode === "limited") return root.limitedColor
    return bar ? bar.barForeground : Color.foreground
  }

  readonly property var levelGlyphs: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  readonly property var chargingGlyphs: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]

  // Battery glyph tracks the real charge level like the native panel. While
  // in full-charge mode and actively charging we show the charging ramp;
  // otherwise the stepped outline. The limit state is conveyed by color plus
  // the overlay badge (lock for limited, bolt for full).
  readonly property string iconGlyph: {
    var pct = root.percentage
    if (pct < 0) return root.mode === "full" ? "󰂄" : "󰂏"
    var index = Math.max(0, Math.min(9, Math.floor(pct / 10)))
    if (root.mode === "full" && root.batteryState === "Charging") return root.chargingGlyphs[index]
    return root.levelGlyphs[index]
  }

  readonly property string badgeGlyph: root.mode === "full" ? "󱐋" : "󰌾"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function refresh() { if (panelLoader.item) panelLoader.item.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.mnsosa.charge-limit"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.barSize
    fixedHeight: root.barSize
    tooltipText: panelLoader.item ? panelLoader.item.shortStatus : "Charge limit"
    onPressed: root.togglePanel()

    Item {
      id: glyph
      anchors.centerIn: parent
      width: Style.space(20)
      height: Math.round(width * 954 / 1063)

      Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/icon-white.png")
        sourceSize.width: 1063
        sourceSize.height: 954
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: false
        opacity: root.supported ? 1.0 : 0.45
      }
    }

    Text {
      visible: root.supported
      text: root.badgeGlyph
      color: root.badgeColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.round(Style.font.caption * 0.9)
      anchors.right: glyph.right
      anchors.bottom: glyph.bottom
      anchors.rightMargin: -Style.space(1)
      anchors.bottomMargin: -Style.space(1)

      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }
}
