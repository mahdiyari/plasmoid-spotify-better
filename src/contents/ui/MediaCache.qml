import QtQuick 2.15
import QtQuick.LocalStorage 2.0 as Sql

Item {
    property var db: null
    property int artworkLimit: 32 * 1024 * 1024
    readonly property int lyricsLimit: 1024 * 1024

    function database() {
        if (db) {
            return db
        }
        db = Sql.LocalStorage.openDatabaseSync("SpotifyBetterMediaCache", "1.0", "Spotify Better lyrics and artwork", 10000000)
        db.transaction(tx => {
            tx.executeSql("PRAGMA auto_vacuum = FULL")
            tx.executeSql("CREATE TABLE IF NOT EXISTS entries (kind TEXT NOT NULL, cache_key TEXT NOT NULL, value TEXT NOT NULL, accessed INTEGER NOT NULL, PRIMARY KEY (kind, cache_key))")
        })
        return db
    }

    function get(kind, key) {
        try {
            let value = null
            database().transaction(tx => {
                const rows = tx.executeSql("SELECT value FROM entries WHERE kind = ? AND cache_key = ?", [kind, key])
                if (rows.rows.length > 0) {
                    value = rows.rows.item(0).value
                    tx.executeSql("UPDATE entries SET accessed = ? WHERE kind = ? AND cache_key = ?", [Date.now(), kind, key])
                }
            })
            return value
        } catch (error) {
            console.warn("Could not read media cache:", error)
            return null
        }
    }

    function put(kind, key, value) {
        try {
            database().transaction(tx => {
                tx.executeSql("INSERT OR REPLACE INTO entries (kind, cache_key, value, accessed) VALUES (?, ?, ?, ?)", [kind, key, value, Date.now()])
                trimKind(tx, kind)
            })
        } catch (error) {
            console.warn("Could not write media cache:", error)
        }
    }

    function trimKind(tx, kind) {
        const limit = kind === "artwork" ? artworkLimit : lyricsLimit
        tx.executeSql("DELETE FROM entries WHERE rowid IN (SELECT rowid FROM (SELECT rowid, SUM(length(CAST(value AS BLOB))) OVER (ORDER BY accessed DESC, rowid DESC) AS used FROM entries WHERE kind = ?) WHERE used > ?)", [kind, limit])
    }

    function trim(kind) {
        try {
            database().transaction(tx => trimKind(tx, kind))
        } catch (error) {
            console.warn("Could not trim media cache:", error)
        }
    }

    function remove(kind, key) {
        try {
            database().transaction(tx => {
                tx.executeSql("DELETE FROM entries WHERE kind = ? AND cache_key = ?", [kind, key])
            })
        } catch (error) {
            console.warn("Could not remove media cache entry:", error)
        }
    }

    function fetchArtwork(url) {
        if (artworkLimit <= 0) {
            return Promise.resolve(url)
        }
        const cached = get("artwork", url)
        if (cached !== null) {
            return Promise.resolve(cached)
        }
        return downloadArtwork(url).then(source => {
            put("artwork", url, source)
            return source
        })
    }

    function downloadArtwork(url) {
        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", url, true)
            xhr.responseType = "arraybuffer"
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE) {
                    return
                }
                if (xhr.status !== 200 || !xhr.response) {
                    reject("HTTP " + xhr.status)
                    return
                }

                const bytes = new Uint8Array(xhr.response)
                const mime = (xhr.getResponseHeader("Content-Type") || "").split(";")[0].trim().toLowerCase()
                if (!mime.startsWith("image/") || bytes.length === 0 || bytes.length > 2 * 1024 * 1024) {
                    reject("Unsupported artwork response")
                    return
                }
                resolve("data:" + mime + ";base64," + encodeBase64(bytes))
            }
            xhr.send()
        })
    }

    function encodeBase64(bytes) {
        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        const parts = []
        let chunk = ""
        let i = 0
        for (; i + 2 < bytes.length; i += 3) {
            chunk += alphabet[bytes[i] >> 2]
                + alphabet[((bytes[i] & 3) << 4) | (bytes[i + 1] >> 4)]
                + alphabet[((bytes[i + 1] & 15) << 2) | (bytes[i + 2] >> 6)]
                + alphabet[bytes[i + 2] & 63]
            if (chunk.length >= 8192) {
                parts.push(chunk)
                chunk = ""
            }
        }
        if (i < bytes.length) {
            chunk += alphabet[bytes[i] >> 2]
                + alphabet[(bytes[i] & 3) << 4 | (i + 1 < bytes.length ? bytes[i + 1] >> 4 : 0)]
                + (i + 1 < bytes.length ? alphabet[(bytes[i + 1] & 15) << 2] : "=")
                + "="
        }
        parts.push(chunk)
        return parts.join("")
    }

    onArtworkLimitChanged: trim("artwork")
    Component.onCompleted: {
        trim("artwork")
        trim("lyrics")
    }
}
