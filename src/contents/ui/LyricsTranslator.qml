import QtQuick 2.15
import "SiteTranslations.js" as Sites

Item {
    required property var cache

    Utils {
        id: utils
    }

    // Keyless Google Translate endpoint; shortcut: unofficial and rate-limited, switch to a keyed API if it starts failing.
    readonly property string url: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t"
    // Genius and UtaTime reject Qt's default "Mozilla/5.0" user agent.
    readonly property var siteHeaders: ({
        "User-Agent": "Spotify Better/1.0.0 (https://github.com/mahdiyari/plasmoid-spotify-better)"
    })

    // Resolves to one English string per lyric line ("" where there is nothing to show),
    // or null when the lyrics are already English. Human translations from UtaTime/Genius
    // are preferred for Japanese lyrics; Google Translate covers everything else.
    function translate(lyrics, track, artist) {
        const indexes = []
        const texts = []
        lyrics.forEach((line, i) => {
            const text = line.text.trim()
            if (text) {
                indexes.push(i)
                texts.push(text)
            }
        })
        if (texts.length === 0) {
            return Promise.resolve(null)
        }

        const source = texts.join("\n")
        const key = "translation:v2:" + Qt.md5(source)
        const cached = cache.get("lyrics", key)
        if (cached !== null) {
            try {
                return Promise.resolve(JSON.parse(cached))
            } catch (error) {
                cache.remove("lyrics", key)
            }
        }

        // A failed site lookup (network, rate limit) is not cached so the song is retried later.
        let cacheable = true
        const japanese = lyrics.some(line => Sites.isLyricLine(line.text))
        const site = japanese
            ? Sites.find(url => utils.fetch(url, siteHeaders).then(response => response.text()),
                    lines => google(lines).then(result => result.lines), track || "", artist || "", lyrics)
                .catch(error => {
                    console.warn("Could not search translation sites:", error && error.status !== undefined ? "HTTP " + error.status : error)
                    cacheable = false
                    return null
                })
            : Promise.resolve(null)

        return site.then(found => {
            if (found) {
                console.log("Lyrics translation from", found.source)
                return found.translations
            }
            return google(texts).then(result => {
                if (result.language === "en") {
                    return null
                }
                const translations = lyrics.map(() => "")
                indexes.forEach((lyricIndex, i) => {
                    if (result.lines[i].toLowerCase() !== texts[i].toLowerCase()) {
                        translations[lyricIndex] = result.lines[i]
                    }
                })
                return translations
            })
        }).then(translations => {
            if (cacheable) {
                cache.put("lyrics", key, JSON.stringify(translations))
            }
            return translations
        })
    }

    // Resolves { language: detected source language, lines: one English line per input line }.
    function google(texts) {
        return utils.fetch(url, {
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8"
        }, "q=" + encodeURIComponent(texts.join("\n"))).then(response => {
            const data = response.json()
            // Segments are sentence chunks that keep the source newlines, so joining restores one line per input line.
            const lines = data[0].map(segment => segment[0] || "").join("").split("\n").map(line => line.trim())
            if (lines.length !== texts.length) {
                throw new Error("Translation returned " + lines.length + " lines for " + texts.length)
            }
            return { language: data[2], lines: lines }
        })
    }
}
