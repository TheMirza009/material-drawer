pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: chipsContainer
    
    property var categoryDefs: []
    property int selectedCategory: 0
    property bool showIcons: true
    
    signal categorySelected(int index)
    
    width: chipsRow.implicitWidth + 8
    height: chipsRow.implicitHeight + 8
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer1

    ButtonGroup {
        id: chipsRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: chipsContainer.categoryDefs

            delegate: SelectionGroupButton {
                id: chip
                required property var modelData
                required property int index

                leftmost: index === 0
                rightmost: index === chipsContainer.categoryDefs.length - 1
                toggled: chipsContainer.selectedCategory === index
                
                buttonText: chip.modelData.label
                buttonIcon: chipsContainer.showIcons ? chip.modelData.icon : ""
                
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colBackgroundActive: Appearance.colors.colLayer3Active

                onClicked: chipsContainer.categorySelected(chip.index)
            }
        }
    }
}
