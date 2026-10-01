import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.mnsosa.charge-limit"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property bool supported: true
  property string mode: "unknown"
  property string savedStart: "75"
  property string savedEnd: "80"
  property bool enabled: true
  property string percentage: ""
  property string batteryState: ""
  property string error: ""
  property bool busy: false
  property bool historyAvailable: false
  property var historyPoints: []
  property real historyStart: 0
  property real historyEnd: 0
  property string historyError: ""

  property bool editing: false
  property int draftStart: 75
  property int draftEnd: 80

  readonly property var barIdentity: hostWidget || root
  readonly property int refreshInterval: Math.max(5, Number(setting("refreshIntervalSec", 30))) * 1000
  readonly property color limitedColor: String(setting("limitedColor", "#3fb950"))
  readonly property color fullColor: String(setting("fullColor", "#d29922"))
  readonly property color foregroundColor: bar ? bar.barForeground : Color.foreground
  readonly property color failureColor: bar ? bar.urgent : Color.urgent
  readonly property color mutedColor: Util.alpha(foregroundColor, 0.5)

  readonly property string statusPath: pathFor("scripts/status")
  readonly property string actionPath: pathFor("scripts/action")
  readonly property string historyPath: pathFor("scripts/history")

  readonly property string savedLabel: savedStart + "-" + savedEnd + "%"

  readonly property string shortStatus: {
    if (!supported) return "Charge thresholds not supported"
    if (mode === "full") return "Charging to 100% (limit off)"
    if (mode === "limited") return "Limited to " + savedLabel
    return "Charge limit"
  }

  readonly property string statusTitle: {
    if (!supported) return "Not supported"
    if (mode === "full") return "Charging to 100%"
    if (mode === "limited") return "Protected"
    return "Charge limit"
  }

  readonly property string statusDetail: {
    if (!supported) return "This battery does not expose charge thresholds"
    if (mode === "full") return "Limit lifted · will top up to 100%"
    if (mode === "limited") return "Holding at " + savedLabel + " to extend battery life"
    return "Reading state…"
  }

  readonly property color statusColor: {
    if (!supported) return failureColor
    if (mode === "full") return fullColor
    if (mode === "limited") return limitedColor
    return mutedColor
  }

  function pathFor(relativePath) {
    return decodeURIComponent(Qt.resolvedUrl(relativePath).toString().replace("file://", ""))
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!historyProc.running) historyProc.running = true
  }

  function applyStatus(raw) {
    try {
      var payload = JSON.parse(raw)
      supported = payload.supported === true
      mode = String(payload.mode || "unknown")
      savedStart = String(payload.savedStart || "75")
      savedEnd = String(payload.savedEnd || "80")
      enabled = payload.enabled === true
      percentage = String(payload.percentage || "")
      batteryState = String(payload.batteryState || "")
      error = ""
      if (!editing) {
        draftStart = Number(savedStart)
        draftEnd = Number(savedEnd)
      }
    } catch (exception) {
      error = "Could not read charge-limit state"
    }
  }

  function applyHistory(raw) {
    try {
      var payload = JSON.parse(raw)
      historyAvailable = payload.available === true
      historyPoints = Array.isArray(payload.points) ? payload.points : []
      historyStart = Number(payload.windowStart || 0)
      historyEnd = Number(payload.windowEnd || 0)
      historyError = String(payload.error || "")
    } catch (exception) {
      historyAvailable = false
      historyPoints = []
      historyError = "Could not read battery history"
    }
  }

  function runAction(action) {
    if (busy || actionProc.running) return
    error = ""
    busy = true
    actionProc.command = [actionPath, action]
    actionProc.running = true
  }

  function applyDraft() {
    if (busy || actionProc.running) return
    if (draftEnd <= draftStart) { error = "End must be greater than start"; return }
    error = ""
    busy = true
    editing = false
    actionProc.command = [actionPath, "set", String(draftStart), String(draftEnd)]
    actionProc.running = true
  }

  function startEditing() {
    draftStart = Number(savedStart)
    draftEnd = Number(savedEnd)
    editing = true
  }

  function open() { refresh(); controller.show() }
  function close() { editing = false; controller.hide() }
  function toggle() { if (opened) close(); else open() }

  Process {
    id: statusProc
    command: [root.statusPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: actionProc
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.length > 0) root.error = text.trim()
    }
    onExited: function(exitCode, exitStatus) {
      root.busy = false
      if (exitCode !== 0 && root.error === "")
        root.error = "Action failed (exit " + exitCode + "). Is the sudoers rule installed?"
      root.refresh()
    }
  }

  Process {
    id: historyProc
    command: [root.historyPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyHistory(text)
    }
  }

  Timer {
    interval: root.refreshInterval
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(16)

        // ---------------------------------------------------------- header
        Row {
          width: parent.width
          spacing: Style.space(14)

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Style.font.display * 2.3)
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

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              text: root.statusTitle
              color: root.foregroundColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.statusDetail
              color: root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ------------------------------------------------- current level bar
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.supported

          Item {
            width: parent.width
            height: chargeNow.implicitHeight

            Text {
              id: chargeNow
              anchors.left: parent.left
              text: root.percentage !== "" ? root.percentage + "%" : "—"
              color: root.foregroundColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              anchors.baseline: chargeNow.baseline
              text: root.enabled ? "limit " + root.savedLabel : "limit off (" + root.savedLabel + ")"
              color: root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(8)
            radius: height / 2
            color: Util.alpha(root.foregroundColor, 0.12)

            Rectangle {
              readonly property real frac: Math.max(0, Math.min(1, (root.percentage !== "" ? Number(root.percentage) : 0) / 100))
              width: Math.max(height, parent.width * frac)
              height: parent.height
              radius: parent.radius
              color: root.statusColor

              Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 200 } }
            }

            // saved-limit tick on the level bar
            Rectangle {
              visible: root.enabled
              width: Math.max(2, Style.space(2))
              height: parent.height + Style.space(5)
              radius: width / 2
              color: root.limitedColor
              anchors.verticalCenter: parent.verticalCenter
              x: Math.max(0, Math.min(parent.width - width, parent.width * (Number(root.savedEnd) / 100) - width / 2))
            }
          }
        }

        // --------------------------------------------------- history chart
        Rectangle {
          id: historyCard
          width: parent.width
          height: Style.space(188)
          radius: Style.cornerRadius
          color: Util.alpha(root.foregroundColor, 0.045)
          border.width: Style.spacing.hairline
          border.color: Util.alpha(root.foregroundColor, 0.09)

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(14)
            spacing: Style.space(8)

            // title row + legend
            Item {
              width: parent.width
              height: Math.max(historyTitle.implicitHeight, legendRow.implicitHeight)

              Text {
                id: historyTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Battery · last 24h"
                color: root.foregroundColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Row {
                id: legendRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(12)

                Row {
                  spacing: Style.space(5)
                  anchors.verticalCenter: parent.verticalCenter
                  Rectangle {
                    width: Style.space(10); height: Style.space(3); radius: height / 2
                    color: root.limitedColor
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: "charging"
                    color: root.mutedColor
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  spacing: Style.space(5)
                  anchors.verticalCenter: parent.verticalCenter
                  Rectangle {
                    width: Style.space(10); height: Style.space(3); radius: height / 2
                    color: root.foregroundColor
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: "on battery"
                    color: root.mutedColor
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // plot area: Y labels on the left, canvas filling the rest
            Item {
              id: plotArea
              width: parent.width
              height: Style.space(104)

              readonly property real axisWidth: Style.space(26)

              // Y axis labels 100 / 50 / 0
              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: "100"
                color: root.mutedColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "50"
                color: root.mutedColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: "0"
                color: root.mutedColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              Canvas {
                id: levelCanvas
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.leftMargin: plotArea.axisWidth
                property var chartPoints: root.historyPoints
                property real chartStart: root.historyStart
                property real chartEnd: root.historyEnd
                property real limitFrac: root.enabled ? Number(root.savedEnd) / 100 : -1
                property color fg: root.foregroundColor
                property color charge: root.limitedColor

                onChartPointsChanged: requestPaint()
                onChartStartChanged: requestPaint()
                onChartEndChanged: requestPaint()
                onLimitFracChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.clearRect(0, 0, width, height)

                  // gridlines at 0 / 50 / 100
                  ctx.save()
                  ctx.strokeStyle = fg
                  ctx.globalAlpha = 0.1
                  ctx.lineWidth = 1
                  for (var g = 0; g <= 2; g++) {
                    var gy = Math.round(height * g / 2) + 0.5
                    ctx.beginPath()
                    ctx.moveTo(0, gy)
                    ctx.lineTo(width, gy)
                    ctx.stroke()
                  }
                  ctx.restore()

                  function yFor(level) {
                    return height - Math.max(0, Math.min(100, level)) / 100 * height
                  }

                  // saved-limit threshold line (dashed, green)
                  if (limitFrac >= 0) {
                    var ly = Math.round(yFor(limitFrac * 100)) + 0.5
                    ctx.save()
                    ctx.strokeStyle = charge
                    ctx.globalAlpha = 0.6
                    ctx.lineWidth = 1
                    if (ctx.setLineDash) ctx.setLineDash([4, 4])
                    ctx.beginPath()
                    ctx.moveTo(0, ly)
                    ctx.lineTo(width, ly)
                    ctx.stroke()
                    ctx.restore()
                  }

                  if (!chartPoints || chartPoints.length === 0 || chartEnd <= chartStart) return

                  var pts = []
                  for (var i = 0; i < chartPoints.length; i++) {
                    var p = chartPoints[i]
                    if (p.timestamp >= chartStart && p.timestamp <= chartEnd) pts.push(p)
                  }
                  if (pts.length === 0) return

                  function xFor(ts) {
                    return (ts - chartStart) / (chartEnd - chartStart) * width
                  }

                  // Draw the line as colored segments: green while charging,
                  // foreground on battery. Break the line across long gaps
                  // (machine off/suspended > 2h) so we don't draw fake data.
                  ctx.save()
                  ctx.lineWidth = 2
                  ctx.lineJoin = "round"
                  ctx.lineCap = "round"
                  ctx.globalAlpha = 0.95
                  for (var j = 1; j < pts.length; j++) {
                    var a = pts[j - 1]
                    var b = pts[j]
                    if (b.timestamp - a.timestamp > 7200) continue
                    var charging = (b.state === "charging" || b.state === "pending-charge")
                    ctx.strokeStyle = charging ? charge : fg
                    ctx.beginPath()
                    ctx.moveTo(xFor(a.timestamp), yFor(a.level))
                    ctx.lineTo(xFor(b.timestamp), yFor(b.level))
                    ctx.stroke()
                  }
                  ctx.restore()

                  // "now" dot at the latest sample
                  var lastPt = pts[pts.length - 1]
                  ctx.save()
                  ctx.fillStyle = (lastPt.state === "charging" || lastPt.state === "pending-charge") ? charge : fg
                  ctx.beginPath()
                  ctx.arc(xFor(lastPt.timestamp), yFor(lastPt.level), 2.5, 0, Math.PI * 2)
                  ctx.fill()
                  ctx.restore()
                }
              }
            }

            // time axis labels
            Item {
              width: parent.width
              height: historyNow.implicitHeight

              Text {
                anchors.left: parent.left
                anchors.leftMargin: plotArea.axisWidth
                text: "24h ago"
                color: root.mutedColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                id: historyNow
                anchors.right: parent.right
                text: "now"
                color: root.mutedColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: !root.historyAvailable || root.historyPoints.length === 0
              text: root.historyError !== "" ? root.historyError : "No battery history yet"
              color: root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: Util.alpha(root.foregroundColor, 0.14)
        }

        // ----------------------------------------------------- limit editor
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.editing

          Text {
            text: "SET LIMIT  ·  " + root.draftStart + "–" + root.draftEnd + "%"
            color: root.foregroundColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "Start charging below " + root.draftStart + "%"
              color: root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            PanelSlider {
              width: parent.width
              bar: root.bar
              integer: true
              minimum: 40
              maximum: 95
              step: 1
              value: root.draftStart
              onMoved: function(v) {
                root.draftStart = Math.round(v)
                if (root.draftEnd <= root.draftStart) root.draftEnd = Math.min(100, root.draftStart + 1)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "Stop charging at " + root.draftEnd + "%"
              color: root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            PanelSlider {
              width: parent.width
              bar: root.bar
              integer: true
              minimum: 50
              maximum: 100
              step: 1
              value: root.draftEnd
              onMoved: function(v) {
                root.draftEnd = Math.round(v)
                if (root.draftStart >= root.draftEnd) root.draftStart = Math.max(0, root.draftEnd - 1)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Cancel"
              foreground: root.foregroundColor
              bordered: true
              onClicked: root.editing = false
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              enabled: !root.busy && root.draftEnd > root.draftStart
              text: "Apply " + root.draftStart + "–" + root.draftEnd + "%"
              iconText: "󰁹"
              foreground: root.foregroundColor
              accent: root.limitedColor
              bordered: true
              onClicked: root.applyDraft()
            }
          }
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          text: root.error
          color: root.failureColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // -------------------------------------------------------- actions
        Row {
          width: parent.width
          spacing: Style.space(10)
          visible: !root.editing

          Button {
            width: (parent.width - parent.spacing) / 2
            enabled: root.supported && !root.busy
            text: root.busy
              ? "Working…"
              : root.mode === "full"
                ? "Re-apply limit"
                : "Charge to 100%"
            iconText: root.busy ? "󰑓" : (root.mode === "full" ? "󰂏" : "󰂄")
            iconSpinning: root.busy
            foreground: root.foregroundColor
            accent: root.mode === "full" ? root.limitedColor : root.fullColor
            bordered: true
            onClicked: root.runAction("toggle")
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            enabled: root.supported && !root.busy
            text: "Edit limit"
            iconText: "󰢻"
            foreground: root.foregroundColor
            bordered: true
            onClicked: root.startEditing()
          }
        }
      }
    }
  }
}
