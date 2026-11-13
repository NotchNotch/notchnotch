# Using NotchNotch

NotchNotch turns the notch on your Mac into a small, quiet place for what's happening now: the song that's playing, your next meeting, a timer, or anything an extension adds.

## Install

NotchNotch needs macOS 14 or later.

1. Download the latest `NotchNotch-<version>.dmg` from [Releases](https://github.com/NotchNotch/notchnotch/releases).
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

When several activities are running, the notch shows one of them and the others as small circles beside it. **Home**, the grid button at the top of the open notch, shows every activity; click one to open it.

**Drag** files, links or text near the notch and it opens to the places that take them, such as Shelf. Let go on one to hand them over.

## Shelf

A place to keep files, links and text for a moment, then send them on. It comes with NotchNotch.

1. Drag anything to the notch and let go on **Shelf**. Shelf opens with what you dropped.
2. Click files to select them: **⌘** adds one, **⇧** adds a range, and clicking a selected file deselects it.
3. Use the buttons at the bottom on the selection, or on every file when nothing is selected: **Remove** or **Clear**, **Copy**, **Open With**, **Quick Look** and **Share** (AirDrop, Messages, Mail and more).
4. Drag files back out to Finder, Mail or any app. Dragging a selected file takes the whole selection; in Home, dragging Shelf's stack takes every file.

Right-click a file for more. Links and text show as rows you can open, copy or drag out.

Shelf remembers where each file is, even after you move or rename it. In Shelf's **Setup**:

- **Keep a copy of dropped files** keeps Shelf's own copy, so a file stays even if you delete the original. Removing it from Shelf deletes the copy.
- **Remove files after dragging them out** empties Shelf as you go.

## Music

Shows what's playing on your Mac, with playback controls: Spotify, Apple Music, your browser, and any other app in macOS's Now Playing. It comes with NotchNotch.

1. Open **Settings & Extensions…** from the menu bar and choose **Music**.
2. In **Setup**, choose **Connect**.
3. Allow Music to see and control what's playing.

If NotchNotch can't read Now Playing on your Mac, Music asks you to connect Spotify or Apple Music one by one instead, and macOS asks before NotchNotch controls each.

## Calendar

Shows your next event with a countdown, and a button to join the meeting. Get it from the **Store**. If you had it before NotchNotch 0.9, it's installed from the Store for you, with your chosen calendars.

1. Open **Settings & Extensions…** and choose **Calendar**.
2. In **Setup**, choose **Connect Calendar**. Allow Calendar to read your calendars, then allow access when macOS asks.
3. Choose which calendars to show.

It uses the accounts already in the Calendar app. NotchNotch only reads your calendars.

## Settings

Open **Settings & Extensions…** from the menu bar, or press **⌘,** while NotchNotch is active.

- **General:** open NotchNotch at login.
- **Notch:** choose the display, and whether the notch opens when you hover over it.
- **About:** version and software updates.

## Extensions

Each extension has a page with these tabs:

- **Setup:** what it needs from you, such as connecting an app or entering an API token. An extension marked **Needs setup** starts once you fill in its required fields and choose **Save**.
- **About:** what it does and what changed in each version, when the extension includes them.
- **Access:** what it can connect to, which access you chose to always allow, and the secrets it saved in your Keychain. **Forget** makes it ask again.
- **Developer:** its console and package details.

Use the switch at the top of the page to turn an extension off. Its activities disappear and its connections close. **Uninstall…** beside it, or in the sidebar's right-click menu, removes the extension with its settings and data. Music goes back to the Store, where you can get it again.

### The Store

**Store** in the sidebar lists extensions that were reviewed before being published. Search or pick a category, open one to see its screenshots and what it can do, and choose **Get**. NotchNotch downloads it, checks it is exactly the package that was reviewed, and shows the same review as any other install before anything is installed.

Install buttons on the NotchNotch website open the extension's page in the Store with a `notchnotch://extensions/<author>/<name>` link. A link only opens the page: installing still takes **Get** and the review.

Extensions you got from the Store update on their own, shortly after NotchNotch opens and every few hours, as long as the new version asks for nothing the installed one couldn't do. An update that wants anything new, such as another website or a setting, waits: the Store shows a badge and lists it under **Updates**, and its review marks what's **New**. Turn off **Update Store extensions automatically** in **General** to review every update yourself. Each automatic update is noted in the extension's console.

The Store's list is signed. NotchNotch refuses a list that isn't signed by NotchNotch, is out of date, or is older than one it has already seen, and a download that differs from what the list describes.

### Install an extension from a file

Double-click a `.notchext` file, or click **+** at the bottom of the sidebar and choose one. Before anything is installed, NotchNotch shows what the extension is, who made it, and what it can do beyond its sandbox, riskiest first. When you update an extension, anything it couldn't do before is marked **New**: look twice at those.

Only install extensions you trust. An extension's own code can't reach your files or the network, but one that runs a native helper can do anything your account can. The review says when that is the case.

## Privacy

NotchNotch has no account, no analytics and no tracking. Your music, events and extension data stay on your Mac. See the [privacy policy](../../PRIVACY.md).

## Troubleshooting

**macOS says NotchNotch can't be opened.** Use **Open Anyway** as described in [Install](#install).

**Music or Calendar stopped working after an update.** macOS may ask for access again. Reconnect from the extension's **Setup**, and check **System Settings › Privacy & Security › Automation** or **Calendars**.

**An extension stopped.** Its page shows what went wrong. Choose **Restart** there, or **Restart extensions** in the menu bar.

**The notch doesn't show anything.** Check that the extension is turned on and connected in its **Setup**. On a Mac without a notch, NotchNotch uses the top center of the display you choose in **Notch**.

**Still stuck?** Choose **General › Problems › Export…**, read the report, save it, and attach it to [a new issue](https://github.com/NotchNotch/notchnotch/issues). The report lists the app and macOS versions, your extensions, recent errors and short summaries of recent crashes, with your home folder and account name removed. NotchNotch never sends it for you.

To keep errors between launches and hear about crashes, turn on **Remember problems between launches**. NotchNotch then keeps up to two weeks of problems in `~/Library/Application Support/NotchNotch/Problems.json` and reads macOS's crash reports for its own processes. Turning it off deletes the file.
