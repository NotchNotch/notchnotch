# Using NotchNotch

NotchNotch turns the notch on your Mac into a small, quiet place for what's happening now: the song that's playing, your next meeting, a timer, or anything an extension adds.

## Install

NotchNotch needs macOS 14 or later.

1. Download the latest `NotchNotch-<version>.dmg` from [Releases](https://github.com/sadeqi-ah/notchnotch/releases).
2. Open it and drag **NotchNotch** to **Applications**.
3. Open NotchNotch. This preview isn't notarized by Apple yet, so macOS blocks the first launch. Choose **Done**, open **System Settings › Privacy & Security**, scroll to *"NotchNotch" was blocked* and choose **Open Anyway**. You only do this once.

After that, NotchNotch updates itself. Choose **Check for Updates…** in the menu bar to update right away.

## The notch

NotchNotch lives in the menu bar and around the camera. When nothing is going on, the notch looks the way it always does.

- **Compact:** an activity shows a symbol and a few words on either side of the camera.
- **Hover** over the notch to preview, and **click** to open it.
- **Announcements** briefly show one line below the camera, such as a new song.
- **Questions** from an extension open on their own and wait for your answer. Closing the notch doesn't answer them; a badge reminds you.
- Press **Escape** or click elsewhere to close it.

When several activities are running, the notch shows one of them. Switch to another from the menu in the top-left corner of the open notch.

## Music

Shows what's playing in Spotify or Apple Music, with playback controls.

1. Open **Settings & Extensions…** from the menu bar and choose **Music**.
2. In **Setup**, choose **Connect Spotify** or **Connect Apple Music**.
3. Allow NotchNotch to use the music helper, then allow it to control the player when macOS asks.

## Calendar

Shows your next event with a countdown, and a button to join the meeting.

1. Open **Settings & Extensions…** and choose **Calendar**.
2. In **Setup**, choose **Connect Calendar** and allow access when macOS asks.
3. Choose which calendars to show.

It uses the accounts already in the Calendar app. NotchNotch only reads your calendars.

## Settings

Open **Settings & Extensions…** from the menu bar, or press **⌘,** while NotchNotch is active.

- **General:** open NotchNotch at login.
- **Notch:** choose the display, and whether the notch opens when you hover over it.
- **About:** version and software updates.

## Extensions

Each extension has a page with these tabs:

- **Setup:** what it needs from you, such as connecting an app.
- **About:** what it does and what changed in each version, when the extension includes them.
- **Access:** what it can connect to, which access you chose to always allow, and the secrets it saved in your Keychain. **Forget** makes it ask again.
- **Developer:** its console, package details and **Remove…**.

Use the switch at the top of the page to turn an extension off. Its activities disappear and its connections close.

### Install an extension

Double-click a `.notchext` file, or click **+** at the bottom of the sidebar and choose one. NotchNotch shows what the extension is, who made it and what it asks for before anything is installed.

Only install extensions you trust. An extension's own code can't reach your files or the network, but one that runs a native helper can do anything your account can. The review says when that is the case.

## Privacy

NotchNotch has no account, no analytics and no tracking. Your music, events and extension data stay on your Mac. See the [privacy policy](../../PRIVACY.md).

## Troubleshooting

**macOS says NotchNotch can't be opened.** Use **Open Anyway** as described in [Install](#install).

**Music or Calendar stopped working after an update.** macOS may ask for access again. Reconnect from the extension's **Setup**, and check **System Settings › Privacy & Security › Automation** or **Calendars**.

**An extension stopped.** Its page shows what went wrong. Choose **Restart** there, or **Restart extensions** in the menu bar.

**The notch doesn't show anything.** Check that the extension is turned on and connected in its **Setup**. On a Mac without a notch, NotchNotch uses the top center of the display you choose in **Notch**.

**Still stuck?** [Open an issue](https://github.com/sadeqi-ah/notchnotch/issues).
