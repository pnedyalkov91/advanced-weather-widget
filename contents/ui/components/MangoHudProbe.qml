/*
 * MangoHudProbe.qml - reports whether an overlay such as MangoHud is injected
 * into plasmashell via LD_PRELOAD.
 *
 * LD_PRELOAD is process-wide symbol interposition, so a widget cannot opt out
 * of it. What it can do is notice it and keep fragile native stacks (the
 * QtWebEngine radar) out of a process that has it. A child process inherits
 * plasmashell's environment, so asking a tiny shell for $LD_PRELOAD tells us
 * what plasmashell was started with, without needing /proc access from QML.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: probe

    visible: false
    width: 0
    height: 0

    property bool done: false
    property bool detected: false

    readonly property string _command: "echo \"preload=[$LD_PRELOAD]\""

    Component.onCompleted: exec.connectSource(_command)

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var out = (data["stdout"] || "").toString();
            probe.detected = /mangohud/i.test(out);
            probe.done = true;
        }
    }
}
