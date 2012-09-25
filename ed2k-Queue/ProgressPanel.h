//
//  ProgressPanel.h
//  ed2k-Queue
//
//  Created by gabry on 9/24/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ProgressPanel : NSWindowController

@property (weak) IBOutlet NSTextField *label;
@property (weak) IBOutlet NSProgressIndicator *bar;
- (IBAction)urlStop:(id)sender;
@end
