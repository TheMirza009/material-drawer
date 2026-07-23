pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // ── Control Panel ──────────────────────────────────────────────────────────
    readonly property int fadeDurationMs: 350
    readonly property real goldenRatio: 1.6180339887

    readonly property var emptyStrings: [
        "<b>No results</b> found",
        "We looked <b>everywhere</b>...",
        "<b>Nothing</b> to see here",
        "<b>No apps</b> match your search",
        "It's <b>quiet</b> in here...",
        "<b>Zero</b> results returned",
        "Could not find <b>anything</b>",
        "<b>Empty</b> space...",
        "Try a <b>different</b> search",
        "<b>No matches</b> found"
    ]

    // ── State ──────────────────────────────────────────────────────────────────
    property var gearModel: []
    property string currentText: ""
    property real clusterMinX: 0
    property real clusterMinY: 0
    property real clusterWidth: 100
    property real clusterHeight: 100

    // ── Math & Geometry Helpers ────────────────────────────────────────────────
    function pt(cx, cy, r, a, s) {
        return [(cx + r * Math.cos(a)) * s, (cy + r * Math.sin(a)) * s];
    }

    function regularPts(n, opts, s) {
        opts = opts || {};
        const rot = opts.rot !== undefined ? opts.rot : -Math.PI / 2;
        const r = opts.r !== undefined ? opts.r : 0.46;
        const cx = opts.cx !== undefined ? opts.cx : 0.5;
        const cy = opts.cy !== undefined ? opts.cy : 0.5;
        const out = [];
        for (let i = 0; i < n; i++) out.push(pt(cx, cy, r, rot + i * (Math.PI * 2) / n, s));
        return out;
    }

    function roundedPolygonPath(points, cornerFrac, radiiOverride) {
        cornerFrac = cornerFrac !== undefined ? cornerFrac : 0.25;
        const n = points.length;
        const radii = radiiOverride || points.map(function (p, i) {
            const prev = points[(i - 1 + n) % n], next = points[(i + 1) % n];
            const e1 = Math.hypot(p[0] - prev[0], p[1] - prev[1]);
            const e2 = Math.hypot(p[0] - next[0], p[1] - next[1]);
            return Math.min(e1, e2) * cornerFrac;
        });
        const d = [];
        for (let i = 0; i < n; i++) {
            const prev = points[(i - 1 + n) % n], curr = points[i], next = points[(i + 1) % n];
            const r = radii[i];
            const d1 = Math.hypot(curr[0] - prev[0], curr[1] - prev[1]);
            const d2 = Math.hypot(next[0] - curr[0], next[1] - curr[1]);
            const p1 = [curr[0] + (prev[0] - curr[0]) * (r / d1), curr[1] + (prev[1] - curr[1]) * (r / d1)];
            const p2 = [curr[0] + (next[0] - curr[0]) * (r / d2), curr[1] + (next[1] - curr[1]) * (r / d2)];
            d.push((i === 0 ? 'M ' : 'L ') + p1[0].toFixed(4) + ' ' + p1[1].toFixed(4));
            d.push('Q ' + curr[0].toFixed(4) + ' ' + curr[1].toFixed(4) + ' ' + p2[0].toFixed(4) + ' ' + p2[1].toFixed(4));
        }
        d.push('Z');
        return d.join(' ');
    }

    function blobPath(n, ampFn, opts, s) {
        opts = opts || {};
        const cx = opts.cx !== undefined ? opts.cx : 0.5;
        const cy = opts.cy !== undefined ? opts.cy : 0.5;
        const r = opts.r !== undefined ? opts.r : 0.42;
        const rot = opts.rot !== undefined ? opts.rot : -Math.PI / 2;
        const pts = [];
        for (let i = 0; i < n; i++) {
            const theta = rot + i * (Math.PI * 2) / n;
            pts.push(pt(cx, cy, r * ampFn(theta, i), theta, s));
        }
        const N = pts.length;
        const d = ['M ' + pts[0][0].toFixed(4) + ' ' + pts[0][1].toFixed(4)];
        for (let i = 0; i < N; i++) {
            const p0 = pts[(i - 1 + N) % N], p1 = pts[i], p2 = pts[(i + 1) % N], p3 = pts[(i + 2) % N];
            const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
            const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
            d.push('C ' + c1[0].toFixed(4) + ' ' + c1[1].toFixed(4) + ' ' + c2[0].toFixed(4) + ' ' + c2[1].toFixed(4) + ' ' + p2[0].toFixed(4) + ' ' + p2[1].toFixed(4));
        }
        d.push('Z');
        return d.join(' ');
    }

    // ── Shapes ─────────────────────────────────────────────────────────────────
    property var shapeNames: [
        "circle", "pill", /* "semicircle", "arch", */ "triangle", "square", "pentagon", 
        "diamond", "gem", "clamshell", "fan", "cookie6", "cookie9", "sunny", 
        "burst", "clover4", "flower", "puffy", "heart"
    ]

    function generateShape(name, s) {
        switch(name) {
            case "circle": return roundedPolygonPath(regularPts(28, { r: 0.47 }, s), 0.5);
            case "pill": return roundedPolygonPath([[0.10*s, 0.32*s], [0.90*s, 0.32*s], [0.90*s, 0.68*s], [0.10*s, 0.68*s]], 0.5);
            case "semicircle": return 'M ' + (0.04*s) + ' ' + (0.54*s) + ' A ' + (0.46*s) + ' ' + (0.46*s) + ' 0 0 1 ' + (0.96*s) + ' ' + (0.54*s) + ' Z';
            case "arch": return 'M ' + (0.08*s) + ' ' + (0.95*s) + ' L ' + (0.08*s) + ' ' + (0.5*s) + ' A ' + (0.42*s) + ' ' + (0.42*s) + ' 0 0 1 ' + (0.92*s) + ' ' + (0.5*s) + ' L ' + (0.92*s) + ' ' + (0.95*s) + ' Z';
            case "triangle": return roundedPolygonPath(regularPts(3, { r: 0.5 }, s), 0.22);
            case "square": return roundedPolygonPath(regularPts(4, { r: 0.42, rot: -Math.PI / 4 }, s), 0.24);
            case "pentagon": return roundedPolygonPath(regularPts(5, { r: 0.46 }, s), 0.18);
            case "diamond": return roundedPolygonPath(regularPts(4, { r: 0.5 }, s), 0.12);
            case "gem": return roundedPolygonPath(regularPts(6, { r: 0.44 }, s), 0.14);
            case "clamshell": return roundedPolygonPath([[0.5*s, 0.05*s], [0.92*s, 0.62*s], [0.5*s, 0.95*s], [0.08*s, 0.62*s]], 0, [0.34*s, 0.06*s, 0.34*s, 0.06*s]);
            case "fan": return roundedPolygonPath([[0.5*s, 0.04*s], [0.94*s, 0.92*s], [0.06*s, 0.92*s]], 0, [0.36*s, 0.1*s, 0.1*s]);
            case "cookie6": return blobPath(48, function (t) { return 1 + 0.14 * Math.cos(6 * t); }, {}, s);
            case "cookie9": return blobPath(60, function (t) { return 1 + 0.13 * Math.cos(9 * t); }, {}, s);
            case "sunny": return blobPath(64, function (t) { return 1 + 0.24 * Math.cos(10 * t); }, { r: 0.4 }, s);
            case "burst": return blobPath(72, function (t) { return 1 + 0.32 * Math.cos(13 * t); }, { r: 0.37 }, s);
            case "clover4": return blobPath(80, function (t) { return 0.60 + 0.5 * Math.max(0, Math.cos(4 * t)); }, {}, s);
            case "flower": return blobPath(96, function (t) { return 0.66 + 0.42 * Math.max(0, Math.cos(8 * t)); }, {}, s);
            case "puffy": return blobPath(48, function (t) { return 1 + 0.11 * Math.cos(3 * t + 0.4) + 0.06 * Math.cos(5 * t + 1.1); }, {}, s);
            case "heart": return 'M'+(0.5*s)+','+(0.9*s)+' C'+(0.2*s)+','+(0.66*s)+' '+(0.04*s)+','+(0.42*s)+' '+(0.04*s)+','+(0.25*s)+' C'+(0.04*s)+','+(0.09*s)+' '+(0.17*s)+','+(-0.01*s)+' '+(0.32*s)+','+(0.02*s)+' C'+(0.42*s)+','+(0.05*s)+' '+(0.48*s)+','+(0.12*s)+' '+(0.5*s)+','+(0.19*s)+' C'+(0.52*s)+','+(0.12*s)+' '+(0.58*s)+','+(0.05*s)+' '+(0.68*s)+','+(0.02*s)+' C'+(0.83*s)+','+(-0.01*s)+' '+(0.96*s)+','+(0.09*s)+' '+(0.96*s)+','+(0.25*s)+' C'+(0.96*s)+','+(0.42*s)+' '+(0.8*s)+','+(0.66*s)+' '+(0.5*s)+','+(0.9*s)+' Z';
        }
        return "";
    }

    // ── Randomization ──────────────────────────────────────────────────────────
    function buildGears() {
        if (!root.visible || root.width === 0 || root.height === 0) return;

        // Randomize text
        root.currentText = root.emptyStrings[Math.floor(Math.random() * root.emptyStrings.length)];

        // Generate geometry
        const count = 3 + Math.floor(Math.random() * 3); // 3, 4, or 5 shapes
        
        const stageH = Math.max(10, root.height - 80);
        const cx = 0;
        const cy = 0;

        const hubSize = stageH * 0.4 + Math.random() * (stageH * 0.2); // 40-60% of height
        const hubRadius = hubSize / 2;

        const sizes = [hubSize];
        for (let i = 1; i < count; i++) {
            sizes.push(sizes[i - 1] / root.goldenRatio);
        }

        const currentTones = [
            Appearance.m3colors.m3primary,
            Appearance.m3colors.m3secondary,
            Appearance.m3colors.m3tertiary,
            Appearance.m3colors.m3primaryContainer,
            Appearance.m3colors.m3secondaryContainer,
            Appearance.m3colors.m3tertiaryContainer,
            Appearance.m3colors.m3error,
            Appearance.m3colors.m3surfaceVariant
        ];
        const hubDuration = 46 + Math.random() * 18;
        const usedTones = [...currentTones].sort(() => Math.random() - 0.5);
        const angleOffset = Math.random() * (Math.PI * 2);

        let newModel = [];
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;

        for (let i = 0; i < count; i++) {
            const size = sizes[i];
            const isHub = i === 0;
            const tone = isHub ? usedTones[0] : usedTones[i % usedTones.length];

            let x, y;
            if (isHub) {
                x = cx; y = cy;
            } else {
                const angle = angleOffset + (i - 1) * ((Math.PI * 2) / (count - 1)) + (Math.random() * 0.35 - 0.175);
                const overlapPct = Math.random() * 0.2;
                const dist = (hubRadius + size / 2) * (1 - overlapPct);
                x = cx + Math.cos(angle) * dist;
                y = cy + Math.sin(angle) * dist * 0.86;
            }

            minX = Math.min(minX, x - size / 2);
            minY = Math.min(minY, y - size / 2);
            maxX = Math.max(maxX, x + size / 2);
            maxY = Math.max(maxY, y + size / 2);

            const dur = isHub ? hubDuration : Math.max(7, hubDuration * (size / hubSize));
            const shapeName = root.shapeNames[Math.floor(Math.random() * root.shapeNames.length)];
            const pathData = root.generateShape(shapeName, size);
            const fillOpacity = 1.0;

            const svgString = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + size + ' ' + size + '"><path d="' + pathData + '" fill="' + tone + '"/></svg>';
            const imageSource = "data:image/svg+xml;utf8," + encodeURIComponent(svgString);

            newModel.push({
                size: size,
                x: x,
                y: y,
                color: tone,
                duration: dur,
                path: pathData,
                imageSource: imageSource,
                isHub: isHub,
                fillOpacity: fillOpacity
            });
        }

        root.clusterMinX = minX;
        root.clusterMinY = minY;
        root.clusterWidth = Math.max(1, maxX - minX);
        root.clusterHeight = Math.max(1, maxY - minY);
        root.gearModel = newModel;
    }

    onVisibleChanged: {
        if (visible) {
            buildGears();
        }
    }

    onWidthChanged: {
        if (visible) buildGears();
    }

    onHeightChanged: {
        if (visible) buildGears();
    }

    // ── UI ─────────────────────────────────────────────────────────────────────
    Item {
        id: stageItem
        anchors.fill: parent
        anchors.bottomMargin: 80 // Leave space for text
        clip: false // explicitly do not clip, as requested

        Item {
            id: clusterContainer
            width: root.clusterWidth
            height: root.clusterHeight
            anchors.centerIn: parent
            scale: Math.min(1.0, (stageItem.width * 0.9) / width, (stageItem.height * 0.9) / height)

            Repeater {
                model: root.gearModel
                
                delegate: Item {
                    required property var modelData

                    x: modelData.x - modelData.size / 2 - root.clusterMinX
                    y: modelData.y - modelData.size / 2 - root.clusterMinY
                    width: modelData.size
                    height: modelData.size
                    opacity: modelData.fillOpacity

                    RotationAnimation on rotation {
                        from: 0
                        to: modelData.isHub ? 360 : -360
                        duration: modelData.duration * 1000
                        loops: Animation.Infinite
                        running: root.visible
                    }

                    Image {
                        width: modelData.size
                        height: modelData.size
                        sourceSize.width: modelData.size
                        sourceSize.height: modelData.size
                        source: modelData.imageSource
                        x: 0
                        y: 0
                        smooth: true
                        antialiasing: true
                    }
                }
            }
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        
        text: root.currentText
        textFormat: Text.RichText
        font.pixelSize: Appearance.font.pixelSize.large
        font.family: Appearance.font.family.main
        font.weight: Font.Light
        color: Appearance.m3colors.m3onSurface
    }
}
