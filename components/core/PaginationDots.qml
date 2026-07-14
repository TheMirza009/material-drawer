pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: paginationContainer
    
    property int pageCount: 0
    property int currentIndex: 0
    
    signal dotClicked(int index)

    property int activeDots: pageCount
    property real dotsTotalWidth: activeDots === 0 ? 0 : ((activeDots - 1) * 15) + 20
    property real startX: (width - dotsTotalWidth) / 2

    Repeater {
        // Pre-allocate a safe maximum of dots so they can scale down completely 
        // before being destroyed, allowing for perfect M3 exit animations.
        model: Math.max(25, paginationContainer.pageCount)

        delegate: Rectangle {
            required property int index

            readonly property bool isActive: paginationContainer.currentIndex === index
            readonly property bool isVisibleDot: index < paginationContainer.activeDots

            x: paginationContainer.startX + (index * 15) + (index > paginationContainer.currentIndex ? 12 : 0)
            y: (paginationContainer.height - height) / 2

            width:  isActive ? 20 : 8
            height: 8
            radius: Appearance.rounding.full
            
            color:  isActive
                ? Appearance.colors.colOnLayer0
                : Appearance.colors.colOnLayer1Inactive

            scale: isVisibleDot ? 1 : 0
            opacity: isVisibleDot ? 1 : 0

            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0] } }
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.0, 0.0, 1.0] } }
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: isVisibleDot ? Easing.OutCubic : Easing.InCubic } }
            Behavior on opacity { NumberAnimation { duration: 300 } }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: isVisibleDot
                onClicked: paginationContainer.dotClicked(index)
            }
        }
    }
}
