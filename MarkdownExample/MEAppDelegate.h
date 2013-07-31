//
//  MEAppDelegate.h
//  MarkdownExample
//
//  Created by Ben Syverson on 2013/7/31.
//  Copyright (c) 2013 Ben Syverson. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "OSMarkdown.h"

@interface MEAppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate>
{
	IBOutlet NSTextView *textView;
	IBOutlet WebView *webView;
	int changeCounter;
}

@property (assign) IBOutlet NSWindow *window;

@end
