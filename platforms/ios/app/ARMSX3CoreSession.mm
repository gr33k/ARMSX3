#import "ARMSX3CoreSession.h"

#import <QuartzCore/CAMetalLayer.h>

#include "RPCS3IOS.h"

namespace
{
NSString* string_from_utf8(const char* value)
{
    if (!value || !value[0])
        return @"";
    return [NSString stringWithUTF8String:value] ?: @"<invalid UTF-8>";
}

NSString* last_core_error(rpcs3_ios_status status)
{
    NSString* detail = string_from_utf8(rpcs3_ios_last_error());
    return detail.length ? detail : [NSString stringWithFormat:@"RPCS3 status %d", status];
}

void core_main_thread_callback(void*, rpcs3_ios_main_thread_task task, void* task_context)
{
    if (!task)
        return;
    if (NSThread.isMainThread)
    {
        task(task_context);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        task(task_context);
    });
}
}

@interface ARMSX3CoreSession ()

@property(atomic, readwrite, getter=isReady) BOOL ready;
@property(atomic, copy, readwrite) NSArray<NSDictionary<NSString*, id>*>* games;
@property(atomic, copy, readwrite) NSArray<NSDictionary<NSString*, id>*>* netISOGames;

- (void)emit:(NSString*)line;
- (void)emitCoreLevel:(int32_t)level message:(NSString*)message;

@end

static void core_log_callback(void* user_context, int32_t level, const char* message)
{
    ARMSX3CoreSession* session = (__bridge ARMSX3CoreSession*)user_context;
    [session emitCoreLevel:level message:string_from_utf8(message)];
}

static void install_progress_callback(void* user_context, uint32_t completed, uint32_t total, const char* stage)
{
    NSDictionary* context = (__bridge NSDictionary*)user_context;
    ARMSX3CoreProgressHandler progress = context[@"progress"];
    if (!progress)
        return;
    const double fraction = total ? static_cast<double>(completed) / static_cast<double>(total) : -1.0;
    NSString* stage_string = string_from_utf8(stage);
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(fraction, stage_string);
    });
}

static void game_enumeration_callback(void* user_context, const rpcs3_ios_game_info* game)
{
    if (!game)
        return;
    NSMutableArray* games = (__bridge NSMutableArray*)user_context;
    [games addObject:@{
        @"titleID": string_from_utf8(game->title_id),
        @"title": string_from_utf8(game->title),
        @"version": string_from_utf8(game->version),
        @"path": string_from_utf8(game->path),
        @"bootable": @(game->bootable != 0),
        @"size": @(game->size_on_disk),
        @"remote": @NO,
    }];
}

static void netiso_game_enumeration_callback(void* user_context, const rpcs3_ios_netiso_game_info* game)
{
    if (!game)
        return;
    NSMutableArray* games = (__bridge NSMutableArray*)user_context;
    const BOOL folder = game->kind == RPCS3_IOS_NETISO_GAME_EXTRACTED_FOLDER;
    [games addObject:@{
        @"titleID": @"NETISO",
        @"title": string_from_utf8(game->display_name),
        @"version": folder ? @"NAS folder" : @"NAS ISO",
        @"path": string_from_utf8(game->remote_path),
        @"bootable": @YES,
        @"size": @(game->size),
        @"remote": @YES,
    }];
}

@implementation ARMSX3CoreSession
{
    dispatch_queue_t _coreQueue;
    dispatch_queue_t _controlQueue;
    dispatch_queue_t _diagnosticQueue;
    NSURL* _diagnosticLogURL;
    ARMSX3CoreLogHandler _logHandler;
    NSLock* _verboseLogLock;
    NSString* _latestVerboseLog;
    NSUInteger _suppressedVerboseLogCount;
    BOOL _verboseLogFlushScheduled;
    uint64_t _lastNetISOBytes;
    CFAbsoluteTime _lastNetISOSample;
    double _netISOMegabitsPerSecond;
}

- (instancetype)initWithLogHandler:(ARMSX3CoreLogHandler)logHandler
{
    self = [super init];
    if (self)
    {
        _coreQueue = dispatch_queue_create("com.thec0de.armsx3ios.core", DISPATCH_QUEUE_SERIAL);
        _controlQueue = dispatch_queue_create("com.thec0de.armsx3ios.control", DISPATCH_QUEUE_SERIAL);
        _diagnosticQueue = dispatch_queue_create("com.thec0de.armsx3ios.diagnostics", DISPATCH_QUEUE_SERIAL);
        _logHandler = [logHandler copy];
        _verboseLogLock = [[NSLock alloc] init];
        _games = @[];
        _netISOGames = @[];
        NSURL* documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                                 inDomains:NSUserDomainMask].firstObject;
        _diagnosticLogURL = [documents URLByAppendingPathComponent:@"ARMSX3-last-session.log"];
        NSString* header = [NSString stringWithFormat:@"ARMSX3 diagnostic session %.3f\n",
            NSDate.date.timeIntervalSince1970];
        [header writeToURL:_diagnosticLogURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return self;
}

- (void)writeDiagnosticLine:(NSString*)line
{
    if (!line.length || !_diagnosticLogURL)
        return;
    NSURL* url = _diagnosticLogURL;
    NSString* record = [NSString stringWithFormat:@"%.3f %@\n",
        NSDate.date.timeIntervalSince1970, line];
    dispatch_async(_diagnosticQueue, ^{
        NSData* data = [record dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:url.path];
        if (!handle)
        {
            [data writeToURL:url atomically:YES];
            return;
        }
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    });
}

- (void)emitCoreLevel:(int32_t)level message:(NSString*)message
{
    NSString* line = [NSString stringWithFormat:@"[Core:%d] %@", level, message];
    if (level < 5)
    {
        [self emit:line];
        return;
    }

    static NSArray<NSString*>* high_priority_fragments;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        high_priority_fragments = @[
            @"thread terminated due to fatal error",
            @"fatal error",
            @"ppu trap",
            @"compiled all ppu",
            @"linking ppu modules",
        ];
    });
    for (NSString* fragment in high_priority_fragments)
    {
        if ([message rangeOfString:fragment options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
            [self emit:line];
            return;
        }
    }

    // RPCS3 emits thousands of notice/trace lines per second in demanding
    // titles. Keep diagnostics available without flooding UIKit's main queue.
    [_verboseLogLock lock];
    _latestVerboseLog = line;
    _suppressedVerboseLogCount += 1;
    const BOOL should_schedule = !_verboseLogFlushScheduled;
    _verboseLogFlushScheduled = YES;
    [_verboseLogLock unlock];
    if (!should_schedule)
        return;

    __weak ARMSX3CoreSession* weak_self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        ARMSX3CoreSession* strong_self = weak_self;
        if (!strong_self)
            return;

        [strong_self->_verboseLogLock lock];
        NSString* latest = strong_self->_latestVerboseLog;
        const NSUInteger count = strong_self->_suppressedVerboseLogCount;
        strong_self->_latestVerboseLog = nil;
        strong_self->_suppressedVerboseLogCount = 0;
        strong_self->_verboseLogFlushScheduled = NO;
        [strong_self->_verboseLogLock unlock];

        if (!latest.length || !strong_self->_logHandler)
            return;
        NSString* summary = count > 1
            ? [NSString stringWithFormat:@"[Diagnostics] Coalesced %lu verbose core lines | %@",
                (unsigned long)count, latest]
            : latest;
        NSLog(@"[ARMSX3 iOS] %@", summary);
        strong_self->_logHandler(summary);
    });
}

- (void)emit:(NSString*)line
{
    NSLog(@"[ARMSX3 iOS] %@", line);
    [self writeDiagnosticLine:line];
    if (!_logHandler)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_logHandler(line);
    });
}

- (void)finish:(ARMSX3CoreCompletion)completion succeeded:(BOOL)succeeded message:(NSString*)message
{
    [self writeDiagnosticLine:[NSString stringWithFormat:@"[Operation %@] %@",
        succeeded ? @"PASS" : @"FAIL", message ?: @"No detail"]];
    if (!completion)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(succeeded, message);
    });
}

- (void)initializeWithCompletion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        @autoreleasepool
        {
            if (rpcs3_ios_abi_version() != RPCS3_IOS_ABI_VERSION)
            {
                [self finish:completion succeeded:NO message:@"RPCS3Core ABI mismatch"];
                return;
            }

            NSFileManager* manager = NSFileManager.defaultManager;
            NSURL* support = [[manager URLsForDirectory:NSApplicationSupportDirectory
                                               inDomains:NSUserDomainMask].firstObject
                URLByAppendingPathComponent:@"ARMSX3Core" isDirectory:YES];
            NSURL* cache = [[manager URLsForDirectory:NSCachesDirectory
                                             inDomains:NSUserDomainMask].firstObject
                URLByAppendingPathComponent:@"ARMSX3Core" isDirectory:YES];
            NSError* directory_error = nil;
            if (![manager createDirectoryAtURL:support withIntermediateDirectories:YES attributes:nil error:&directory_error] ||
                ![manager createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:&directory_error])
            {
                [self finish:completion succeeded:NO message:directory_error.localizedDescription ?: @"Cannot create RPCS3 sandbox directories"];
                return;
            }

            rpcs3_ios_config config{};
            config.abi_version = RPCS3_IOS_ABI_VERSION;
            config.struct_size = sizeof(config);
            config.application_support_path = support.fileSystemRepresentation;
            config.cache_path = cache.fileSystemRepresentation;
            config.log_callback = core_log_callback;
            config.main_thread_callback = core_main_thread_callback;
            config.user_context = (__bridge void*)self;

            [self emit:[NSString stringWithFormat:@"Core build: %@", string_from_utf8(rpcs3_ios_build_info())]];
            const rpcs3_ios_status status = rpcs3_ios_initialize(&config);
            if (status != RPCS3_IOS_OK)
            {
                [self finish:completion succeeded:NO message:last_core_error(status)];
                return;
            }
            self.ready = YES;

            uint64_t output = 0;
            const rpcs3_ios_status jit_status = rpcs3_ios_run_llvm_self_test(42, &output);
            if (jit_status != RPCS3_IOS_OK || output != 133)
            {
                [self finish:completion succeeded:NO message:last_core_error(jit_status)];
                return;
            }

            rpcs3_ios_pad_state pad{};
            pad.struct_size = sizeof(pad);
            pad.connected = 1;
            rpcs3_ios_set_pad_state(0, &pad);

            NSString* firmware = string_from_utf8(rpcs3_ios_firmware_version());
            NSString* message = firmware.length
                ? [NSString stringWithFormat:@"Core + LLVM JIT PASS | firmware %@", firmware]
                : @"Core + LLVM JIT PASS | install PS3 firmware next";
            [self finish:completion succeeded:YES message:message];
        }
    });
}

- (void)updateDisplayLayer:(CAMetalLayer*)layer refreshRate:(float)refreshRate
{
    if (!self.isReady || !layer)
        return;
    const CGSize size = layer.drawableSize;
    if (size.width < 1.0 || size.height < 1.0)
        return;

    rpcs3_ios_display_surface surface{};
    surface.struct_size = sizeof(surface);
    surface.width = static_cast<uint32_t>(llround(size.width));
    surface.height = static_cast<uint32_t>(llround(size.height));
    surface.refresh_rate = refreshRate;
    surface.metal_layer = (__bridge void*)layer;
    const rpcs3_ios_status status = rpcs3_ios_set_display_surface(&surface);
    if (status != RPCS3_IOS_OK)
        [self emit:[NSString stringWithFormat:@"[Display] %@", last_core_error(status)]];
}

- (void)installURL:(NSURL*)url
       asFirmware:(BOOL)firmware
          progress:(ARMSX3CoreProgressHandler)progress
        completion:(ARMSX3CoreCompletion)completion
{
    const BOOL security_scoped = [url startAccessingSecurityScopedResource];
    dispatch_async(_coreQueue, ^{
        @autoreleasepool
        {
            NSDictionary* progress_context = @{ @"progress": progress ?: ^(double, NSString*) {} };
            rpcs3_ios_status status = RPCS3_IOS_INVALID_ARGUMENT;
            NSString* extension = url.pathExtension.lowercaseString;
            NSNumber* directory = nil;
            [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
            const char* path = url.fileSystemRepresentation;

            if (firmware)
                status = rpcs3_ios_install_firmware(path, install_progress_callback, (__bridge void*)progress_context);
            else if (directory.boolValue)
                status = rpcs3_ios_install_folder(path, install_progress_callback, (__bridge void*)progress_context);
            else if ([extension isEqualToString:@"iso"])
                status = rpcs3_ios_install_iso(path, nullptr, install_progress_callback, (__bridge void*)progress_context);
            else if ([extension isEqualToString:@"zip"])
                status = rpcs3_ios_install_zip(path, install_progress_callback, (__bridge void*)progress_context);
            else if ([extension isEqualToString:@"pkg"])
                status = rpcs3_ios_install_package(path, install_progress_callback, (__bridge void*)progress_context);
            else if ([extension isEqualToString:@"rap"])
                status = rpcs3_ios_install_rap(path);

            NSString* message = status == RPCS3_IOS_OK
                ? (firmware ? [NSString stringWithFormat:@"Firmware installed: %@", string_from_utf8(rpcs3_ios_firmware_version())]
                            : [NSString stringWithFormat:@"Imported %@", url.lastPathComponent])
                : last_core_error(status);
            if (security_scoped)
                [url stopAccessingSecurityScopedResource];
            [self finish:completion succeeded:status == RPCS3_IOS_OK message:message];
        }
    });
}

- (void)refreshGamesWithCompletion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        @autoreleasepool
        {
            NSMutableArray* games = [NSMutableArray array];
            const rpcs3_ios_status status = rpcs3_ios_enumerate_games(
                game_enumeration_callback, (__bridge void*)games);
            if (status != RPCS3_IOS_OK)
            {
                [self finish:completion succeeded:NO message:last_core_error(status)];
                return;
            }
            [games sortUsingComparator:^NSComparisonResult(NSDictionary* left, NSDictionary* right) {
                return [left[@"title"] localizedCaseInsensitiveCompare:right[@"title"]];
            }];
            self.games = games;
            [self finish:completion succeeded:YES
                message:[NSString stringWithFormat:@"%lu installed title%@", (unsigned long)games.count, games.count == 1 ? @"" : @"s"]];
        }
    });
}

- (void)connectNetISOHost:(NSString*)host
                     port:(uint16_t)port
               completion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        @autoreleasepool
        {
            const rpcs3_ios_status connect_status = rpcs3_ios_netiso_connect(host.UTF8String, port);
            if (connect_status != RPCS3_IOS_OK)
            {
                [self finish:completion succeeded:NO message:last_core_error(connect_status)];
                return;
            }

            NSMutableArray* games = [NSMutableArray array];
            const rpcs3_ios_status enumerate_status = rpcs3_ios_enumerate_netiso_games(
                netiso_game_enumeration_callback, (__bridge void*)games);
            if (enumerate_status != RPCS3_IOS_OK)
            {
                [self finish:completion succeeded:NO message:last_core_error(enumerate_status)];
                return;
            }
            [games sortUsingComparator:^NSComparisonResult(NSDictionary* left, NSDictionary* right) {
                return [left[@"title"] localizedCaseInsensitiveCompare:right[@"title"]];
            }];
            self.netISOGames = games;
            self->_lastNetISOBytes = 0;
            self->_lastNetISOSample = CFAbsoluteTimeGetCurrent();
            self->_netISOMegabitsPerSecond = 0.0;
            [self finish:completion succeeded:YES
                message:[NSString stringWithFormat:@"NETISO connected | %lu streamed title%@",
                    (unsigned long)games.count, games.count == 1 ? @"" : @"s"]];
        }
    });
}

- (void)runJITSelfTestWithCompletion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        uint64_t output = 0;
        const rpcs3_ios_status status = rpcs3_ios_run_llvm_self_test(42, &output);
        const BOOL passed = status == RPCS3_IOS_OK && output == 133;
        [self finish:completion succeeded:passed
            message:passed ? @"LLVM JIT PASS: 42 * 3 + 7 = 133" : last_core_error(status)];
    });
}

- (void)bootTitleID:(NSString*)titleID completion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        const rpcs3_ios_status status = rpcs3_ios_boot_game(titleID.UTF8String);
        [self finish:completion succeeded:status == RPCS3_IOS_OK
            message:status == RPCS3_IOS_OK ? [NSString stringWithFormat:@"Boot request completed: %@", titleID] : last_core_error(status)];
    });
}

- (void)bootNetISOPath:(NSString*)remotePath completion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        const rpcs3_ios_status status = rpcs3_ios_boot_netiso_game(remotePath.UTF8String);
        [self finish:completion succeeded:status == RPCS3_IOS_OK
            message:status == RPCS3_IOS_OK
                ? [NSString stringWithFormat:@"NETISO boot request completed: %@", remotePath.lastPathComponent]
                : last_core_error(status)];
    });
}

- (void)bootXMBWithCompletion:(ARMSX3CoreCompletion)completion
{
    dispatch_async(_coreQueue, ^{
        const rpcs3_ios_status status = rpcs3_ios_boot_vsh();
        [self finish:completion succeeded:status == RPCS3_IOS_OK
            message:status == RPCS3_IOS_OK ? @"PS3 XMB boot request completed" : last_core_error(status)];
    });
}

- (void)stopWithCompletion:(ARMSX3CoreCompletion)completion
{
    // Stop cannot share the boot queue: BootGame remains synchronous while PPU
    // modules are prepared, which previously made cancellation unreachable.
    dispatch_async(_controlQueue, ^{
        const rpcs3_ios_status status = rpcs3_ios_stop_emulation();
        [self finish:completion succeeded:status == RPCS3_IOS_OK
            message:status == RPCS3_IOS_OK ? @"Stop requested; core cleanup continues in the background" : last_core_error(status)];
    });
}

- (BOOL)updatePadConnected:(BOOL)connected
                   buttons:(uint64_t)buttons
                     leftX:(float)leftX
                     leftY:(float)leftY
                    rightX:(float)rightX
                    rightY:(float)rightY
               leftTrigger:(float)leftTrigger
              rightTrigger:(float)rightTrigger
{
    if (!self.isReady)
        return NO;
    rpcs3_ios_pad_state pad{};
    pad.struct_size = sizeof(pad);
    pad.connected = connected ? 1u : 0u;
    pad.buttons = buttons;
    pad.left_stick_x = leftX;
    pad.left_stick_y = leftY;
    pad.right_stick_x = rightX;
    pad.right_stick_y = rightY;
    pad.left_trigger = leftTrigger;
    pad.right_trigger = rightTrigger;
    return rpcs3_ios_set_pad_state(0, &pad) == RPCS3_IOS_OK;
}

- (NSString*)runtimeStatus
{
    if (!self.isReady)
        return @"Core not ready";

    const rpcs3_ios_emulation_state state = rpcs3_ios_get_emulation_state();
    uint32_t completed = 0;
    uint32_t total = 0;
    char stage[192]{};
    rpcs3_ios_get_boot_progress(&completed, &total, stage, sizeof(stage));

    rpcs3_ios_performance_metrics metrics{};
    metrics.struct_size = sizeof(metrics);
    rpcs3_ios_get_performance_metrics(&metrics);
    NSString* state_name = @"unknown";
    switch (state)
    {
    case RPCS3_IOS_EMULATION_STATE_STOPPED: state_name = @"stopped"; break;
    case RPCS3_IOS_EMULATION_STATE_LOADING: state_name = @"loading"; break;
    case RPCS3_IOS_EMULATION_STATE_READY: state_name = @"ready"; break;
    case RPCS3_IOS_EMULATION_STATE_STARTING: state_name = @"starting"; break;
    case RPCS3_IOS_EMULATION_STATE_RUNNING: state_name = @"running"; break;
    case RPCS3_IOS_EMULATION_STATE_PAUSED: state_name = @"paused"; break;
    case RPCS3_IOS_EMULATION_STATE_STOPPING: state_name = @"stopping"; break;
    default: break;
    }

    NSMutableString* result = [NSMutableString stringWithFormat:@"%@", state_name];
    if (stage[0])
    {
        if (total)
            [result appendFormat:@" | %u%% %@", (completed * 100u) / total, string_from_utf8(stage)];
        else
            [result appendFormat:@" | %@", string_from_utf8(stage)];
    }
    if (metrics.valid_fields & RPCS3_IOS_PERFORMANCE_FPS_VALID)
        [result appendFormat:@" | %.1f FPS", metrics.frames_per_second];
    if (metrics.valid_fields & RPCS3_IOS_PERFORMANCE_MEMORY_VALID)
        [result appendFormat:@" | %.0f MiB", metrics.memory_used_bytes / (1024.0 * 1024.0)];

    rpcs3_ios_netiso_metrics netiso{};
    netiso.struct_size = sizeof(netiso);
    if (rpcs3_ios_get_netiso_metrics(&netiso) == RPCS3_IOS_OK && netiso.remote_bytes)
    {
        const CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        const CFAbsoluteTime elapsed = now - _lastNetISOSample;
        if (_lastNetISOSample > 0.0 && elapsed > 0.20 && netiso.remote_bytes >= _lastNetISOBytes)
        {
            _netISOMegabitsPerSecond = ((netiso.remote_bytes - _lastNetISOBytes) * 8.0) / (elapsed * 1000000.0);
            _lastNetISOBytes = netiso.remote_bytes;
            _lastNetISOSample = now;
        }
        [result appendFormat:@" | NET %.1f Mbps %.0f MiB R%llu",
            _netISOMegabitsPerSecond,
            netiso.remote_bytes / (1024.0 * 1024.0),
            (unsigned long long)netiso.reconnects];
    }
    return result;
}

@end
