import QtQuick
import QtQuick.Layouts

Rectangle {
    id: pill
    default property alias content: innerLayout.data
    property alias innerSpacing: innerLayout.spacing
    color: root.pillColor
    radius: root.pillRadius
    implicitWidth: innerLayout.implicitWidth + root.pillHPad * 2
    implicitHeight: innerLayout.implicitHeight + root.pillVPad * 2
    Layout.alignment: Qt.AlignVCenter

    RowLayout {
        id: innerLayout
        anchors.centerIn: parent
        spacing: 6
    }
}
