# @notchnotch/cli

Builds and checks [NotchNotch](https://github.com/NotchNotch/notchnotch) extensions.

```sh
notchnotch dev [folder]                          # run it in NotchNotch, reload on save, print its console
notchnotch build [folder] [--out dist] [--watch]   # bundle src/index.tsx, copy helpers/ and assets/, run build.mjs, check
notchnotch build [folder] --pack                 # also write <id>-<version>.notchext
notchnotch pack <package> [--out file.notchext]  # zip a built package for double-click install
notchnotch check <package>                       # the app's install checks only
notchnotch lint [folder]                         # store guidelines: icon, title, description, README…
notchnotch screenshot [folder]                   # Store screenshots of the running extension into metadata/
notchnotch publish [folder] [--dry-run]          # open or update a Store pull request (needs gh auth login)
```

`@notchnotch/cli/native` exports `helperApp()` to package a native helper as an app bundle with its own privacy usage descriptions, and `codesign()`. See [Native helpers](https://github.com/NotchNotch/notchnotch/blob/main/docs/extensions/native-helpers.md).
