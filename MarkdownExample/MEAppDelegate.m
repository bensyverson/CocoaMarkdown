//
//  MEAppDelegate.m
//  MarkdownExample
//
//  Created by Ben Syverson on 2013/7/31.
//  Copyright (c) 2013 Ben Syverson. All rights reserved.
//

#import "MEAppDelegate.h"

@implementation MEAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	if (textView) [textView setDelegate:self];
	//if (webView) [webView setFrameLoadDelegate:self];
	NSString *htmlString = [NSString stringWithFormat:@"<html><head><style type=\"text/css\">body { background:#e8e8e8; color: #16161d; font-family: sans-serif; }</style></head><body>loading…</body></html>"];
	[[webView mainFrame] loadHTMLString:htmlString baseURL:[NSURL URLWithString:@"http://localhost/"]];
	[self textUpdated];
	
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	[self textUpdated];
}

- (void)textDidChange:(NSNotification *)aNotification
{
	[self textUpdated];
}

- (void)textUpdated
{
	if (webView && textView) {
		// Do the conversion in the background;
		// for long or complex documents, it can
		// take longer than the delay between
		// keypresses while you write. This frees
		// up the main thread to stay responsive
		// to your typing, and updates the DOM as
		// we go.
		// - Ben
		
		changeCounter = (changeCounter + 1) % 100000;
		int myCounter = changeCounter;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void) {
			OSMarkdown *markdown = [[OSMarkdown alloc] init];
			NSString *contentString = [markdown htmlForMarkdown:[[textView textStorage] string]];
			if (changeCounter == myCounter) {
				// WebView stuff has to happen in the main queue/thread.
				dispatch_async(dispatch_get_main_queue(), ^(void) {
					DOMDocument *doc = [[webView mainFrame] DOMDocument];
					DOMNodeList *bodyNodes = [doc getElementsByTagName:@"body"];
					
					if (bodyNodes) {
						DOMHTMLElement *bodyElement = (DOMHTMLElement *)[bodyNodes item:0];
						[bodyElement setInnerHTML:contentString];
					}
				});
			} else {
				// NSLog(@"We already have a new update in the hopper.\n");
			}
		});
	}
}


@end
