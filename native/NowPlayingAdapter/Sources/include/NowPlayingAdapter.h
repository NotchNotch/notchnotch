#pragma once

/// Runs the Now Playing adapter until standard input closes. NotchNotch starts
/// it inside /usr/bin/perl, which macOS lets read MediaRemote, and perl calls
/// it as an XSUB; both arguments are perl's and unused.
void notchnotch_now_playing_run(void *perl, void *cv);
