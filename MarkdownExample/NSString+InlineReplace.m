//
//  NSString+InlineReplace.m
//  Oscawana
//
//  Created by Ben Syverson on 2013/7/30.
//  Copyright (c) 2013 Ben Syverson. All rights reserved.
//

#import "NSString+InlineReplace.h"
#import "NSRegularExpression+BlockReplace.h"

@implementation NSString (InlineReplace)

- (NSString *)stringByReplacingPattern:(NSString *)aPattern
								 flags:(NSRegularExpressionOptions)regexOptions
							   options:(NSMatchingOptions)options
						  withTemplate:(NSString *)aTemplate
{
	NSError *anError = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:aPattern
																		   options:regexOptions
																			 error:&anError];
	if (anError) NSLog(@"%@", [anError localizedDescription]);
	return [regex stringByReplacingMatchesInString:self options:options range:NSMakeRange(0, [self length]) withTemplate:aTemplate];
}

- (NSString *)stringByReplacingPattern:(NSString *)aPattern
								 flags:(NSRegularExpressionOptions)regexOptions
							   options:(NSMatchingOptions)options
						  usingBlock:(NSString * (^)(NSArray *groups))block
{
	NSError *anError = NULL;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:aPattern
																		   options:regexOptions
																			 error:&anError];
	if (anError) NSLog(@"%@", [anError localizedDescription]);
	return [regex replaceMatchesInString:self options:options usingBlock:block];
}

@end
