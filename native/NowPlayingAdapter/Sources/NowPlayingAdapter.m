// The Now Playing adapter. Since macOS 15.4, MediaRemote answers only Apple's
// own processes, so NotchNotch loads this library into /usr/bin/perl and talks
// to it over pipes:
//
//   stdout  one JSON object per line, sent whenever Now Playing changes:
//           {"type":"state","bundle":…,"title":…,"artist":…,"album":…,
//            "duration":…,"elapsed":…,"timestamp":…,"rate":…,"playing":…,
//            "shuffle":…,"repeat":…,"artwork":"<base64>"?}
//           or {"type":"state","bundle":null} when nothing is playing.
//           "artwork" is present only when the picture changed.
//   stdin   one JSON command per line: {"command":"togglePlayPause"|"next"|
//           "previous"|"seek","value":seconds}
//
// When stdin closes, NotchNotch is gone, and the adapter exits.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include "NowPlayingAdapter.h"

typedef void (*GetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientString)(id);
typedef void (*Register)(dispatch_queue_t);
typedef Boolean (*SendCommand)(int, NSDictionary *);
typedef void (*SetElapsed)(double);

static GetInfo getInfo;
static GetClient getClient;
static ClientString clientBundle, clientParentBundle;
static Register registerNotifications;
static SendCommand sendCommand;
static SetElapsed setElapsedTime;
static NSUInteger lastArtworkHash;
static BOOL emitting, emitAgain;

// MRMediaRemoteCommand values.
enum { CommandTogglePlayPause = 2, CommandNextTrack = 4, CommandPreviousTrack = 5 };

static void writeLine(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id orNull(id value) { return value ?: [NSNull null]; }

static void emit(void);

/// Reads the current item and the app playing it, then writes one line.
/// Notifications come in bursts; one read at a time, and one more if any arrived meanwhile.
static void emit(void) {
    if (emitting) { emitAgain = YES; return; }
    emitting = YES;
    getClient(dispatch_get_main_queue(), ^(id client) {
        NSString *bundle = client && clientBundle ? (__bridge NSString *)clientBundle(client) : nil;
        NSString *parent = client && clientParentBundle ? (__bridge NSString *)clientParentBundle(client) : nil;
        getInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
            NSMutableDictionary *line = [@{ @"type": @"state" } mutableCopy];
            NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
            if (!info.count || !title.length) {
                line[@"bundle"] = [NSNull null];
                lastArtworkHash = 0;
            } else {
                double rate = [info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue];
                NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                line[@"bundle"] = orNull(parent.length ? parent : bundle);
                line[@"title"] = title;
                line[@"artist"] = orNull(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
                line[@"album"] = orNull(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
                line[@"duration"] = orNull(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                line[@"elapsed"] = orNull(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                line[@"timestamp"] = timestamp ? @(timestamp.timeIntervalSince1970) : [NSNull null];
                line[@"rate"] = @(rate);
                line[@"playing"] = rate > 0 ? @YES : @NO;
                line[@"shuffle"] = [info[@"kMRMediaRemoteNowPlayingInfoShuffleMode"] intValue] > 1 ? @YES : @NO;
                line[@"repeat"] = [info[@"kMRMediaRemoteNowPlayingInfoRepeatMode"] intValue] > 1 ? @YES : @NO;
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSUInteger hash = artwork.length ? artwork.hash ^ artwork.length : 0;
                if (hash != lastArtworkHash) {
                    lastArtworkHash = hash;
                    line[@"artwork"] = artwork.length ? [artwork base64EncodedStringWithOptions:0] : @"";
                }
            }
            writeLine(line);
            emitting = NO;
            if (emitAgain) { emitAgain = NO; emit(); }
        });
    });
}

static void perform(NSDictionary *command) {
    NSString *name = command[@"command"];
    if ([name isEqualToString:@"togglePlayPause"]) sendCommand(CommandTogglePlayPause, nil);
    else if ([name isEqualToString:@"next"]) sendCommand(CommandNextTrack, nil);
    else if ([name isEqualToString:@"previous"]) sendCommand(CommandPreviousTrack, nil);
    else if ([name isEqualToString:@"seek"] && [command[@"value"] isKindOfClass:NSNumber.class] && setElapsedTime) {
        setElapsedTime([command[@"value"] doubleValue]);
    }
}

/// Reads commands on a background thread and performs them on the main queue.
static void readCommands(void) {
    [NSThread detachNewThreadWithBlock:^{
        char *buffer = NULL;
        size_t capacity = 0;
        while (getline(&buffer, &capacity, stdin) > 0) {
            NSData *data = [NSData dataWithBytes:buffer length:strlen(buffer)];
            NSDictionary *command = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![command isKindOfClass:NSDictionary.class]) continue;
            dispatch_async(dispatch_get_main_queue(), ^{ perform(command); });
        }
        exit(0);
    }];
}

void notchnotch_now_playing_run(void *perl, void *cv) {
    (void)perl; (void)cv;
    void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    getInfo = (GetInfo)dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
    getClient = (GetClient)dlsym(framework, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (ClientString)dlsym(framework, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = (ClientString)dlsym(framework, "MRNowPlayingClientGetParentAppBundleIdentifier");
    registerNotifications = (Register)dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
    sendCommand = (SendCommand)dlsym(framework, "MRMediaRemoteSendCommand");
    setElapsedTime = (SetElapsed)dlsym(framework, "MRMediaRemoteSetElapsedTime");
    if (!getInfo || !getClient || !registerNotifications || !sendCommand) {
        writeLine(@{ @"type": @"unavailable" });
        exit(1);
    }
    registerNotifications(dispatch_get_main_queue());
    for (NSString *name in @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                              @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification" ]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { (void)note; emit(); }];
    }
    readCommands();
    emit();
    CFRunLoopRun();
}
