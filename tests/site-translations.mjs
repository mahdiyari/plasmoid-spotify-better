// Run: node tests/site-translations.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../src/contents/ui/SiteTranslations.js", import.meta.url), "utf8")
const { align, pairGenius, alignByMeaning } = new Function(source.replace(".pragma library", "") + "\nreturn { align, pairGenius, alignByMeaning }")()
const lyrics = lines => lines.map(text => ({ text }))

// Site lines: one merged line (b+c), a chorus that the timed lyrics repeat, and a blank stanza break.
const original = ["あいうえおかきく", "さしすせそ たちつてと", "", "なにぬねのはひふへほ"]
const english = ["A", "B and C", "", "Chorus"]

assert.deepEqual(
    align(lyrics(["あいうえおかきく", "さしすせそ", "たちつてと", "なにぬねの はひふへほ", "ルルル", "なにぬねの、はひふへほ！", "ああさしすせそたちつてと"]), original, english),
    ["A", "B and C", "B and C", "Chorus", "", "Chorus", "B and C"],
    "split, punctuation/space differences, vocalizations, repeats and a differing line start map to the right site lines")

assert.equal(align(lyrics(["まみむめもやゆよ", "らりるれろわをん"]), original, english), null,
    "a page for a different song is rejected")

// Genius: identical section/line structure pairs 1:1; anything else needs realignment.
assert.deepEqual(
    pairGenius(["[Verse]", "一", "二", "[Chorus]", "三"], ["[Verse]", "One", "Two", "[Chorus]", "Three"]),
    { original: ["一", "二", "三"], english: ["One", "Two", "Three"] })
assert.equal(pairGenius(["[Verse]", "一", "二"], ["One", "Two", "Three"]), null)

// A translator split line 2 in two and merged lines 3-4; machine translations of the originals guide the alignment.
assert.deepEqual(
    alignByMeaning(
        ["The red moon rises over the city", "I keep walking alone through the night until morning comes", "Your voice", "still echoes in my heart"],
        ["Over the city the red moon rises", "Alone I keep walking through the night", "until the morning comes", "Your voice still echoes inside my heart"]),
    ["Over the city the red moon rises", "Alone I keep walking through the night until the morning comes", "Your voice still echoes inside my heart", "Your voice still echoes inside my heart"])

console.log("ok")
