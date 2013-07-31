//
//  NSString+InlineReplace.h
//
//  Created by Ben Syverson on 2013/7/30.
//  Copyright (c) 2013 Ben Syverson. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (InlineReplace)


- (NSString *)stringByReplacingPattern:(NSString *)aPattern
								 flags:(NSRegularExpressionOptions)regexOptions
							   options:(NSMatchingOptions)options
						  withTemplate:(NSString *)aTemplate;


- (NSString *)stringByReplacingPattern:(NSString *)aPattern
								 flags:(NSRegularExpressionOptions)regexOptions
							   options:(NSMatchingOptions)options
							usingBlock:(NSString * (^)(NSArray *groups))block;

@end
