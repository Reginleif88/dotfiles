//@ pragma UseQApplication
// Quickshell status bar for Hyprland
// Entry point: ~/.config/quickshell/shell.qml
// Tested against Quickshell v0.2.1
//
// Features:
//   - Hyprland workspace switcher (clickable, left side)
//   - Clock with date (center)
//   - System tray with right-click menu (right side)
//   - Volume level via native PipeWire bindings (right side)
//   - Active window title (left side, after workspaces)
//
// Dependencies:
//   - quickshell
//   - hyprland (IPC via Quickshell.Hyprland)
//   - pipewire (native PipeWire bindings via Quickshell.Services.Pipewire)
//
// nerd font for icons

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import "sidebar"

ShellRoot {
    id: root

    // ---------------------
    // Theme / font settings
    // ---------------------
    readonly property color bgColor:        "#282828"   // Gruvbox Dark bg
    readonly property color fgColor:        "#ebdbb2"   // fg
    readonly property color mutedColor:     "#504945"   // bg2
    readonly property color accentBlue:     "#83a598"   // bright blue
    readonly property color accentLavender: "#d3869b"   // bright purple
    readonly property color accentGreen:    "#b8bb26"   // bright green
    readonly property color accentYellow:   "#fabd2f"   // bright yellow
    readonly property color accentRed:      "#fb4934"   // bright red
    readonly property color accentMauve:    "#d3869b"   // bright purple
    readonly property color accentTeal:     "#8ec07c"   // bright aqua
    readonly property color accentOrange:   "#fe8019"   // bright orange

    readonly property string fontFamily:    "FiraCode Nerd Font"
    readonly property int    fontSize:      13
    readonly property int    barHeight:     32
    readonly property int    barGap:        8    // top + bottom gap
    readonly property int    barSideMargin: 8    // left + right inset

    // ---------------------
    // Global state
    // ---------------------
    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property real volumeRaw: defaultSink?.audio?.volume ?? 0
    readonly property int volumeLevel: Math.round(volumeRaw * 100)
    readonly property bool volumeMuted: defaultSink?.audio?.muted ?? false
    property string activeWindowTitle: ""
    property string _windowBuf: ""
    property real cpuPercent: 0
    property real ramGb: 0
    property var _cpuPrev: null

    // ---------------------
    // Weather state
    // ---------------------
    property real weatherTemp: 0
    property real weatherFeelsLike: 0
    property int weatherCode: 0
    property bool weatherIsDay: true
    property string weatherLat: "48.7306"
    property string weatherLon: "2.2719"
    property string weatherLocation: "Massy"
    property bool weatherReady: false
    property string weatherError: ""
    property int weatherImgRevision: 0
    property string _geoBuf: ""
    property string _weatherBuf: ""

    function weatherIconForCode(code, isDay) {
        if (code === 0)
            return isDay ? { icon: "\uE302", label: "Clear sky" }
                         : { icon: "\uE32B", label: "Clear night" }
        if (code === 1 || code === 2)
            return isDay ? { icon: "\uE303", label: "Partly cloudy" }
                         : { icon: "\uE379", label: "Partly cloudy" }
        if (code === 3)
            return { icon: "\uE312", label: "Overcast" }
        if (code >= 45 && code <= 48)
            return { icon: "\uE311", label: "Fog" }
        if (code >= 51 && code <= 67)
            return { icon: "\uE318", label: "Rain" }
        if (code >= 71 && code <= 77)
            return { icon: "\uE31A", label: "Snow" }
        if (code >= 80 && code <= 82)
            return { icon: "\uE318", label: "Rain showers" }
        if (code >= 85 && code <= 86)
            return { icon: "\uE31A", label: "Snow showers" }
        if (code >= 95 && code <= 99)
            return { icon: "\uE334", label: "Thunderstorm" }
        return { icon: "\uE302", label: "Unknown" }
    }

    function shortDayName(isoDate) {
        var d = new Date(isoDate)
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()]
    }

    // ---------------------
    // Track all PipeWire nodes for full property access
    // ---------------------
    PwObjectTracker {
        objects: [root.defaultSink].concat(Pipewire.nodes.values)
    }

    // ---------------------
    // System clock (built-in, no process needed)
    // ---------------------
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // ---------------------
    // Screenshot via grimblast
    // ---------------------
    Process {
        id: screenshotProc
        // copysave: copies to clipboard AND saves to ~/Pictures/<timestamp>.png
        // bash wrapper: notify on success, silent on cancel (Escape key)
        command: ["bash", "-c",
            "FILE=$(grimblast copysave area) && " +
            "notify-send -i camera-photo -t 3000 'Screenshot' \"Saved & copied:\\n$(basename $FILE)\""
        ]
    }

    // ---------------------
    // Active window title via Hyprland IPC
    // ---------------------
    Process {
        id: windowProc
        command: ["hyprctl", "activewindow", "-j"]
        stdout: SplitParser {
            onRead: function(line) {
                root._windowBuf += line
            }
        }
        onExited: function() {
            try {
                var d = JSON.parse(root._windowBuf)
                root.activeWindowTitle = d.title || ""
            } catch(e) {
                root.activeWindowTitle = ""
            }
            root._windowBuf = ""
        }
    }

    // Refresh active window on every Hyprland event (instant)
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // activewindow, openwindow, closewindow, focusedmon all affect the title
            if (event.name === "activewindow" || event.name === "openwindow" ||
                event.name === "closewindow"  || event.name === "focusedmon") {
                windowProc.running = true
            }
        }
    }

    // Fallback poll for active window (catches edge cases)
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            windowProc.running = true
        }
    }

    // ---------------------
    // CPU usage (polls /proc/stat every 2 s)
    // ---------------------
    Process {
        id: cpuProc
        command: ["awk", "/^cpu /{printf \"%d %d\", $2+$3+$4+$5+$6+$7+$8, $5}", "/proc/stat"]
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.trim().split(" ")
                if (parts.length < 2) return
                var total = parseInt(parts[0])
                var idle  = parseInt(parts[1])
                if (root._cpuPrev !== null) {
                    var dt = total - root._cpuPrev.total
                    var di = idle  - root._cpuPrev.idle
                    root.cpuPercent = dt > 0 ? Math.round((dt - di) / dt * 100) : root.cpuPercent
                }
                root._cpuPrev = { total: total, idle: idle }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: cpuProc.running = true
    }

    // ---------------------
    // RAM usage (polls /proc/meminfo every 2 s)
    // ---------------------
    Process {
        id: ramProc
        command: ["awk", "/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{printf \"%.1f\", (t-a)/1024/1024}", "/proc/meminfo"]
        stdout: SplitParser {
            onRead: function(line) {
                var val = parseFloat(line.trim())
                if (!isNaN(val)) root.ramGb = val
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: ramProc.running = true
    }

    // ---------------------
    // Geolocation via ipinfo.io
    // ---------------------
    Process {
        id: geoProc
        command: ["curl", "-sf", "--max-time", "10", "https://ipinfo.io/json"]
        stdout: SplitParser {
            onRead: function(line) {
                root._geoBuf += line
            }
        }
        onExited: function() {
            try {
                var d = JSON.parse(root._geoBuf)
                var city = d.city || ""
                // If IP geolocation returns "Paris", keep Massy defaults
                // (IP geolocation lumps the whole metro area into Paris)
                if (city !== "" && city !== "Paris") {
                    var loc = (d.loc || "").split(",")
                    if (loc.length === 2) {
                        root.weatherLat = loc[0]
                        root.weatherLon = loc[1]
                        root.weatherLocation = city
                    }
                }
            } catch(e) {}
            root._geoBuf = ""
            weatherProc.running = true
            wttrProc.running = true
        }
    }

    Timer {
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: geoProc.running = true
    }

    // ---------------------
    // Weather fetch via Open-Meteo
    // ---------------------
    Process {
        id: weatherProc
        command: ["curl", "-sf", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.weatherLat +
            "&longitude=" + root.weatherLon +
            "&current=temperature_2m,apparent_temperature,is_day,weather_code&timezone=auto"]
        stdout: SplitParser {
            onRead: function(line) {
                root._weatherBuf += line
            }
        }
        onExited: function() {
            try {
                var d = JSON.parse(root._weatherBuf)
                var c = d.current
                root.weatherTemp = c.temperature_2m
                root.weatherFeelsLike = c.apparent_temperature
                root.weatherCode = c.weather_code
                root.weatherIsDay = c.is_day === 1
                root.weatherReady = true
                root.weatherError = ""
            } catch(e) {
                root.weatherError = "Weather data unavailable"
            }
            root._weatherBuf = ""
        }
    }

    Timer {
        interval: 900000
        running: root.weatherLat !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    // ---------------------
    // wttr.in PNG forecast image
    // ---------------------
    Process {
        id: wttrProc
        command: ["curl", "-sf", "--max-time", "20", "-o", "/tmp/qs-wttr.png",
            "https://wttr.in/" + root.weatherLocation + ".png?background=1e1e1e"]
        onExited: function() {
            root.weatherImgRevision++
        }
    }

    // ---------------------
    // One PanelWindow per screen via Variants
    // ---------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            // Hyprland monitor object for this bar's screen
            readonly property var hyprMonitor: Hyprland.monitors.values.find(
                function(m) { return m.name === bar.screen.name }) ?? null

            // Workspace IDs for this monitor: DP-1 gets 1,2 — HDMI-A-1 gets 3,4
            readonly property var monitorWsIds: bar.screen.name === "DP-1" ? [1, 2] : [3, 4]

            // Anchor to the top edge, spanning full width
            anchors {
                top:   true
                left:  true
                right: true
            }

            // Reserve space so windows don't overlap the bar
            exclusiveZone: root.barHeight + root.barGap * 2

            implicitHeight: root.barHeight + root.barGap * 2
            color: "transparent"   // background painted by inner Rectangle

            // -------------------------------------------------------
            // Root bar rectangle
            // -------------------------------------------------------
            Rectangle {
                anchors {
                    fill:         parent
                    topMargin:    root.barGap
                    bottomMargin: root.barGap
                    leftMargin:   root.barSideMargin
                    rightMargin:  root.barSideMargin
                }
                color:  root.bgColor
                radius: 10
                clip:   true

                // True-centered clock + weather (direct child, renders above layout)
                Row {
                    anchors.centerIn: parent
                    z: 1
                    spacing: 16

                    Text {
                        text: Qt.formatDateTime(clock.date, "ddd d MMM   HH:mm")
                        color: root.accentOrange
                        font.pixelSize: root.fontSize; font.family: root.fontFamily
                        font.bold: true
                    }

                    Text {
                        id: weatherBtn
                        visible: root.weatherReady
                        text: root.weatherIconForCode(root.weatherCode, root.weatherIsDay).icon +
                              " " + Math.round(root.weatherTemp) + "\u00B0(" +
                              Math.round(root.weatherFeelsLike) + ")"
                        color: root.accentTeal
                        font.pixelSize: root.fontSize; font.family: root.fontFamily
                        font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: weatherPopup.visible = !weatherPopup.visible
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ======================
                    // LEFT SECTION
                    // ======================
                    RowLayout {
                        spacing: 2
                        Layout.leftMargin: 8

                        // ---- Workspace switcher ----
                        Repeater {
                            model: bar.monitorWsIds

                            delegate: Item {
                                id: wsItem
                                required property int modelData

                                readonly property int  wsId:     modelData
                                readonly property var  wsObj:    Hyprland.workspaces.values.find(function(ws) { return ws.id === wsId }) ?? null
                                readonly property bool isFocused: bar.hyprMonitor !== null && bar.hyprMonitor.activeWorkspace !== null && bar.hyprMonitor.activeWorkspace.id === wsId
                                readonly property bool hasWindows: wsObj !== null

                                width:  24
                                height: root.barHeight

                                // Highlight pill behind the active workspace number
                                Rectangle {
                                    visible: wsItem.isFocused
                                    anchors.centerIn: parent
                                    width:  20
                                    height: 20
                                    radius: 4
                                    color:  Qt.rgba(
                                        root.accentBlue.r,
                                        root.accentBlue.g,
                                        root.accentBlue.b,
                                        0.2
                                    )
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: wsItem.wsId
                                    font.pixelSize: root.fontSize
                                    font.family:    root.fontFamily
                                    font.bold:      wsItem.isFocused
                                    color: wsItem.isFocused
                                           ? root.accentBlue
                                           : (wsItem.hasWindows ? root.fgColor : root.mutedColor)
                                }

                                // Dot indicator at the bottom for occupied (but unfocused) workspaces
                                Rectangle {
                                    visible: wsItem.hasWindows && !wsItem.isFocused
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    width:  4
                                    height: 4
                                    radius: 2
                                    color:  root.accentMauve
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("workspace " + wsItem.wsId)
                                }
                            }
                        }

                        // ---- Separator ----
                        Text {
                            Layout.leftMargin: 6; Layout.rightMargin: 6
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uE0B1"
                            font.pixelSize: root.fontSize; font.family: root.fontFamily
                            color: root.mutedColor
                        }

                        // ---- Active window title ----
                        Text {
                            text: "\uF2D0 " + (root.activeWindowTitle.length > 0
                                  ? root.activeWindowTitle
                                  : "Desktop")
                            color:           root.fgColor
                            font.pixelSize:  root.fontSize
                            font.family:     root.fontFamily
                            elide:           Text.ElideRight
                            maximumLineCount: 1
                            Layout.maximumWidth: 300
                            Layout.rightMargin:  8
                        }

                        // ---- Separator ----
                        Text {
                            Layout.leftMargin: 6; Layout.rightMargin: 6
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uE0B1"
                            font.pixelSize: root.fontSize; font.family: root.fontFamily
                            color: root.mutedColor
                        }

                        // ---- CPU usage ----
                        Text {
                            text: "\uF4BC " + root.cpuPercent + "%"
                            color: root.cpuPercent > 85 ? root.accentRed
                                 : root.cpuPercent > 60 ? root.accentYellow
                                 : root.accentTeal
                            font.pixelSize: root.fontSize
                            font.family:    root.fontFamily
                        }

                        // ---- Separator ----
                        Text {
                            Layout.leftMargin: 6; Layout.rightMargin: 6
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uE0B1"
                            font.pixelSize: root.fontSize; font.family: root.fontFamily
                            color: root.mutedColor
                        }

                        // ---- RAM usage ----
                        Text {
                            text: "\uF2DB " + root.ramGb.toFixed(1) + "G"
                            color: root.ramGb > 16 ? root.accentRed
                                 : root.ramGb > 8  ? root.accentYellow
                                 : root.accentBlue
                            font.pixelSize: root.fontSize
                            font.family:    root.fontFamily
                            Layout.rightMargin: 8
                        }
                    }

                    // ======================
                    // CENTER SECTION (spacer)
                    // ======================
                    Item { Layout.fillWidth: true }

                    // ======================
                    // RIGHT SECTION
                    // ======================
                    RowLayout {
                        spacing: 8
                        Layout.rightMargin: 8

                        // ---- Sound output ----
                        Text {
                            id: sinkSwitchBtn
                            text: "\uF025"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: sinkPopup.visible ? root.accentYellow : root.accentGreen
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sinkPopup.visible = !sinkPopup.visible
                            }
                        }

                        // ---- Separator ----
                        Text {
                            Layout.leftMargin: 2; Layout.rightMargin: 2
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uE0B1"
                            font.pixelSize: root.fontSize; font.family: root.fontFamily
                            color: root.mutedColor
                        }

                        // ---- Volume ----
                        Item {
                            id: volumeGroup
                            implicitWidth: volRow.width
                            implicitHeight: volRow.height

                            Row {
                                id: volRow
                                spacing: 4
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: speakerIcon
                                    text: root.volumeMuted ? "\uF026" :
                                          (root.volumeLevel > 66 ? "\uF028" :
                                           root.volumeLevel > 33 ? "\uF027" : "\uF027")
                                    font.pixelSize: root.fontSize
                                    font.family: root.fontFamily
                                    color: root.volumeMuted ? root.mutedColor : root.accentGreen
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                if (root.defaultSink)
                                                    root.defaultSink.audio.muted = !root.defaultSink.audio.muted
                                            } else
                                                volPopup.visible = !volPopup.visible
                                        }
                                    }
                                }

                                Text {
                                    text: root.volumeMuted ? "mute" : root.volumeLevel + "%"
                                    font.pixelSize: root.fontSize
                                    font.family:    root.fontFamily
                                    color: root.volumeMuted ? root.mutedColor : root.accentGreen
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton) {
                                                if (root.defaultSink)
                                                    root.defaultSink.audio.muted = !root.defaultSink.audio.muted
                                            } else
                                                volPopup.visible = !volPopup.visible
                                        }
                                    }
                                }
                            }

                            // Scroll-wheel volume control over the volume area
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: function(wheel) {
                                    if (!root.defaultSink) return
                                    var step = root.volumeRaw < 0.1 ? 0.01 : 0.02
                                    if (wheel.angleDelta.y > 0)
                                        root.defaultSink.audio.volume = Math.min(1.0, root.volumeRaw + step)
                                    else
                                        root.defaultSink.audio.volume = Math.max(0, root.volumeRaw - step)
                                }
                            }
                        }

                        // ---- Separator ----
                        Text {
                            Layout.leftMargin: 2; Layout.rightMargin: 2
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uE0B1"
                            font.pixelSize: root.fontSize; font.family: root.fontFamily
                            color: root.mutedColor
                        }

                        // ---- Screenshot ----
                        Text {
                            id: screenshotBtn
                            text: "\uF030"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            color: root.accentTeal
                            Layout.alignment: Qt.AlignVCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: screenshotProc.running = true
                            }
                        }

                        // ---- Separator ----
                        Text {
                            Layout.leftMargin: 6; Layout.rightMargin: 6
                            Layout.alignment: Qt.AlignVCenter
                            text: "\uE0B1"
                            font.pixelSize: root.fontSize; font.family: root.fontFamily
                            color: root.mutedColor
                        }

                        // ---- System tray ----
                        Row {
                            spacing: 0

                            Repeater {
                                model: SystemTray.items.values

                                delegate: Row {
                                    id: trayItem
                                    required property var modelData
                                    required property int index
                                    spacing: 0

                                    // Separator before every item except the first
                                    Text {
                                        visible: trayItem.index > 0
                                        text: "\uE0B1"
                                        font.pixelSize: root.fontSize
                                        font.family: root.fontFamily
                                        color: root.mutedColor
                                        anchors.verticalCenter: parent.verticalCenter
                                        leftPadding: 6; rightPadding: 6
                                    }

                                    Item {
                                        id: trayIcon
                                        width:  20
                                        height: 20

                                    // Icon image - prefer the icon provided by the item,
                                    // fall back to a named icon from the desktop theme.
                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: 16
                                        // modelData.icon is already a valid image source string
                                        source: trayItem.modelData.icon
                                        mipmap: true
                                    }

                                        // Context menu anchor (for right-click menus)
                                        QsMenuAnchor {
                                            id: trayMenu
                                            anchor.item: trayIcon
                                            menu: trayItem.modelData.menu
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (trayItem.modelData.hasMenu) {
                                                        trayMenu.open()
                                                    } else {
                                                        trayItem.modelData.activate()
                                                    }
                                                } else if (mouse.button === Qt.MiddleButton) {
                                                    trayItem.modelData.secondaryActivate()
                                                } else {
                                                    if (trayItem.modelData.onlyMenu && trayItem.modelData.hasMenu) {
                                                        trayMenu.open()
                                                    } else {
                                                        trayItem.modelData.activate()
                                                    }
                                                }
                                            }
                                            onWheel: function(wheel) {
                                                trayItem.modelData.scroll(wheel.angleDelta.y / 120, false)
                                            }
                                        }
                                    } // Item (trayIcon)
                                } // Row (trayItem delegate)
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------
            // Sink switcher popup
            // -------------------------------------------------------
            PopupWindow {
                id: sinkPopup
                visible: false
                grabFocus: true

                anchor.window: bar
                anchor.item: sinkSwitchBtn
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                anchor.adjustment: PopupAdjustment.Slide

                implicitWidth: sinkPopupContent.width
                implicitHeight: sinkPopupContent.height

                color: root.bgColor

                Rectangle {
                    id: sinkPopupContent
                    width: sinkColumn.width + 24
                    height: sinkColumn.height + 16
                    color: root.bgColor
                    border.color: root.mutedColor
                    border.width: 1
                    radius: 6

                    Column {
                        id: sinkColumn
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "Audio Output"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            font.bold: true
                            color: root.accentLavender
                            bottomPadding: 4
                        }

                        Repeater {
                            model: {
                                var sinks = [];
                                var nodes = Pipewire.nodes.values;
                                for (var i = 0; i < nodes.length; i++) {
                                    var n = nodes[i];
                                    if (n.isSink && !n.isStream) {
                                        sinks.push(n);
                                    }
                                }
                                return sinks;
                            }

                            delegate: Rectangle {
                                id: sinkDelegate
                                required property var modelData
                                readonly property bool isDefault: Pipewire.defaultAudioSink !== null && Pipewire.defaultAudioSink.id === modelData.id
                                readonly property string displayName: modelData.description || modelData.nickname || modelData.name

                                width: Math.max(sinkLabel.implicitWidth + 16, 220)
                                height: sinkLabel.implicitHeight + 10
                                radius: 4
                                color: isDefault
                                       ? Qt.rgba(root.accentGreen.r, root.accentGreen.g, root.accentGreen.b, 0.15)
                                       : (sinkMouse.containsMouse
                                          ? Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.08)
                                          : "transparent")

                                Text {
                                    id: sinkLabel
                                    anchors.centerIn: parent
                                    text: sinkDelegate.displayName
                                    font.pixelSize: root.fontSize
                                    font.family: root.fontFamily
                                    font.bold: sinkDelegate.isDefault
                                    color: sinkDelegate.isDefault ? root.accentGreen : root.fgColor
                                }

                                MouseArea {
                                    id: sinkMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: {
                                        Pipewire.preferredDefaultAudioSink = sinkDelegate.modelData;
                                        sinkPopup.visible = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------
            // Volume slider popup (right-click speaker icon)
            // -------------------------------------------------------
            PopupWindow {
                id: volPopup
                visible: false
                grabFocus: true

                anchor.window: bar
                anchor.item: speakerIcon
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                anchor.adjustment: PopupAdjustment.Slide

                implicitWidth: volPopupContent.width
                implicitHeight: volPopupContent.height

                color: root.bgColor

                Rectangle {
                    id: volPopupContent
                    width: 240
                    height: volPopupColumn.height + 20
                    color: root.bgColor
                    border.color: root.mutedColor
                    border.width: 1
                    radius: 6

                    Column {
                        id: volPopupColumn
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "\uF028  Volume: " + root.volumeLevel + "%"
                            font.pixelSize: root.fontSize
                            font.family: root.fontFamily
                            font.bold: true
                            color: root.accentLavender
                        }

                        Item {
                            id: volSlider
                            width: 212
                            height: 20

                            readonly property real sliderValue: root.volumeRaw
                            readonly property real visualPos: Math.max(0, Math.min(1, sliderValue))

                            function setVolFromX(mx) {
                                var val = Math.max(0, Math.min(1, mx / sliderTrack.width))
                                if (root.defaultSink)
                                    root.defaultSink.audio.volume = val
                            }

                            Rectangle {
                                id: sliderTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 8
                                radius: 4
                                color: root.mutedColor

                                Rectangle {
                                    width: volSlider.visualPos * parent.width
                                    height: parent.height
                                    radius: 4
                                    color: root.volumeMuted ? root.mutedColor
                                           : (volSlider.sliderValue > 1.0 ? root.accentRed : root.accentGreen)
                                }
                            }

                            Rectangle {
                                id: sliderHandle
                                x: volSlider.visualPos * (sliderTrack.width - width)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14
                                radius: 7
                                color: sliderMouse.pressed ? root.accentLavender : root.fgColor

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            MouseArea {
                                id: sliderMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                preventStealing: true

                                onPressed: function(mouse) {
                                    volSlider.setVolFromX(mouse.x)
                                }
                                onPositionChanged: function(mouse) {
                                    if (pressed)
                                        volSlider.setVolFromX(mouse.x)
                                }
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------
            // Weather forecast popup (wttr.in PNG)
            // -------------------------------------------------------
            PopupWindow {
                id: weatherPopup
                visible: false
                grabFocus: true

                anchor.window: bar
                anchor.item: weatherBtn
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                anchor.adjustment: PopupAdjustment.Slide

                implicitWidth: weatherPopupContent.width
                implicitHeight: weatherPopupContent.height

                color: root.bgColor

                Rectangle {
                    id: weatherPopupContent
                    width: weatherImg.status === Image.Ready
                           ? Math.max(weatherImg.implicitWidth + 24, 320)
                           : 320
                    height: weatherImg.status === Image.Ready
                            ? weatherImg.implicitHeight + 16
                            : 80
                    color: root.bgColor
                    border.color: root.mutedColor
                    border.width: 1
                    radius: 6

                    Image {
                        id: weatherImg
                        anchors.centerIn: parent
                        source: "file:///tmp/qs-wttr.png?" + root.weatherImgRevision
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: weatherImg.status === Image.Error || weatherImg.status === Image.Null
                        text: root.weatherError || "Forecast image unavailable"
                        color: root.fgColor
                        font.pixelSize: root.fontSize
                        font.family: root.fontFamily
                    }
                }
            }
        }
    }

    // ---------------------
    // Gemini sidebar (auto-hide, left edge of DP-1)
    // ---------------------
    GeminiSidebar {
        bgColor: root.bgColor
        borderColor: root.mutedColor
        targetScreen: "DP-1"
    }
}
