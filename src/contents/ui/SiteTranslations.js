.pragma library
// Human English translations of Japanese lyrics from UtaTime (often official) and Genius.
// Genius search finds the original song (also for covers, via a lyric line); its artist/title
// locate the UtaTime page. Both sites are scraped HTML: shortcut: breaks if their markup changes, fix the parsers then.

const GENIUS = "https://genius.com"
const UTATIME = "https://www.utatime.com/global/lyrics/"

function norm(s) {
    return s.normalize("NFKC").toLowerCase()
        .replace(/[\s!-\/:-@\[-`{-~\u2010-\u206f\u3000-\u303f\u30fb\uff65]/g, "")
}

function isLyricLine(line) {
    return /[\u3040-\u30ff\u4e00-\u9fff]/.test(line) && !/[:：]/.test(line) && new Set(norm(line)).size >= 4
}

function slugify(s) {
    return s.normalize("NFKC").toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
}

// Romanization spellings differ (Zankyosanka vs zankyou-sanka); compare without hyphens and long vowels.
function roma(slug) {
    return slug.replace(/-/g, "").replace(/ou/g, "o").replace(/oo/g, "o").replace(/uu/g, "u").replace(/aa/g, "a").replace(/ei/g, "e")
}

// Genius names look like "米津玄師 (Kenshi Yonezu)"; the romanized part is what UtaTime slugs use.
function nameSlugs(name) {
    const m = name.match(/^(.*?)\s*\(([^()]*)\)\s*$/)
    const slugs = (m ? [m[2], m[1]] : [name]).map(slugify).filter(s => s)
    return slugs.filter((s, i) => slugs.indexOf(s) === i)
}

function decodeEntities(s) {
    return s.replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
        .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&")
}

function htmlText(s) {
    return decodeEntities(s.replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim()
}

function allMatches(re, text) {
    const out = []
    let m
    while ((m = re.exec(text)) !== null) {
        out.push(m)
    }
    return out
}

// Numbered lines of one UtaTime tab ("EnglishOff" official, "English" UtaTime's own, "Original").
// Each tab holds the full version first, then a TV-size copy ("olyrictext-tv") that restarts numbering.
function utatimeBlock(page, id) {
    const start = page.indexOf('id="' + id + '"')
    if (start < 0) {
        return null
    }
    let end = page.indexOf('class="contents"', start + 10)
    const tv = page.indexOf('class="olyrictext-tv"', start)
    if (tv >= 0 && (end < 0 || tv < end)) {
        end = tv
    }
    const block = page.slice(start, end < 0 ? page.length : end)
        .replace(/<span class="rt">[^<]*<\/span>/g, "")
        .replace(/[(（][\u3040-\u309f]+[)）]/g, "")
    const lines = []
    block.split('<span class="line-number">').slice(1).forEach(part => {
        const m = part.match(/^(\d+)\.<\/span>([\s\S]*)$/)
        if (m) {
            lines[Number(m[1]) - 1] = htmlText(m[2].replace(/<br\s*\/?>/g, " ").replace(/<\/div>[\s\S]*$/, ""))
        }
    })
    return lines.length > 0 ? Array.from(lines, line => line || "") : null
}

// End index of the <div> opened at `start`, by tag depth (Genius nests divs inside lyric containers).
function divEnd(html, start) {
    const re = /<div\b|<\/div>/g
    re.lastIndex = html.indexOf(">", start) + 1
    let depth = 1
    let m
    while ((m = re.exec(html)) !== null) {
        depth += m[0] === "</div>" ? -1 : 1
        if (depth === 0) {
            return re.lastIndex
        }
    }
    return html.length
}

function geniusLines(page) {
    const lines = []
    allMatches(/<div[^>]*data-lyrics-container="true"/g, page).forEach(m => {
        let html = page.slice(page.indexOf(">", m.index) + 1, divEnd(page, m.index) - "</div>".length)
        let i
        while ((i = html.search(/<div[^>]*data-exclude-from-selection="true"/)) >= 0) {
            html = html.slice(0, i) + html.slice(divEnd(html, i))
        }
        decodeEntities(html.replace(/<br\s*\/?>/g, "\n").replace(/<[^>]+>/g, "")).split("\n").forEach(line => {
            if (line.trim()) {
                lines.push(line.trim())
            }
        })
    })
    return lines
}

function geniusSections(lines) {
    const sections = []
    let current = null
    lines.forEach(line => {
        if (/^\[.*\]$/.test(line)) {
            current = []
            sections.push(current)
        } else {
            if (!current) {
                current = []
                sections.push(current)
            }
            current.push(line)
        }
    })
    return sections.filter(section => section.length > 0)
}

// Genius translations usually keep the original's sections and line breaks; pair them 1:1 when they do.
function pairGenius(originalLines, englishLines) {
    const original = geniusSections(originalLines)
    const english = geniusSections(englishLines)
    if (original.length !== english.length || original.some((lines, s) => lines.length !== english[s].length)) {
        return null
    }
    return {
        original: [].concat.apply([], original),
        english: [].concat.apply([], english)
    }
}

const STOPWORDS = ["the", "and", "you", "your", "that", "this", "with", "for", "are", "was", "will", "can", "not", "but", "all", "its", "just", "from", "have", "into", "what"]

function words(text) {
    return text.toLowerCase().split(/[^a-z']+/)
        .filter(w => w.length >= 3 && STOPWORDS.indexOf(w) < 0)
        .map(w => w.replace(/(ing|ed|es|s)$/, "").slice(0, 6))
}

function similarity(a, b) {
    const wa = words(a)
    const wb = words(b)
    const common = wa.filter(w => wb.indexOf(w) >= 0).length
    const dice = wa.length + wb.length > 0 ? 2 * common / (wa.length + wb.length) : 0
    const length = Math.max(a.length, b.length) > 0 ? 1 - Math.abs(a.length - b.length) / Math.max(a.length, b.length) : 0
    return dice + 0.3 * length
}

// Translators often re-break lines. Align the human English lines to a machine translation of
// the original lines (monotonic 1:1, 1:2, 2:1 or skip, maximizing similarity) and return one
// human English string per original line.
function alignByMeaning(machine, human) {
    const J = machine.length
    const E = human.length
    const steps = [[1, 1], [1, 2], [2, 1], [1, 0], [0, 1]]
    const best = []
    for (let i = 0; i <= J; i++) {
        best.push([])
        for (let j = 0; j <= E; j++) {
            best[i].push(i === 0 && j === 0 ? { score: 0 } : { score: -Infinity })
            steps.forEach(step => {
                const pi = i - step[0]
                const pj = j - step[1]
                if (pi < 0 || pj < 0 || best[pi][pj].score === -Infinity) {
                    return
                }
                // Dropping a human line loses text; an original line without English just shows nothing.
                const gain = step[0] && step[1]
                    ? similarity(machine.slice(pi, i).join(" "), human.slice(pj, j).join(" "))
                    : step[0] ? 0 : -0.3
                if (best[pi][pj].score + gain > best[i][j].score) {
                    best[i][j] = { score: best[pi][pj].score + gain, step: step }
                }
            })
        }
    }
    const english = machine.map(() => "")
    for (let i = J, j = E; i > 0 || j > 0;) {
        const step = best[i][j].step
        if (step[0] && step[1]) {
            const text = human.slice(j - step[1], j).join(" ")
            for (let k = i - step[0]; k < i; k++) {
                english[k] = text
            }
        }
        i -= step[0]
        j -= step[1]
    }
    return english
}

// One English string per lyric line, located by finding each lyric line in the site's original text.
// Returns null when too few lines match, i.e. the page is a different song.
function align(lyrics, original, english) {
    let joined = ""
    const starts = original.map(line => {
        const start = joined.length
        joined += norm(line)
        return start
    })
    const lineAt = pos => {
        let k = 0
        while (k + 1 < starts.length && starts[k + 1] <= pos) {
            k++
        }
        return k
    }
    let cursor = 0
    let matched = 0
    let counted = 0
    const translations = lyrics.map(lyric => {
        const text = norm(lyric.text)
        if (isLyricLine(lyric.text)) {
            counted++
        }
        if (!text) {
            return ""
        }
        const find = part => {
            const at = joined.indexOf(part, cursor)
            return at >= 0 ? at : joined.indexOf(part)
        }
        let pos = find(text)
        let length = text.length
        if (pos < 0 && text.length >= 12) {
            // Lyric sources differ in small details ("あぁ" vs "Ah,"); fall back to either half of the line.
            length = Math.floor(text.length / 2)
            pos = find(text.slice(0, length))
            if (pos < 0) {
                pos = find(text.slice(text.length - length))
            }
        }
        if (pos < 0) {
            return ""
        }
        if (isLyricLine(lyric.text)) {
            matched++
        }
        cursor = pos + length
        const parts = []
        for (let k = lineAt(pos); k <= lineAt(pos + length - 1); k++) {
            if (english[k] && parts.indexOf(english[k]) < 0) {
                parts.push(english[k])
            }
        }
        return parts.join(" ")
    })
    return counted > 0 && matched / counted >= 0.5 ? translations : null
}

function firstResult(items, fn) {
    return items.reduce((chain, item) => chain.then(found => found || fn(item)), Promise.resolve(null))
}

// fetchText(url) -> Promise<string>; translateLines(texts) -> Promise<string[]> machine translation,
// only used to line up re-broken Genius translations. Resolves { source, translations } or null when no site has the song.
function find(fetchText, translateLines, track, artist, lyrics) {
    const fetchJson = url => fetchText(url).then(text => JSON.parse(text))
    const tryFetch = url => fetchText(url).catch(() => null)
    const queries = [track + " " + artist]
    const lyricLine = lyrics.map(line => line.text).filter(isLyricLine)[0]
    if (lyricLine) {
        queries.push(lyricLine)
    }
    const artistPages = {}

    function tryUtaTime(song) {
        const titles = nameSlugs(song.title.replace(/\s*\[.*?\]\s*/g, " ").trim()).map(roma)
        return firstResult(nameSlugs(song.primary_artist.name), artistSlug => {
            if (!(artistSlug in artistPages)) {
                artistPages[artistSlug] = tryFetch(UTATIME + artistSlug + "/")
            }
            return artistPages[artistSlug].then(page => {
                if (!page) {
                    return null
                }
                const slugs = allMatches(new RegExp('href="' + UTATIME.replace(/[.\/]/g, "\\$&") + artistSlug + '/([a-z0-9-]+)/"', "g"), page)
                    .map(m => m[1])
                    .filter((slug, i, all) => all.indexOf(slug) === i && titles.some(t => t && roma(slug).startsWith(t)))
                    .sort((a, b) => a.length - b.length)
                    .slice(0, 3)
                return firstResult(slugs, slug => tryFetch(UTATIME + artistSlug + "/" + slug + "/english/").then(songPage => {
                    if (!songPage) {
                        return null
                    }
                    const official = utatimeBlock(songPage, "EnglishOff")
                    const english = official || utatimeBlock(songPage, "English")
                    const original = utatimeBlock(songPage, "Original")
                    const translations = english && original ? align(lyrics, original, english) : null
                    return translations && { source: (official ? "UtaTime (official)" : "UtaTime") + ": " + artistSlug + "/" + slug, translations: translations }
                }))
            })
        })
    }

    // Some "Genius English Translations" pages are not linked from the original song; search for them.
    function findGeniusTranslation(song) {
        const linked = (song.translation_songs || []).filter(t => t.language === "en")[0]
        if (linked) {
            return Promise.resolve(linked.url)
        }
        const title = song.title.replace(/\s*[(\[].*$/, "").trim().toLowerCase()
        if (!title) {
            return Promise.resolve(null)
        }
        const artists = song.primary_artist.name.split(/\s*[()]\s*/).filter(s => s).map(s => s.toLowerCase())
        return fetchJson(GENIUS + "/api/search/multi?q=" + encodeURIComponent(song.primary_artist.name + " " + song.title + " English Translation")).then(result => {
            let url = null
            result.response.sections.forEach(section => section.hits.forEach(hit => {
                const r = hit.result
                const hitTitle = (r.title || "").toLowerCase()
                if (!url && hit.type === "song" && r.primary_artist.name === "Genius English Translations"
                        && hitTitle.indexOf(title) >= 0 && artists.some(a => hitTitle.indexOf(a) >= 0)) {
                    url = r.url
                }
            }))
            return url
        }, () => null)
    }

    function tryGenius(song) {
        return findGeniusTranslation(song).then(translationUrl => {
            if (!translationUrl) {
                return null
            }
            return Promise.all([tryFetch(song.url), tryFetch(translationUrl)]).then(pages => {
                if (!pages[0] || !pages[1]) {
                    return null
                }
                const originalLines = geniusLines(pages[0])
                const englishLines = geniusLines(pages[1])
                const exact = pairGenius(originalLines, englishLines)
                const notHeader = line => !/^\[.*\]$/.test(line)
                const original = originalLines.filter(notHeader)
                const pairs = exact
                    ? Promise.resolve(exact)
                    : translateLines(original).then(machine => ({
                        original: original,
                        english: alignByMeaning(machine, englishLines.filter(notHeader))
                    }), () => null)
                return pairs.then(p => {
                    const translations = p ? align(lyrics, p.original, p.english) : null
                    return translations && { source: "Genius" + (exact ? "" : " (realigned)") + ": " + translationUrl, translations: translations }
                })
            })
        })
    }

    return Promise.all(queries.map(q => fetchJson(GENIUS + "/api/search/multi?q=" + encodeURIComponent(q)))).then(results => {
        const ids = []
        results.forEach(result => result.response.sections.forEach(section => {
            if (section.type === "top_hit" || section.type === "song" || section.type === "lyric") {
                section.hits.forEach(hit => {
                    if (hit.type === "song" && ids.indexOf(hit.result.id) < 0) {
                        ids.push(hit.result.id)
                    }
                })
            }
        }))
        return firstResult(ids.slice(0, 5), id => fetchJson(GENIUS + "/api/songs/" + id).then(data => {
            const song = data.response.song
            // "Genius Romanizations", "Genius English Translations", ... are Genius's own copies, not songs.
            if (/^Genius\b/.test(song.primary_artist.name)) {
                return null
            }
            return tryUtaTime(song).then(found => found || tryGenius(song))
        }, () => null))
    })
}
