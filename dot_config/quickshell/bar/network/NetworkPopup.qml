import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Network management popup with WiFi + Bluetooth tabs
// Clean list-based UI matching existing bar popup style (sinkPopup, volPopup)

PopupWindow {
    id: popup
    visible: false
    grabFocus: true

    // These must be set by the parent (shell.qml)
    required property var anchorWindow
    required property var anchorItem

    anchor.window: anchorWindow
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    // Theme colors (passed from root)
    required property color bgColor
    required property color fgColor
    required property color mutedColor
    required property color accentBlue
    required property color accentLavender
    required property color accentGreen
    required property color accentYellow
    required property color accentRed
    required property color accentTeal
    required property string fontFamily
    required property int fontSize

    // Expose state to parent for bar icon coloring
    property string btPower: "off"
    property string btConnName: ""
    property string wifiPower: "off"
    property string wifiSsid: ""

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    // ─────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────
    property string activeTab: "bt"      // "bt" or "wifi"
    readonly property color activeAccent: activeTab === "wifi" ? popup.accentBlue : popup.accentLavender

    // Bluetooth state
    property var btConnected: []
    property var btDevices: []
    property string _btBuf: ""

    // WiFi state
    property var wifiConnected: null
    property var wifiNetworks: []
    property string _wifiBuf: ""

    // Optimistic power toggle state
    property bool btPowerPending: false
    property string expectedBtPower: ""
    property bool wifiPowerPending: false
    property string expectedWifiPower: ""

    // Per-device busy tracking (MAC/SSID → true)
    property var busyTasks: ({})

    readonly property string scriptsDir:
        Qt.resolvedUrl("../scripts/").toString().replace("file://", "")

    // ─────────────────────────────────────────────────────
    // BT status polling
    // ─────────────────────────────────────────────────────
    Process {
        id: btStatusProc
        command: ["bash", popup.scriptsDir + "bluetooth_panel.sh", "--status"]
        stdout: SplitParser {
            onRead: function(line) { popup._btBuf += line }
        }
        onExited: function() {
            try {
                var d = JSON.parse(popup._btBuf)
                if (!popup.btPowerPending) {
                    popup.btPower = d.power || "off"
                }
                popup.btConnected = d.connected || []
                popup.btDevices = d.devices || []
                popup.btConnName = popup.btConnected.length > 0
                    ? popup.btConnected[0].name : ""
            } catch(e) {}
            popup._btBuf = ""
        }
    }

    // ─────────────────────────────────────────────────────
    // WiFi status polling
    // ─────────────────────────────────────────────────────
    Process {
        id: wifiStatusProc
        command: ["bash", popup.scriptsDir + "wifi_panel.sh", "--status"]
        stdout: SplitParser {
            onRead: function(line) { popup._wifiBuf += line }
        }
        onExited: function() {
            try {
                var d = JSON.parse(popup._wifiBuf)
                if (!popup.wifiPowerPending) {
                    popup.wifiPower = d.power || "off"
                }
                popup.wifiConnected = d.connected || null
                popup.wifiNetworks = d.networks || []
                popup.wifiSsid = popup.wifiConnected
                    ? popup.wifiConnected.ssid : ""
            } catch(e) {}
            popup._wifiBuf = ""
        }
    }

    // Poll every 3 seconds when visible
    Timer {
        id: pollTimer
        interval: 3000
        running: popup.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            btStatusProc.running = true
            wifiStatusProc.running = true
        }
    }

    // ─────────────────────────────────────────────────────
    // Action processes (fire-and-forget, re-poll on exit)
    // ─────────────────────────────────────────────────────
    Process {
        id: btToggleProc
        command: ["bash", popup.scriptsDir + "bluetooth_panel.sh", "--toggle"]
        onExited: function() { btStatusProc.running = true }
    }

    Process {
        id: wifiToggleProc
        command: ["bash", popup.scriptsDir + "wifi_panel.sh", "--toggle"]
        onExited: function() { wifiStatusProc.running = true }
    }

    // BT connect/disconnect — command set dynamically
    Process {
        id: btActionProc
        property string targetMac: ""
        command: ["bash", popup.scriptsDir + "bluetooth_panel.sh", "--connect", targetMac]
        onExited: function() {
            var newBusy = Object.assign({}, popup.busyTasks)
            delete newBusy[targetMac]
            popup.busyTasks = newBusy
            btStatusProc.running = true
        }
    }

    Process {
        id: btDisconnectProc
        property string targetMac: ""
        command: ["bash", popup.scriptsDir + "bluetooth_panel.sh", "--disconnect", targetMac]
        onExited: function() {
            var newBusy = Object.assign({}, popup.busyTasks)
            delete newBusy[targetMac]
            popup.busyTasks = newBusy
            btStatusProc.running = true
        }
    }

    Process {
        id: wifiConnectProc
        property string targetSsid: ""
        command: ["bash", popup.scriptsDir + "wifi_panel.sh", "--connect", targetSsid]
        onExited: function() {
            var newBusy = Object.assign({}, popup.busyTasks)
            delete newBusy[targetSsid]
            popup.busyTasks = newBusy
            wifiStatusProc.running = true
        }
    }

    Process {
        id: wifiDisconnectProc
        command: ["bash", popup.scriptsDir + "wifi_panel.sh", "--disconnect"]
        onExited: function() { wifiStatusProc.running = true }
    }

    // Power toggle timeout resets
    Timer {
        id: btPendingReset
        interval: 8000
        onTriggered: { popup.btPowerPending = false; popup.expectedBtPower = "" }
    }
    Timer {
        id: wifiPendingReset
        interval: 8000
        onTriggered: { popup.wifiPowerPending = false; popup.expectedWifiPower = "" }
    }

    // Busy timeout (safety valve — 15s)
    Timer {
        id: busyTimeout
        interval: 15000
        running: Object.keys(popup.busyTasks).length > 0
        onTriggered: { popup.busyTasks = ({}) }
    }

    // ─────────────────────────────────────────────────────
    // Helper: current power state (respects optimistic UI)
    // ─────────────────────────────────────────────────────
    readonly property string displayBtPower:
        btPowerPending ? expectedBtPower : btPower
    readonly property string displayWifiPower:
        wifiPowerPending ? expectedWifiPower : wifiPower
    readonly property bool currentPowerOn:
        activeTab === "bt" ? displayBtPower === "on" : displayWifiPower === "on"

    // ─────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────
    Rectangle {
        id: popupContent
        width: 300
        height: mainColumn.height + 24
        color: popup.bgColor
        border.color: popup.mutedColor
        border.width: 1
        radius: 6

        Column {
            id: mainColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            // ── Tab buttons ──────────────────────────────
            Row {
                spacing: 4
                width: parent.width

                Rectangle {
                    width: (parent.width - 4) / 2
                    height: 28
                    radius: 4
                    color: popup.activeTab === "wifi"
                           ? Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.2)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰤨  WiFi"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        font.bold: popup.activeTab === "wifi"
                        color: popup.activeTab === "wifi" ? popup.accentBlue : popup.fgColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activeTab = "wifi"
                    }
                }

                Rectangle {
                    width: (parent.width - 4) / 2
                    height: 28
                    radius: 4
                    color: popup.activeTab === "bt"
                           ? Qt.rgba(popup.accentLavender.r, popup.accentLavender.g, popup.accentLavender.b, 0.2)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\uF294  Bluetooth"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        font.bold: popup.activeTab === "bt"
                        color: popup.activeTab === "bt" ? popup.accentLavender : popup.fgColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activeTab = "bt"
                    }
                }
            }

            // ── Divider ─────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ── Power toggle ────────────────────────────
            Row {
                width: parent.width
                spacing: 8

                Text {
                    text: "\u23FB  Power"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.fgColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { width: 1; height: 1; Layout.fillWidth: true }

                Rectangle {
                    width: 44; height: 22
                    radius: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: popup.currentPowerOn
                           ? Qt.rgba(popup.activeAccent.r, popup.activeAccent.g, popup.activeAccent.b, 0.3)
                           : popup.mutedColor

                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        y: 3
                        x: popup.currentPowerOn ? 25 : 3
                        color: popup.currentPowerOn ? popup.activeAccent : popup.fgColor

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (popup.activeTab === "bt") {
                                popup.btPowerPending = true
                                popup.expectedBtPower = popup.btPower === "on" ? "off" : "on"
                                btPendingReset.restart()
                                btToggleProc.running = true
                            } else {
                                popup.wifiPowerPending = true
                                popup.expectedWifiPower = popup.wifiPower === "on" ? "off" : "on"
                                wifiPendingReset.restart()
                                wifiToggleProc.running = true
                            }
                        }
                    }
                }

                Text {
                    text: popup.currentPowerOn ? "on" : "off"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    color: popup.currentPowerOn ? popup.activeAccent : popup.mutedColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── Divider ─────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
                visible: popup.currentPowerOn
            }

            // ═══════════════════════════════════════════════
            // BLUETOOTH TAB CONTENT
            // ═══════════════════════════════════════════════
            Column {
                visible: popup.activeTab === "bt" && popup.currentPowerOn
                width: parent.width
                spacing: 6

                // ── Connected devices ────────────────────
                Text {
                    visible: popup.btConnected.length > 0
                    text: "CONNECTED"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                }

                Repeater {
                    model: popup.btConnected

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: btConnCol.height + 12
                        radius: 4
                        color: Qt.rgba(popup.accentLavender.r, popup.accentLavender.g, popup.accentLavender.b, 0.1)

                        Column {
                            id: btConnCol
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: 8
                            }
                            spacing: 2

                            Text {
                                text: modelData.icon + "  " + modelData.name
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentLavender
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                visible: modelData.battery !== "" || modelData.profile !== ""
                                text: {
                                    var parts = []
                                    if (modelData.battery !== "")
                                        parts.push(modelData.battery + "%")
                                    if (modelData.profile !== "")
                                        parts.push(modelData.profile)
                                    return "   " + parts.join(" \u2022 ")
                                }
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.fgColor
                            }

                            Text {
                                text: {
                                    var mac = modelData.mac
                                    if (popup.busyTasks[mac])
                                        return "   Disconnecting\u2026"
                                    return "   Hold to disconnect"
                                }
                                font.pixelSize: popup.fontSize - 3
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                font.italic: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressAndHold: {
                                var mac = modelData.mac
                                if (popup.busyTasks[mac]) return
                                var newBusy = Object.assign({}, popup.busyTasks)
                                newBusy[mac] = true
                                popup.busyTasks = newBusy
                                btDisconnectProc.targetMac = mac
                                btDisconnectProc.running = true
                            }
                        }
                    }
                }

                // ── Available devices ────────────────────
                Text {
                    visible: popup.btDevices.length > 0
                    text: "AVAILABLE DEVICES"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    topPadding: 4
                }

                Repeater {
                    model: popup.btDevices

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 32
                        radius: 4
                        color: btDevMouse.containsMouse
                               ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                               : "transparent"

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8; rightMargin: 8
                            }
                            spacing: 8

                            Text {
                                text: modelData.icon + "  " + modelData.name
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                color: popup.fgColor
                                elide: Text.ElideRight
                                width: parent.width - actionBtn.width - 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: actionBtn
                                text: {
                                    var mac = modelData.mac
                                    if (popup.busyTasks[mac]) return "\u2026"
                                    return modelData.action
                                }
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentLavender
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: btDevMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                var mac = modelData.mac
                                if (popup.busyTasks[mac]) return
                                var newBusy = Object.assign({}, popup.busyTasks)
                                newBusy[mac] = true
                                popup.busyTasks = newBusy
                                btActionProc.targetMac = mac
                                btActionProc.running = true
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    visible: popup.btConnected.length === 0 && popup.btDevices.length === 0
                    text: "No devices found"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    font.italic: true
                }
            }

            // ═══════════════════════════════════════════════
            // WIFI TAB CONTENT
            // ═══════════════════════════════════════════════
            Column {
                visible: popup.activeTab === "wifi" && popup.currentPowerOn
                width: parent.width
                spacing: 6

                // ── Connected network ────────────────────
                Text {
                    visible: popup.wifiConnected !== null
                    text: "CONNECTED"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                }

                Rectangle {
                    visible: popup.wifiConnected !== null
                    width: parent.width
                    height: wifiConnCol.height + 12
                    radius: 4
                    color: Qt.rgba(popup.accentBlue.r, popup.accentBlue.g, popup.accentBlue.b, 0.1)

                    Column {
                        id: wifiConnCol
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 8
                        }
                        spacing: 2

                        Text {
                            text: (popup.wifiConnected ? popup.wifiConnected.icon : "") + "  " +
                                  (popup.wifiConnected ? popup.wifiConnected.ssid : "")
                            font.pixelSize: popup.fontSize
                            font.family: popup.fontFamily
                            font.bold: true
                            color: popup.accentBlue
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: {
                                if (!popup.wifiConnected) return ""
                                var parts = []
                                if (popup.wifiConnected.signal)
                                    parts.push(popup.wifiConnected.signal + "%")
                                if (popup.wifiConnected.security)
                                    parts.push(popup.wifiConnected.security)
                                return "   " + parts.join(" \u2022 ")
                            }
                            font.pixelSize: popup.fontSize - 2
                            font.family: popup.fontFamily
                            color: popup.fgColor
                        }

                        Text {
                            visible: popup.wifiConnected !== null &&
                                     ((popup.wifiConnected ? popup.wifiConnected.ip : "") !== "" ||
                                      (popup.wifiConnected ? popup.wifiConnected.freq : "") !== "")
                            text: {
                                if (!popup.wifiConnected) return ""
                                var parts = []
                                if (popup.wifiConnected.ip)
                                    parts.push(popup.wifiConnected.ip)
                                if (popup.wifiConnected.freq)
                                    parts.push(popup.wifiConnected.freq)
                                return "   " + parts.join(" \u2022 ")
                            }
                            font.pixelSize: popup.fontSize - 3
                            font.family: popup.fontFamily
                            color: popup.mutedColor
                        }

                        Text {
                            text: "   Hold to disconnect"
                            font.pixelSize: popup.fontSize - 3
                            font.family: popup.fontFamily
                            color: popup.mutedColor
                            font.italic: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressAndHold: {
                            wifiDisconnectProc.running = true
                        }
                    }
                }

                // ── Available networks ───────────────────
                Text {
                    visible: popup.wifiNetworks.length > 0
                    text: "AVAILABLE NETWORKS"
                    font.pixelSize: popup.fontSize - 2
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.mutedColor
                    topPadding: 4
                }

                Repeater {
                    model: popup.wifiNetworks

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 32
                        radius: 4
                        color: wifiDevMouse.containsMouse
                               ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                               : "transparent"

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8; rightMargin: 8
                            }
                            spacing: 8

                            Text {
                                text: modelData.icon + "  " + modelData.ssid
                                font.pixelSize: popup.fontSize
                                font.family: popup.fontFamily
                                color: popup.fgColor
                                elide: Text.ElideRight
                                width: parent.width - wifiActionBtn.width - wifiSigText.width - 24
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: wifiSigText
                                text: modelData.signal + "%"
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: wifiActionBtn
                                text: {
                                    var ssid = modelData.ssid
                                    if (popup.busyTasks[ssid]) return "\u2026"
                                    return "Connect"
                                }
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                font.bold: true
                                color: popup.accentBlue
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: wifiDevMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                var ssid = modelData.ssid
                                if (popup.busyTasks[ssid]) return
                                var newBusy = Object.assign({}, popup.busyTasks)
                                newBusy[ssid] = true
                                popup.busyTasks = newBusy
                                wifiConnectProc.targetSsid = ssid
                                wifiConnectProc.running = true
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    visible: popup.wifiConnected === null && popup.wifiNetworks.length === 0
                    text: "No networks found"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.mutedColor
                    font.italic: true
                }
            }

            // ── Power off message ────────────────────────
            Text {
                visible: !popup.currentPowerOn
                text: popup.activeTab === "bt" ? "Bluetooth is off" : "WiFi is off"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                color: popup.mutedColor
                font.italic: true
                topPadding: 4
            }
        }
    }
}
