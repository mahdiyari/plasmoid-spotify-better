# Spotify Better for Plasma 6

A fork of [LabyStudio's Spotify plasmoid](https://github.com/LabyStudio/plasmoid-spotify). It keeps the original widget's artwork, track details, playback controls, and scrolling lyrics while improving how media is fetched.

## What this fork changes

- Finds synced lyrics more reliably with duration-aware LRCLIB matching and broader fallbacks when an exact match has no timed lyrics.
- Shows lyrics as soon as they arrive, displays brief loading/error messages, and retries transient failures (including rate limits) once.
- Optional English translation of non-English lyrics (Settings → Lyrics → English translation), shown below each line or instead of the original. Japanese songs use an existing human translation when one can be found online; everything else is machine-translated through Google Translate's public endpoint, which receives the lyrics text. Translations are cached with lyrics.
- Caches lyrics and their translations (up to 2 MiB) and album artwork (configurable 0–256 MiB, default 32 MiB). Settings show current cache usage.
- Falls back to the widget icon when artwork cannot be loaded.

![Spotify Plasmoid Preview](.github/assets/preview.gif)

## Install locally

Requires KDE Plasma 6. From a terminal:

```bash
git clone https://github.com/mahdiyari/plasmoid-spotify-better.git
cd plasmoid-spotify-better
kpackagetool6 --type Plasma/Applet --install src
```

This installs **Spotify Better** widget. For later updates, use `kpackagetool6 --type Plasma/Applet --upgrade src`.

After installing or updating, run `plasmashell --replace` from KRunner (Alt+Space), then add **Spotify Better** from the widget picker.
