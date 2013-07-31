//
//  OSMarkdown.h
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


#import <Foundation/Foundation.h>
#import "NSStringData+MD5.h"
#import "NSRegularExpression+BlockReplace.h"
#import "NSString+InlineReplace.h"

#define MD_g_tab_width					4
// Ignored for now:
//#define MD_g_empty_element_suffix		@" />"

#define MD_regex_modifier_i				NSRegularExpressionCaseInsensitive
#define MD_regex_modifier_x				NSRegularExpressionAllowCommentsAndWhitespace
#define MD_regex_modifier_s				NSRegularExpressionDotMatchesLineSeparators
#define MD_regex_modifier_m				NSRegularExpressionAnchorsMatchLines

@interface OSMarkdown : NSObject
{
	NSString			*g_nested_brackets;
	NSDictionary		*g_escape_table;
	
	__strong NSMutableDictionary	*g_urls;
	__strong NSMutableDictionary	*g_titles;
	__strong NSMutableDictionary	*g_html_blocks;
	
	int					g_list_level;
}

- (NSString *)htmlForMarkdown:(NSString *)text;

- (NSString *)stripLinkDefinitions:(NSString *)aString;
- (NSString *)hashHTMLBlocks:(NSString *)aString;
- (NSString *)runBlockGamut:(NSString *)aString;
- (NSString *)runSpanGamut:(NSString *)aString;
- (NSString *)escapeStarAndUnderscore:(NSString *)aString;
- (NSString *)escapeSpecialChars:(NSString *)aString;
- (NSString *)doAnchors:(NSString *)aString;
- (NSString *)doImages:(NSString *)aString;
- (NSString *)doHeaders:(NSString *)aString;
- (NSString *)doLists:(NSString *)aString;

- (NSString *)processListItems:(NSString *)aString
			 withMarkerPattern:(NSString *)aMarkerRegex;

- (NSString *)doCodeBlocks:(NSString *)aString;
- (NSString *)doCodeSpans:(NSString *)aString;
- (NSString *)encodeCode:(NSString *)aString;
- (NSString *)doItalicsAndBold:(NSString *)aString;
- (NSString *)doBlockQuotes:(NSString *)aString;
- (NSString *)formParagraphs:(NSString *)aString;
- (NSString *)encodeAmpsAndAngles:(NSString *)aString;
- (NSString *)encodeBackslashEscapes:(NSString *)aString;
- (NSString *)doAutoLinks:(NSString *)aString;
- (NSString *)encodeEmailAddress:(NSString *)aString;
- (NSString *)unescapeSpecialChars:(NSString *)aString;
- (NSArray *)tokenizeHTML:(NSString *)aString;
- (NSString *)outdent:(NSString *)aString;
- (NSString *)detab:(NSString *)aString;


@end
