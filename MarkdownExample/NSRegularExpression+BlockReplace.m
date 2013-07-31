//
//  NSRegularExpression+BlockReplace.m
//
//  Created by Ben Syverson on 2013/7/30.
//

/* 
 License:
 ========
 
 © Copyright 2013 Ben Syverson
 <http://bensyverson.com>
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are
 met:
 
 * Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 This software is provided by the copyright holders and contributors "as
 is" and any express or implied warranties, including, but not limited
 to, the implied warranties of merchantability and fitness for a
 particular purpose are disclaimed. In no event shall the copyright owner
 or contributors be liable for any direct, indirect, incidental, special,
 exemplary, or consequential damages (including, but not limited to,
 procurement of substitute goods or services; loss of use, data, or
 profits; or business interruption) however caused and on any theory of
 liability, whether in contract, strict liability, or tort (including
 negligence or otherwise) arising in any way out of the use of this
 software, even if advised of the possibility of such damage.
 */


#import "NSRegularExpression+BlockReplace.h"

@implementation NSRegularExpression (BlockReplace)

- (NSString *)replaceMatchesInString:string options:(NSMatchingOptions)options usingBlock:(NSString * (^)(NSArray *groups))block
{
	NSMutableString *aString = [string mutableCopy];
	
	NSInteger offset = 0; 
	for (NSTextCheckingResult *result in [self matchesInString:string
														options:options
														  range:NSMakeRange(0, [string length])]) {
		
		NSRange resultRange = [result range];
		resultRange.location += offset;
		
		NSMutableArray *matches = [NSMutableArray arrayWithCapacity:[result numberOfRanges]];
		for (int i = 0; i < [result numberOfRanges]; i++) {
			NSRange matchRange = [result rangeAtIndex:i];
			if (matchRange.location != NSNotFound && matchRange.length > 0) {		// It's possible to match an empty string
				[matches addObject:[aString substringWithRange:NSMakeRange(matchRange.location + offset, matchRange.length)]];
			} else {
				[matches addObject:@""];
			}
		}
		
		NSString *replacement = block(matches);
		
		[aString replaceCharactersInRange:resultRange withString:replacement];
		
		offset += ([replacement length] - resultRange.length);
	}
	return aString;
}

@end
