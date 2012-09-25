//
//  ProgressPanel.m
//  ed2k-Queue
//
//  Created by gabry on 9/24/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "ProgressPanel.h"

@interface ProgressPanel ()

@end

@implementation ProgressPanel

@synthesize bar, label;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
}


- (IBAction)urlStop:(id)sender {
    NSLog(@"Stopping in progress operation");
    [NSApp endSheet:[self window]];
}
@end
