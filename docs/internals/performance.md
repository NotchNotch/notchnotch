# Performance budget

NotchNotch runs all day, so its idle cost matters more than its peak. These
are the limits for a release build with the notch closed and nothing changing
on screen. `scripts/measure.mjs --budget` checks them.

| | Budget | Measured (0.8) |
| --- | --- | --- |
| App CPU, idle | ≤ 1.0% | 0.4% with 13 extensions |
| App and runners CPU, idle | ≤ 2.0% | 0.4–0.5% |
| App memory | ≤ 60 MB | 27 MB |
| Each runner's memory | ≤ 40 MB | 8–9 MB |
| Idle wakeups, all processes | ≤ 10 a second | under 1 |

Measured on an Apple silicon MacBook with Music, Calendar and the 11 launch
extensions from the Store (GitHub Notifications waiting for setup), as the
median of three 60-second windows.

The runner limits that stop a misbehaving extension (400 MB, 90% of a core
for 30 seconds, 30 messages a second) are separate: those are ceilings for one
extension, not a budget for normal use. See `RunnerResources`.

## Measuring

```sh
node scripts/measure.mjs --runs 3            # the running NotchNotch, median of three minutes
node scripts/measure.mjs --runs 3 --budget   # exits 1 when over budget
```

- Measure a **release** build. A debug build costs several times more, and
  `pnpm dev` adds a rescan of the extension folders every second.
- To measure without touching your own setup, run the built app with its own
  home: `CFFIXED_USER_HOME=/tmp/nnhome dist/NotchNotch.app/Contents/MacOS/NotchNotch`.
  Put built extensions in `/tmp/nnhome/Library/Application Support/NotchNotch/Extensions/`.
- Wait 20 seconds after launch, keep the pointer away from the notch, and take
  the median: an extension's periodic network refresh landing inside one
  window can triple that window's number.
- CPU comes from each process's total CPU time (`ps`), which is exact. `top`'s
  per-sample CPU is too noisy to average; the script uses `top` only for
  memory, energy impact and wakeups.

## What we learned

**Main-thread wakeups cost more than the work they do.** Each runner had its
own one-second timer for liveness and resource checks. The checks themselves
are tiny (`proc_pid_rusage` takes under a microsecond), but every wakeup of
the main run loop runs AppKit's and SwiftUI's observers. With 13 extensions
that was 13 wakeups a second and 2.6% CPU doing almost nothing. One shared
timer that checks every runner, and also looks for `notchnotch dev` projects,
brought it to 0.4%. New periodic work should join that timer, not add one.

A profiler that samples user-space stacks barely shows this cost: almost every
sample is a thread waiting. Compare total CPU time instead.

**Writing the platform state redraws the whole notch.** The model is
`@Observable`, so storing a snapshot that changes nothing visible (a ticking
Settings page) still invalidated `NotchView`. The app now applies a snapshot to
a copy and keeps it only when `PlatformState.presentsSame(as:)` says the notch
would look different. Per-snapshot counters live outside observation.
