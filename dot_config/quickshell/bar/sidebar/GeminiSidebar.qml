import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

Item {
    id: sidebarRoot
    width: 0; height: 0

    required property color bgColor
    required property color borderColor
    required property string targetScreen
    property int panelWidth: 460
    property int triggerWidth: 4
    property url url: "https://gemini.google.com"

    property bool open: false
    property var geminiProfile: null

    WebEngineProfilePrototype {
        id: geminiProfileProto
        storageName: "gemini-sidebar"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }

    Component.onCompleted: {
        sidebarRoot.geminiProfile = geminiProfileProto.instance()
    }

    Timer {
        id: hideTimer
        interval: 300
        onTriggered: sidebarRoot.open = false
    }

    // Trigger zone: thin invisible strip on left edge
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: modelData.name === sidebarRoot.targetScreen

            anchors { top: true; bottom: true; left: true }
            exclusiveZone: 0
            implicitWidth: sidebarRoot.triggerWidth
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    hideTimer.stop()
                    sidebarRoot.open = true
                }
                onExited: hideTimer.restart()
            }
        }
    }

    // Sidebar panel with embedded web view
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: sidebarRoot.open && modelData.name === sidebarRoot.targetScreen

            anchors { top: true; bottom: true; left: true }
            exclusiveZone: 0
            implicitWidth: sidebarRoot.panelWidth
            color: sidebarRoot.bgColor
            focusable: true

            Rectangle {
                anchors.fill: parent
                color: sidebarRoot.bgColor

                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: sidebarRoot.borderColor
                }

                Loader {
                    anchors.fill: parent
                    anchors.rightMargin: 1
                    active: sidebarRoot.geminiProfile !== null

                    sourceComponent: WebEngineView {
                        url: sidebarRoot.url
                        backgroundColor: sidebarRoot.bgColor
                        profile: sidebarRoot.geminiProfile
                    }
                }
            }

            // Hover tracker on top of WebEngineView so its subsurface
            // doesn't steal onExited from us.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onExited: hideTimer.restart()
                onEntered: hideTimer.stop()
            }
        }
    }
}
