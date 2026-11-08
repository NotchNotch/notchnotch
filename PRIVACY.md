# Privacy

NotchNotch runs entirely on your Mac. It has no account, analytics, crash reporting or advertising, and the app itself sends nothing to the developer or to third parties.

## What stays on your Mac

- **Preferences** (enabled extensions, display, hover and login options) and **remembered connection access** are stored in the app's preferences.
- **Extension storage** is a JSON file per extension in `~/Library/Application Support/NotchNotch/Storage`. It is deleted when the extension is removed.
- **Extension logs** are kept in memory only and cleared when the app quits.

## Included extensions

- **Music** reads the current track, artwork and playback state from Spotify or Apple Music through Apple events, after you connect a player and macOS asks for Automation permission. Artwork may be downloaded from the player's image CDN to display it.
- **Calendar** reads events from the calendars you select, after macOS asks for Calendar access. It never changes events. **Join meeting** opens the meeting link in your browser.

## Extensions you install

Extensions run with the connections declared in their manifest and the native tools they ship. A native tool runs with your user account. Install extensions only from developers you trust; their data practices are their own.

## Contact

Questions: open an issue on the project's GitHub repository.
