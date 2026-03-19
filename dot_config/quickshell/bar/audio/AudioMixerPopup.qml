import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// Unified audio popup: master volume + sink switching + per-app mixing
// Replaces the separate sinkPopup and volPopup from shell.qml

PopupWindow {
    id: popup
    visible: false
    grabFocus: true

    // Must be set by parent (shell.qml)
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
    required property color accentGreen
    required property color accentLavender
    required property color accentRed
    required property color accentYellow
    required property string fontFamily
    required property int fontSize

    implicitWidth: popupContent.width
    implicitHeight: popupContent.height
    color: popup.bgColor

    // ─────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────
    property bool sinkExpanded: false

    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property real volumeRaw: defaultSink?.audio?.volume ?? 0
    readonly property int volumeLevel: Math.round(volumeRaw * 100)
    readonly property bool volumeMuted: defaultSink?.audio?.muted ?? false

    // Collect output sinks (non-stream sinks)
    readonly property var sinkNodes: {
        var sinks = [];
        var nodes = Pipewire.nodes.values;
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            if (n.isSink && !n.isStream)
                sinks.push(n);
        }
        return sinks;
    }

    // Collect audio output streams, deduplicated by app+media name
    // Note: playback streams have BOTH isStream=true AND isSink=true in Quickshell
    // Browsers often create multiple PW streams per tab — group them so the user
    // sees one entry and volume/mute controls all grouped streams together.
    readonly property var streamNodes: {
        var seen = {};
        var groups = [];
        var nodes = Pipewire.nodes.values;
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            if (!n.isStream) continue;
            var props = n.properties;
            var mc = props ? props["media.class"] : "";
            if (mc !== "Stream/Output/Audio") continue;
            var appName = (props ? props["application.name"] : "") || n.name;
            var mediaName = (props ? props["media.name"] : "") || "";
            var key = appName + "\0" + mediaName;
            if (seen[key] !== undefined) {
                // Add to existing group's siblings list
                groups[seen[key]].siblings.push(n);
            } else {
                seen[key] = groups.length;
                groups.push({ node: n, siblings: [n], appName: appName, mediaName: mediaName });
            }
        }
        return groups;
    }

    readonly property string currentSinkName: {
        if (!defaultSink) return "No output";
        return defaultSink.description || defaultSink.nickname || defaultSink.name;
    }

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

            // ══════════════════════════════════════════════
            // MASTER VOLUME SECTION
            // ══════════════════════════════════════════════
            Row {
                width: parent.width
                spacing: 8

                Text {
                    text: popup.volumeMuted ? "\uF026" :
                          (popup.volumeLevel > 66 ? "\uF028" :
                           popup.volumeLevel > 33 ? "\uF027" : "\uF027")
                    font.pixelSize: popup.fontSize + 2
                    font.family: popup.fontFamily
                    color: popup.volumeMuted ? popup.mutedColor : popup.accentGreen
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (popup.defaultSink)
                                popup.defaultSink.audio.muted = !popup.defaultSink.audio.muted
                        }
                    }
                }

                Text {
                    text: "Master Volume"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    font.bold: true
                    color: popup.fgColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: popup.volumeMuted ? "mute" : popup.volumeLevel + "%"
                    font.pixelSize: popup.fontSize
                    font.family: popup.fontFamily
                    color: popup.volumeMuted ? popup.mutedColor : popup.accentGreen
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Master volume slider
            Item {
                id: masterSlider
                width: parent.width
                height: 20

                readonly property real visualPos: Math.max(0, Math.min(1, popup.volumeRaw))

                function setVolFromX(mx) {
                    var val = Math.max(0, Math.min(1, mx / masterTrack.width))
                    if (popup.defaultSink)
                        popup.defaultSink.audio.volume = val
                }

                Rectangle {
                    id: masterTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 8
                    radius: 4
                    color: popup.mutedColor

                    Rectangle {
                        width: masterSlider.visualPos * parent.width
                        height: parent.height
                        radius: 4
                        color: popup.volumeMuted ? popup.mutedColor
                               : (popup.volumeRaw > 1.0 ? popup.accentRed : popup.accentGreen)
                    }
                }

                Rectangle {
                    x: masterSlider.visualPos * (masterTrack.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14
                    radius: 7
                    color: masterMouse.pressed ? popup.accentLavender : popup.fgColor

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }

                MouseArea {
                    id: masterMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true

                    onPressed: function(mouse) {
                        masterSlider.setVolFromX(mouse.x)
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            masterSlider.setVolFromX(mouse.x)
                    }
                }
            }

            // ── Divider ─────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: popup.mutedColor
            }

// ══════════════════════════════════════════════
            // SINK SWITCHER SECTION (collapsible)
            // ══════════════════════════════════════════════
            Rectangle {
                width: parent.width
                height: sinkHeaderRow.height + 8
                radius: 4
                color: sinkHeaderMouse.containsMouse
                       ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.06)
                       : "transparent"

                Row {
                    id: sinkHeaderRow
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 4; rightMargin: 4
                    }
                    spacing: 8

                    Text {
                        text: "Output:"
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        color: popup.mutedColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: popup.currentSinkName
                        font.pixelSize: popup.fontSize
                        font.family: popup.fontFamily
                        color: popup.fgColor
                        elide: Text.ElideRight
                        width: parent.width - 80
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: popup.sinkExpanded ? "\uF078" : "\uF054"
                        font.pixelSize: popup.fontSize - 2
                        font.family: popup.fontFamily
                        color: popup.mutedColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: sinkHeaderMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: popup.sinkExpanded = !popup.sinkExpanded
                }
            }

            // Expanded sink list
            Column {
                visible: popup.sinkExpanded
                width: parent.width
                spacing: 2

                Repeater {
                    model: popup.sinkNodes

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isDefault: Pipewire.defaultAudioSink !== null && Pipewire.defaultAudioSink.id === modelData.id
                        readonly property string displayName: modelData.description || modelData.nickname || modelData.name

                        width: parent.width
                        height: sinkItemLabel.implicitHeight + 10
                        radius: 4
                        color: isDefault
                               ? Qt.rgba(popup.accentGreen.r, popup.accentGreen.g, popup.accentGreen.b, 0.15)
                               : (sinkItemMouse.containsMouse
                                  ? Qt.rgba(popup.fgColor.r, popup.fgColor.g, popup.fgColor.b, 0.08)
                                  : "transparent")

                        Text {
                            id: sinkItemLabel
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8; rightMargin: 8
                            }
                            text: displayName
                            font.pixelSize: popup.fontSize
                            font.family: popup.fontFamily
                            font.bold: isDefault
                            color: isDefault ? popup.accentGreen : popup.fgColor
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: sinkItemMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                Pipewire.preferredDefaultAudioSink = modelData;
                                popup.sinkExpanded = false;
                            }
                        }
                    }
                }
            }

            // ── Divider (only if streams exist) ─────────
            Rectangle {
                visible: popup.streamNodes.length > 0
                width: parent.width; height: 1
                color: popup.mutedColor
            }

            // ══════════════════════════════════════════════
            // PER-APP STREAMS SECTION
            // ══════════════════════════════════════════════
            Text {
                visible: popup.streamNodes.length > 0
                text: "Applications"
                font.pixelSize: popup.fontSize
                font.family: popup.fontFamily
                font.bold: true
                color: popup.accentLavender
            }

            Flickable {
                visible: popup.streamNodes.length > 0
                width: parent.width
                height: Math.min(streamColumn.height, 300)
                contentHeight: streamColumn.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: streamColumn
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: popup.streamNodes

                        delegate: Column {
                            required property var modelData
                            // modelData = { node, siblings[], appName, mediaName }
                            readonly property var primaryNode: modelData.node
                            width: parent.width
                            spacing: 4

                            // Apply volume/mute to ALL siblings in the group
                            function setGroupVolume(val) {
                                var sibs = modelData.siblings;
                                for (var i = 0; i < sibs.length; i++)
                                    if (sibs[i].audio) sibs[i].audio.volume = val;
                            }
                            function toggleGroupMute() {
                                var newMuted = !(primaryNode.audio?.muted ?? false);
                                var sibs = modelData.siblings;
                                for (var i = 0; i < sibs.length; i++)
                                    if (sibs[i].audio) sibs[i].audio.muted = newMuted;
                            }

                            // App name + volume % + mute icon row
                            Row {
                                width: parent.width
                                spacing: 6

                                Text {
                                    text: modelData.appName
                                    font.pixelSize: popup.fontSize
                                    font.family: popup.fontFamily
                                    font.bold: true
                                    color: popup.fgColor
                                    elide: Text.ElideRight
                                    width: parent.width - appVolText.width - appMuteBtn.width - 20
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    id: appVolText
                                    text: Math.round((primaryNode.audio?.volume ?? 0) * 100) + "%"
                                    font.pixelSize: popup.fontSize
                                    font.family: popup.fontFamily
                                    color: (primaryNode.audio?.muted ?? false) ? popup.mutedColor : popup.fgColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    id: appMuteBtn
                                    text: {
                                        var muted = primaryNode.audio?.muted ?? false;
                                        if (muted) return "\uF026";
                                        var vol = Math.round((primaryNode.audio?.volume ?? 0) * 100);
                                        return vol > 66 ? "\uF028" : (vol > 33 ? "\uF027" : "\uF027");
                                    }
                                    font.pixelSize: popup.fontSize
                                    font.family: popup.fontFamily
                                    color: (primaryNode.audio?.muted ?? false) ? popup.mutedColor : popup.accentGreen
                                    anchors.verticalCenter: parent.verticalCenter

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: toggleGroupMute()
                                    }
                                }
                            }

                            // Subtitle (media.name)
                            Text {
                                visible: modelData.mediaName !== "" && modelData.mediaName !== modelData.appName
                                text: modelData.mediaName
                                font.pixelSize: popup.fontSize - 2
                                font.family: popup.fontFamily
                                color: popup.mutedColor
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            // Per-app volume slider
                            Item {
                                width: parent.width
                                height: 16

                                readonly property real appVol: primaryNode.audio?.volume ?? 0
                                readonly property real visualPos: Math.max(0, Math.min(1, appVol))

                                function setVolFromX(mx) {
                                    var val = Math.max(0, Math.min(1, mx / appTrack.width))
                                    setGroupVolume(val)
                                }

                                Rectangle {
                                    id: appTrack
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: popup.mutedColor

                                    Rectangle {
                                        width: parent.parent.visualPos * parent.width
                                        height: parent.height
                                        radius: 3
                                        color: (primaryNode.audio?.muted ?? false) ? popup.mutedColor
                                               : ((primaryNode.audio?.volume ?? 0) > 1.0 ? popup.accentRed : popup.accentGreen)
                                    }
                                }

                                Rectangle {
                                    x: parent.visualPos * (appTrack.width - width)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 10; height: 10
                                    radius: 5
                                    color: appSliderMouse.pressed ? popup.accentLavender : popup.fgColor

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }

                                MouseArea {
                                    id: appSliderMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    preventStealing: true

                                    onPressed: function(mouse) {
                                        parent.setVolFromX(mouse.x)
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (pressed)
                                            parent.setVolFromX(mouse.x)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
