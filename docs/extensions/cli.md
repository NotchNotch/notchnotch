# CLI

`@notchnotch/cli` builds, runs, checks and publishes extensions. A project made with `npm create notchnotch-extension` has it already, with these scripts:

| Script | Runs |
| --- | --- |
| `npm run dev` | `notchnotch dev` |
| `npm run build` | `notchnotch build . --out dist` |
| `npm run watch` | `notchnotch build . --out dist --watch` |
| `npm run pack` | `notchnotch build . --out dist --pack` |
| `npm run check` | `notchnotch check dist` |
| `npm run lint` | `notchnotch lint .` |

Run any command with `npx notchnotch <command>`. `folder` is your project and defaults to the current folder; `package` is a built one, such as `dist`. A command that finds a problem prints it and exits with status 1.

## dev

```sh
notchnotch dev [folder] [--out <dir>]
```

Builds the extension and runs it in the NotchNotch that's open on this Mac, marked **Development**. It rebuilds and reloads on every save, and prints the extension's console output. Press Ctrl+C to stop; the extension leaves the notch.

If NotchNotch isn't open, open it: the extension loads within a second. Every NotchNotch open on the Mac picks it up, so quit any other copy first.

## build

```sh
notchnotch build [folder] [--out <dir>] [--watch] [--pack]
```

Makes an installable package in `--out` (default `<folder>/dist`):

1. Runs `build.mjs` from your project if there is one, for a [native helper](native-helpers.md).
2. Copies `notchnotch.json`, `README.md`, `CHANGELOG.md`, `helpers/` and `assets/`.
3. Bundles `src/index.tsx` into `bundle.js`, with a source map.
4. Runs the install checks, as `check` does.

It replaces the output folder only if it holds a previous build, never another folder. `--watch` keeps rebuilding on change and skips the checks. `--pack` also writes a `.notchext`, as `pack` does.

Install the build from **Settings & Extensions**: click **+** at the bottom of the sidebar and choose the folder.

## pack

```sh
notchnotch pack [package] [--out <file.notchext>]
```

Zips a built package into `<id>-<version>.notchext`, next to the package folder by default. Double-clicking it opens NotchNotch's install review, so it's the way to share an extension outside the Store. It runs the install checks first and refuses a package that fails them.

## check

```sh
notchnotch check [package]
```

Checks a built package against the rules NotchNotch applies when installing: the manifest, permissions, file types and sizes (see [What NotchNotch checks](publishing.md#what-notchnotch-checks)). A package that passes installs.

## lint

```sh
notchnotch lint [folder]
```

Checks the [Store guidelines](publishing.md), which `check` doesn't: a title-case name, a one-sentence description, your own id prefix, `author`, `categories`, `license`, your own icon, a README and a CHANGELOG without the template's placeholders, and screenshots of the right size. These are warnings: the app installs the extension either way, but the Store needs them fixed.

## screenshot

```sh
notchnotch screenshot [folder]
```

Draws each activity and prompt the extension shows now, expanded in the notch, into `metadata/1.png`, `2.png`… for the Store: up to six, at 2000×1250 on the same wallpaper every Store screenshot has. It replaces the numbered screenshots already there.

Run it while `notchnotch dev` runs the extension, after putting it in the state you want to show, such as a timer running. It draws offscreen, so it needs no Screen Recording permission and shows nothing else on your screen.

## publish

```sh
notchnotch publish [folder] [--dry-run]
```

Opens a pull request that adds the extension to the [Store](publishing.md#publish-to-the-store), or updates the one already open. It runs `lint` and the install checks, copies your source to `extensions/<author>/<name>/` on a fork of the Store repository, and opens the pull request from it. `--dry-run` shows what would be submitted and sends nothing.

It uses the [GitHub CLI](https://cli.github.com): run `gh auth login` once. No token passes through NotchNotch.

## Native helpers

`@notchnotch/cli/native` exports `helperApp()`, which packages a native helper as an app bundle with its own privacy descriptions, and `codesign()`. Call them from `build.mjs`; see [Native helpers](native-helpers.md).
