# @notchnotch/cli

Builds and checks [NotchNotch](https://github.com/sadeqi-ah/notchnotch) extensions.

```sh
notchnotch build [folder] [--out dist] [--watch]   # bundle src/index.tsx, copy helpers/ and assets/, run build.mjs, check
notchnotch build [folder] --pack                 # also write <id>-<version>.notchext
notchnotch pack <package> [--out file.notchext]  # zip a built package for double-click install
notchnotch check <package>                       # the app's install checks only
```

`@notchnotch/cli/native` exports `helperApp()` to package a native helper as an app bundle with its own privacy usage descriptions, and `codesign()`. See [App connections](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/connections.md).
