/*
 * AlertSoundPlayer.qml - plays a sound file WITHOUT QtMultimedia.
 *
 * Why: creating a MediaPlayer/AudioOutput inside plasmashell makes Qt load and
 * initialise its whole multimedia backend (FFmpeg or GStreamer) in that
 * process. Under an LD_PRELOAD overlay such as MangoHud that initialisation
 * corrupts the heap and takes plasmashell down. Handing the file to a small
 * external player keeps all audio decoding out of plasmashell's address space.
 *
 * Needs `pw-play` (pipewire-utils) or `paplay` (pulseaudio-utils) on PATH.
 * Both decode through libsndfile: wav/ogg/flac are fine; mp3/opus depend on how
 * libsndfile was built on the user's distro.
 *
 * Public API (unchanged from the QtMultimedia version, so callers need no edits):
 *   playUrl(url), stop(), hasError, errorString, failed(message)
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: player

    visible: false
    width: 0
    height: 0

    property bool hasError: false
    property string errorString: ""

    signal failed(string message)

    // Command string of the currently running player, "" when idle.
    property string _runningCommand: ""

    /** file:// URL or plain path -> local filesystem path. */
    function _toLocalPath(url) {
        var s = String(url);
        if (s.indexOf("file://") === 0)
            s = decodeURIComponent(s.substring(7));
        return s;
    }

    /** POSIX single-quote escaping, so odd file names can't break out of the command. */
    function _shQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    function _buildCommand(path) {
        // `exec` replaces the shell with the player, so the process we may
        // later kill is the player itself. `env -u LD_PRELOAD` keeps overlays
        // such as MangoHud (inherited from plasmashell) out of the helper.
        var script =
            'f="$1"; ' +
            'if command -v pw-play >/dev/null 2>&1; then exec pw-play "$f"; ' +
            'elif command -v paplay >/dev/null 2>&1; then exec paplay "$f"; fi; ' +
            'echo "no audio player found (install pipewire-utils or pulseaudio-utils)" >&2; exit 127';
        return "env -u LD_PRELOAD sh -c " + _shQuote(script) + " alert-sound " + _shQuote(path);
    }

    function playUrl(url) {
        stop();
        hasError = false;
        errorString = "";
        var path = _toLocalPath(url);
        if (path.length === 0)
            return;
        _runningCommand = _buildCommand(path);
        exec.connectSource(_runningCommand);
    }

    function stop() {
        if (_runningCommand.length > 0) {
            exec.disconnectSource(_runningCommand);   // asks the engine to drop (and end) the job
            _runningCommand = "";
        }
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (sourceName === player._runningCommand)
                player._runningCommand = "";
            var code = data["exit code"];
            if (code !== undefined && code !== 0) {
                var msg = (data["stderr"] || "").toString().trim();
                if (msg.length === 0)
                    msg = "player exited with code " + code;
                player.hasError = true;
                player.errorString = msg;
                player.failed(msg);
            }
        }
    }
}
