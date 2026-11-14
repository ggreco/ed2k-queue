//
//  AppDelegate.h
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class MainWindow;

// Keys used for the queue entries (dictionaries stored in `urls`).
extern NSString *const kEntryTypeKey;     // "ed2k" or "magnet"
extern NSString *const kEntryFilenameKey;
extern NSString *const kEntrySizeKey;
extern NSString *const kEntryURLKey;
extern NSString *const kEntryIDKey;       // unique id used for de-duplication

extern NSString *const kEntryTypeED2K;
extern NSString *const kEntryTypeMagnet;

// Default remote command used to open magnet links.
extern NSString *const kDefaultMagnetCommand;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    MainWindow *mainWin;
}

@property (strong) NSString *host, *user, *pwd, *command, *port;
// Remote command used to open magnet links (defaults to "open").
@property (strong) NSString *magnetCommand;
@property (strong) NSMutableArray *urls;

// Path of the application support folder / config file.
+ (NSString *)supportFolder;
+ (NSString *)configFile;
// Shell-quote a string so it can be safely passed as a single argument.
+ (NSString *)shellQuote:(NSString *)s;

- (BOOL)valid_cfg;
- (void)load_cfg;
- (void)add_url:(NSString *)s;
- (void)save_all;
// Command to run on the remote machine for a given queue entry.
- (NSString *)commandForEntry:(NSDictionary *)entry;
@end
