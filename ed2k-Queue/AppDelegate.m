//
//  AppDelegate.m
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "AppDelegate.h"
#import "nsextensions.h"
#import "MainWindow.h"

NSString *const kEntryTypeKey = @"type";
NSString *const kEntryFilenameKey = @"filename";
NSString *const kEntrySizeKey = @"size";
NSString *const kEntryURLKey = @"url";
NSString *const kEntryIDKey = @"id";

NSString *const kEntryTypeED2K = @"ed2k";
NSString *const kEntryTypeMagnet = @"magnet";

NSString *const kDefaultMagnetCommand = @"open";

static NSString *const kPwdKey = @"ed2k-pwd";

static BOOL nonEmpty(NSString *s)
{
    return [s isKindOfClass:[NSString class]] && [s length] > 0;
}

@implementation AppDelegate

@synthesize urls, host, port, command, user, pwd, magnetCommand;

+ (NSString *)supportFolder
{
    return [@"~/Library/Application Support/ed2kQueue" stringByExpandingTildeInPath];
}

+ (NSString *)configFile
{
    return [[self supportFolder] stringByAppendingPathComponent:@"config"];
}

+ (NSString *)dbFile
{
    return [[self supportFolder] stringByAppendingPathComponent:@"db"];
}

+ (NSString *)shellQuote:(NSString *)s
{
    // Wrap in single quotes, escaping embedded single quotes as '\''
    NSString *escaped = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

-(id)init
{
    self = [super init];

    if (self) {
        // loading db & config
        [self load_cfg];
        [self load_db];
    }
    return self;
}

-(void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // creo la finestra principale
    mainWin = [[MainWindow alloc] initWithWindowNibName:@"MainWindow"];
    mainWin.delegate = self;
    [mainWin showWindow:nil];
    [[mainWin window] makeMainWindow];
    [mainWin refresh];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

// Modern replacement for the kAEGetURL Apple Event handler: receives the
// ed2k:// and magnet: links opened by browsers / other apps.
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)openedURLs
{
    for (NSURL *u in openedURLs) {
        NSLog(@"URL from open event: %@", u);
        [self add_url:[u absoluteString]];
    }
}

-(BOOL)valid_cfg
{
    if (!nonEmpty(host) || !nonEmpty(user) || !nonEmpty(port) || !nonEmpty(pwd))
        return NO;

    // Every queued link must have a usable remote command.
    for (NSDictionary *d in urls) {
        if (!nonEmpty([self commandForEntry:d]))
            return NO;
    }
    return YES;
}

-(void)load_cfg
{
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:[AppDelegate configFile]];

    host = [dict objectForKey:@"host"];
    port = [dict objectForKey:@"port"];
    command = [dict objectForKey:@"command"];
    magnetCommand = [dict objectForKey:@"magnet_command"];
    user = [dict objectForKey:@"user"];
    NSString *enc = [dict objectForKey:@"pwd"];
    pwd = nonEmpty(enc) ? [enc decrypt:kPwdKey] : nil;

    if (!nonEmpty(magnetCommand))
        magnetCommand = kDefaultMagnetCommand;
}

- (void)load_db
{
    NSArray *stored = [NSArray arrayWithContentsOfFile:[AppDelegate dbFile]];
    urls = [[NSMutableArray alloc] init];

    // Migrate entries saved by older versions (ed2k only, no type/id).
    for (NSDictionary *d in stored) {
        if (![d isKindOfClass:[NSDictionary class]])
            continue;
        NSMutableDictionary *m = [d mutableCopy];
        if (![m objectForKey:kEntryTypeKey] || ![m objectForKey:kEntryIDKey]) {
            NSDictionary *parsed = [self parseED2K:[m objectForKey:kEntryURLKey]];
            if (parsed)
                [m addEntriesFromDictionary:parsed];
            else {
                [m setObject:kEntryTypeED2K forKey:kEntryTypeKey];
                [m setObject:[m objectForKey:kEntryFilenameKey] ?: @"" forKey:kEntryIDKey];
            }
        }
        [urls addObject:m];
    }
}

- (NSString *)commandForEntry:(NSDictionary *)entry
{
    if ([[entry objectForKey:kEntryTypeKey] isEqualToString:kEntryTypeMagnet])
        return nonEmpty(magnetCommand) ? magnetCommand : kDefaultMagnetCommand;
    return command;
}

#pragma mark - Link parsing

// ed2k://|file|<name>|<size>|<md4 hash>|...|/
- (NSDictionary *)parseED2K:(NSString *)url
{
    if (![url isKindOfClass:[NSString class]])
        return nil;
    NSString *decoded = [url stringByRemovingPercentEncoding] ?: url;
    NSArray *purl = [decoded componentsSeparatedByString:@"|"];

    if ([purl count] < 4 || ![[purl objectAtIndex:1] isEqualToString:@"file"])
        return nil;

    NSString *filename = [purl objectAtIndex:2];
    NSString *size = [purl objectAtIndex:3];
    NSString *uid = ([purl count] > 4 && [[purl objectAtIndex:4] length] > 0)
        ? [[purl objectAtIndex:4] lowercaseString] : filename;

    return @{ kEntryTypeKey: kEntryTypeED2K,
              kEntryFilenameKey: filename,
              kEntrySizeKey: size,
              kEntryURLKey: url,
              kEntryIDKey: [@"ed2k:" stringByAppendingString:uid] };
}

static NSString *decodeQueryValue(NSString *v)
{
    // Magnet links frequently encode spaces as '+'.
    v = [v stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    return [v stringByRemovingPercentEncoding] ?: v;
}

// magnet:?xt=urn:btih:<hash>&dn=<name>&xl=<size>&tr=...
- (NSDictionary *)parseMagnet:(NSString *)url
{
    NSRange q = [url rangeOfString:@"?"];
    if (q.location == NSNotFound)
        return nil;

    NSString *xt = nil, *dn = nil, *xl = nil;
    NSString *query = [url substringFromIndex:NSMaxRange(q)];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location == NSNotFound)
            continue;
        NSString *k = [[pair substringToIndex:eq.location] lowercaseString];
        NSString *v = decodeQueryValue([pair substringFromIndex:NSMaxRange(eq)]);
        // Keep only the first occurrence (xt.1, xt.2... are ignored for the id).
        if ([k isEqualToString:@"xt"] && !xt)
            xt = v;
        else if ([k isEqualToString:@"dn"] && !dn)
            dn = v;
        else if ([k isEqualToString:@"xl"] && !xl)
            xl = v;
    }

    // A magnet without an exact topic cannot be downloaded.
    if (!nonEmpty(xt))
        return nil;

    NSString *uid = [xt lowercaseString];
    NSString *name = nonEmpty(dn) ? dn : xt;
    NSString *size = nonEmpty(xl) ? xl : @"";

    return @{ kEntryTypeKey: kEntryTypeMagnet,
              kEntryFilenameKey: name,
              kEntrySizeKey: size,
              kEntryURLKey: url,
              kEntryIDKey: [@"magnet:" stringByAppendingString:uid] };
}

-(void)add_url:(NSString*)url
{
    if (![url isKindOfClass:[NSString class]])
        return;

    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSDictionary *entry = nil;
    NSString *lower = [url lowercaseString];
    if ([lower hasPrefix:@"ed2k:"])
        entry = [self parseED2K:url];
    else if ([lower hasPrefix:@"magnet:"])
        entry = [self parseMagnet:url];

    if (!entry) {
        NSLog(@"Ignored unsupported URL string %@", url);
        return;
    }

    NSString *uid = [entry objectForKey:kEntryIDKey];
    for (NSDictionary *d in urls) {
        if ([uid isEqualToString:[d objectForKey:kEntryIDKey]] ||
            [url isEqualToString:[d objectForKey:kEntryURLKey]]) {
            NSLog(@"Ignoring already present entry %@", [entry objectForKey:kEntryFilenameKey]);
            return;
        }
    }

    NSLog(@"Adding %@ item %@", [entry objectForKey:kEntryTypeKey], [entry objectForKey:kEntryFilenameKey]);
    [urls addObject:[entry mutableCopy]];
    [mainWin refresh];
}

#pragma mark - Persistence

-(void)save_all
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *folder = [AppDelegate supportFolder];

    if (![fileManager fileExistsAtPath:folder])
        [fileManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];

    NSLog(@"Writing %lu records to db", (unsigned long)[urls count]);
    [urls writeToFile:[AppDelegate dbFile] atomically:YES];

    // Note: the prefs window writes the config file itself; here we only
    // re-save it to keep it in sync, skipping nil values (which would make
    // dictionaryWithObjectsAndKeys: stop early and lose data).
    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    if (host) [config setObject:host forKey:@"host"];
    if (port) [config setObject:port forKey:@"port"];
    if (command) [config setObject:command forKey:@"command"];
    if (magnetCommand) [config setObject:magnetCommand forKey:@"magnet_command"];
    if (user) [config setObject:user forKey:@"user"];
    if (pwd) [config setObject:[pwd encrypt:kPwdKey] forKey:@"pwd"];
    if ([config count] > 0)
        [config writeToFile:[AppDelegate configFile] atomically:YES];
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

-(void)applicationWillResignActive:(NSNotification *)notification
{
    [self save_all];
}

-(void)applicationWillTerminate:(NSNotification *)notification
{
    [self save_all];
}

- (IBAction)submit_action:(id)sender {
    NSLog(@"Received action from: %@", sender);

    if (([sender respondsToSelector:@selector(identifier)] && [[sender identifier] isEqualToString:@"submit"]) ||
        ([sender respondsToSelector:@selector(itemIdentifier)] && [[sender itemIdentifier] isEqualToString:@"submit"]))
    {
        [mainWin send_urls];
    }
    else
        [mainWin open_prefs];
}

@end
