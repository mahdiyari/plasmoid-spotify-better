import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import Qt5Compat.GraphicalEffects
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: widget

    Plasmoid.status: PlasmaCore.Types.HiddenStatus
    Plasmoid.backgroundHints: plasmoid.configuration.transparentBackground
        ? PlasmaCore.Types.NoBackground
        : PlasmaCore.Types.DefaultBackground

    Layout.preferredWidth: row.implicitWidth
    Layout.preferredHeight: row.implicitHeight

    readonly property int volumeStep: 2
    property int lyricsRequestId: 0

    MediaCache {
        id: mediaCache
    }

    /* Lyrics LRC library */
    LyricsLrcLib {
        id: lyricsLrcLib
        cache: mediaCache
    }

    /* Spotify player */
    Spotify {
        id: spotify
    }

    /* Signal handlers */
    Connections {
        target: spotify

        function onReadyChanged() {
            Plasmoid.status = spotify.ready ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
        }

        function onPositionChanged() {
            if (spotify.ready) {
                updateProgressIndicator()
            }
        }

        function onArtworkUrlChanged() {
            updateArtwork()
        }

        function onTrackChanged() {
            Qt.callLater(updateLyrics)
        }

        function onArtistChanged() {
            Qt.callLater(updateLyrics)
        }

        function onAlbumChanged() {
            Qt.callLater(updateLyrics)
        }
    }

    Connections {
        target: plasmoid.configuration

        function onFetchAlbumCoverHttpsChanged() {
            updateArtwork()
        }
    }

    /* Progress bar updater */
    Timer {
        id: timer
        interval: 1000;
        running: spotify && spotify.playing;
        repeat: true
        onTriggered: () => {
            updateProgressIndicator()
        }
    }

    /* Mouse click handling */
    MouseArea {
        z: 100
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: spotify && spotify.canRaise ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: true

        onClicked: (mouse) => {
            switch (mouse.button) {
                case Qt.MiddleButton:
                    spotify.togglePlayback()
                    break
                case Qt.LeftButton:
                    if (spotify.canRaise) {
                        spotify.raise()
                    }
                    break
            }
        }

        onWheel: (wheel) => {
            if (wheel.angleDelta.y > 0) {
                spotify.changeVolume(volumeStep / 100, true)
            } else {
                spotify.changeVolume(-volumeStep / 100, true)
            }
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 0
        clip: true

        LyricsRenderer {
            id: lyricsRenderer
            lyrics: null
            spotify: spotify
            visible: plasmoid.configuration.showLyrics && spotify && spotify.ready
                && ((lyrics && lyrics.length > 0) || statusText)
            Layout.fillWidth: true
            centeredLyrics: !plasmoid.configuration.showAlbumCover
                && !plasmoid.configuration.showTitle
                && !plasmoid.configuration.showArtist
        }

        /* Album artwork */
        Image {
            id: artwork

            Layout.preferredWidth: parent.height
            Layout.preferredHeight: parent.height
            Layout.rightMargin: 5
            Layout.fillWidth: false
            fillMode: Image.PreserveAspectFit
            cache: false


            property string fallbackSource: "../assets/icon.svg"
            property string remoteSource: ""

            source: artwork.fallbackSource
            visible: plasmoid.configuration.showAlbumCover

            Timer {
                id: fallbackTimer
                interval: 5000
                repeat: false
                onTriggered: artwork.fail()
            }

            onSourceChanged: {
                if (source === fallbackSource) {
                    fallbackTimer.stop()
                } else {
                    fallbackTimer.restart()
                }
            }

            onStatusChanged: {
                switch (status) {
                    case Image.Ready:
                        fallbackTimer.stop()
                        break
                    case Image.Error:
                        fail()
                        break
                }
            }

            function fail() {
                fallbackTimer.stop()
                console.warn("Failed to load artwork from", remoteSource || source)
                if (remoteSource) {
                    mediaCache.remove("artwork", remoteSource)
                }
                source = fallbackSource
            }

            /* Border radius */
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Item {
                    width: artwork.width
                    height: artwork.height
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                    }
                }
            }

            /* Progress bar */
            Rectangle {
                id: progress
                visible: spotify && spotify.ready

                x: 2
                height: 3
                width: artwork.width - 4
                anchors.bottom: parent.bottom
                color: "#282828"

                Rectangle {
                    id: progressIndicator
                    anchors.bottom: parent.bottom
                    height: 2
                    width: 0
                    color: "#1db954"
                }
            }
        }

        /* Song information */
        Item {
            Layout.preferredWidth: column.implicitWidth
            Layout.preferredHeight: column.implicitHeight
            Layout.fillWidth: true
            visible: plasmoid.configuration.showTitle || plasmoid.configuration.showArtist

            ColumnLayout {
                id: column
                anchors.fill: parent
                spacing: 0

                /* Song title */
                Text {
                    id: title
                    wrapMode: Text.NoWrap
                    lineHeightMode: Text.FixedHeight
                    Layout.fillWidth: true
                    Layout.rightMargin: 20

                    color: plasmoid.configuration.useCustomTitleColor ? plasmoid.configuration.titleTextColor : Kirigami.Theme.textColor
                    font.pixelSize: plasmoid.configuration.titleFontSize
                    font.family: plasmoid.configuration.titleFontFamily
                    font.weight: Font.Bold
                    text: spotify && spotify.ready
                        ? truncateText(spotify.track || spotify.identity || "No song playing", plasmoid.configuration.maxTitleArtistLength)
                        : "Spotify"

                    Layout.preferredHeight: title.font.pixelSize + (plasmoid.configuration.showArtist && (!spotify.ready || !!spotify.artist) ? 4 : 8)
                    visible: plasmoid.configuration.showTitle
                }

                /* Artist name */
                Text {
                    id: artist
                    wrapMode: Text.NoWrap
                    lineHeightMode: Text.FixedHeight
                    Layout.fillWidth: true
                    Layout.rightMargin: 20

                    color: plasmoid.configuration.useCustomArtistColor ? plasmoid.configuration.artistTextColor : Kirigami.Theme.textColor
                    font.pixelSize: plasmoid.configuration.artistFontSize
                    font.family: plasmoid.configuration.artistFontFamily
                    text: spotify && spotify.ready
                        ? truncateText(spotify.artist || "", plasmoid.configuration.maxTitleArtistLength)
                        : "No song playing"

                    Layout.preferredHeight: artist.font.pixelSize + 4
                    visible: plasmoid.configuration.showArtist && (!spotify.ready || !!spotify.artist)
                }
            }
        }
    }

    function updateProgressIndicator() {
        if (spotify.ready) {
            progressIndicator.width = Math.min(1, (spotify.getDaemonPosition() / spotify.length)) * progress.width
        }
    }

    function truncateText(text, maxLen) {
        return text && text.length > maxLen
            ? text.slice(0, maxLen - 3) + "..."
            : text;
    }

    /* Artwork update handler */
    function updateArtwork() {
        let url = spotify.ready ? spotify.artworkUrl : null
        if (url && url.startsWith("https://") && !plasmoid.configuration.fetchAlbumCoverHttps) {
            url = url.replace("https://", "http://")
        }
        artwork.remoteSource = url && /^https?:\/\//.test(url) ? url : ""
        if (!url) {
            artwork.source = artwork.fallbackSource
        } else if (!artwork.remoteSource) {
            artwork.source = url
        } else {
            artwork.source = artwork.fallbackSource
            mediaCache.fetchArtwork(url).then(source => {
                if (url === artwork.remoteSource) {
                    artwork.source = source
                }
            }).catch(error => {
                if (url === artwork.remoteSource) {
                    console.warn("Could not cache artwork from", url, error)
                    artwork.source = url
                }
            })
        }
    }

    /* Lyrics update handler */
    Timer {
        id: lyricsStatusTimer
        interval: 4000
        onTriggered: lyricsRenderer.statusText = ""
    }

    Timer {
        id: lyricsRetryTimer
        property var callback: null
        onTriggered: {
            const pending = callback
            callback = null
            if (pending) {
                pending()
            }
        }
    }

    function showLyricsStatus(text) {
        lyricsRenderer.statusText = text
        lyricsStatusTimer.restart()
    }

    function retryLyrics(error, callback) {
        const retryAfter = Number(error.retryAfter)
        lyricsRetryTimer.interval = error.status === 429
            ? (Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 5000)
            : 1000
        lyricsRetryTimer.callback = callback
        lyricsRetryTimer.restart()
        showLyricsStatus(error.status === 429 ? "Lyrics service busy; retrying…" : "Retrying lyrics…")
    }

    function updateLyrics() {
        if (spotify && spotify.ready && spotify.track && spotify.artist) {
            const requestId = ++lyricsRequestId
            const track = spotify.track
            const artist = spotify.artist
            const album = spotify.album
            const duration = spotify.length / 1_000_000

            lyricsRetryTimer.stop()
            lyricsRetryTimer.callback = null
            lyricsRenderer.lyrics = null;

            function fetch(attempt) {
                showLyricsStatus("Loading lyrics…")
                lyricsLrcLib.fetchLyrics(track, artist, album, duration)
                    .then(lyrics => {
                    if (widget && requestId === lyricsRequestId) {
                        lyricsRenderer.lyrics = lyrics;
                        if (lyrics) {
                            lyricsStatusTimer.stop()
                            lyricsRenderer.statusText = ""
                        } else {
                            showLyricsStatus("No synced lyrics")
                        }
                    }
                }).catch(error => {
                    console.warn("Could not fetch lyrics:", error)
                    if (requestId !== lyricsRequestId) {
                        return
                    }
                    if (attempt === 0) {
                        retryLyrics(error, () => fetch(1))
                    } else {
                        showLyricsStatus(error.status === 429 ? "Lyrics service busy" : "Lyrics unavailable")
                    }
                })
            }

            fetch(0)
        } else {
            lyricsRequestId++
            lyricsRetryTimer.stop()
            lyricsRetryTimer.callback = null
            lyricsRenderer.lyrics = null;
            lyricsStatusTimer.stop()
            lyricsRenderer.statusText = ""
        }
    }
}
