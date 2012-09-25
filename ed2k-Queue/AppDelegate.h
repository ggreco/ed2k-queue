//
//  AppDelegate.h
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class MainWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    MainWindow *mainWin;
}

@property (strong) NSString *host, *user, *pwd, *command, *port;
@property (strong) NSMutableArray *urls;

- (BOOL)valid_cfg;
-(void)load_cfg;
-(void)add_url:(NSString*)s;
-(void)save_all;
@end

