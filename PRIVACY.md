# Privacy

NotchNotch runs entirely on your Mac. It has no account, analytics, automatic crash reporting or advertising, and the app itself sends nothing to the developer or to third parties apart from update checks to GitHub, described below.

## What stays on your Mac

- **Preferences** (enabled extensions, display, hover and login options) and **remembered connection access** are stored in the app's preferences.
- **Extension storage** is a JSON file per extension in `~/Library/Application Support/NotchNotch/Storage`. It is deleted when the extension is removed.
- **Extension secrets**, such as API tokens an extension asks you for, are kept in your login Keychain, readable only by that extension. They are deleted when the extension is removed, and can be deleted from its **Access** tab.
- **Extension logs** are kept in memory only and cleared when the app quits.
- **Problems** (extensions that failed or stopped, Store updates that couldn't install) are kept in memory for this session. If you turn on **General › Problems › Remember problems between launches**, up to two weeks of them are saved in `~/Library/Application Support/NotchNotch/Problems.json`, and NotchNotch reads macOS's crash reports in `~/Library/Logs/DiagnosticReports`, only those of its own processes, to notice crashes. Turning it off deletes the file.
- **Problem reports** are made only when you choose **Export…**. You see the whole text before saving it, your home folder and account name are removed, and NotchNotch never sends it: you decide whether to attach it to an issue.

## Update checks

Release builds check for updates about once a day by downloading `appcast.xml` from GitHub (`raw.githubusercontent.com`), and download the update itself from GitHub Releases. GitHub sees your IP address and a user agent with the app and macOS versions; no system profile is sent. Turn this off in **Settings & Extensions… › About › Check for updates automatically**.

## Included extensions

- **Music** reads the current track, artwork and playback state from Spotify or Apple Music through Apple events, after you connect a player and macOS asks for Automation permission. Artwork may be downloaded from the player's image CDN to display it. Extensions can only load artwork from hosts listed in their manifest, which you see before installing.
- **Calendar** reads events from the calendars you select, after macOS asks for Calendar access. It never changes events. **Join meeting** opens the meeting link in your browser.

## Extensions you install

Extensions run with the connections declared in their manifest and the native tools they ship. A native tool runs with your user account. Install extensions only from developers you trust; their data practices are their own.

## Contact

Questions: open an issue on the project's GitHub repository.
