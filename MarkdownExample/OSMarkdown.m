//
//  OSMarkdown.m
//
//  Created by Ben Syverson on 2013/7/30.

/*
 Hello,
 
 This is a quick-and-dirty port of the Perl original to 
 2013-era Objective C. There may be mistakes and typos—if
 so, let me know. This is a "literal" translation, in
 that it tries to replicate the original, line-by-line.
 There are some places where a more Objective-C-ish
 construct could be used, but I've tried to keep it
 close as possible to the original. Hopefully that makes
 it easier to track down and debug any discrepancies
 between the output of this version and the original.
 
 On most lines, I kept the original Perl as a comment,
 so you can see exactly where I went wrong if something
 is broken.
 
 Happy Markdowning,
 
 Ben Syverson
 Chicago, 2013
 
 
 License:
 --------
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

 
 Original Markdown.pl license:
 -----------------------------
 Copyright (c) 2004, John Gruber
 <http://daringfireball.net/>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are
 met:
 
 * Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 * Neither the name "Markdown" nor the names of its contributors may
 be used to endorse or promote products derived from this software
 without specific prior written permission.
 
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


#import "OSMarkdown.h"

@implementation OSMarkdown


//
// Globals:
//

- (id)init
{
	self = [super init];
	if (self) {
		// Regex to match balanced [brackets]. See Friedl's
		// "Mastering Regular Expressions", 2nd Ed., pp. 328-331.
		
		// The original supports unlimited nested brackets via regex recursion.
		// We'll support 16 levels of brackets. I mean come on.
		
		NSString *level0 =
		@"(?>" 								// Atomic matching"
		"[^\\[\\]]+"						// Anything other than brackets"
		")*";
		
		NSMutableString *nestedString = [NSMutableString stringWithString:level0];
		for (int i = 0; i < 16; i++) {
			[nestedString setString:[NSString stringWithFormat:
									 @"(?>"								// Atomic matching "
									 "[^\\[\\]]+	"						// Anything other than brackets"
									 "|"								// or..."
									 "\\["								//   a bracket"
									 "%@"								// Recursive set of nested brackets"
									 "\\]"								//   and end bracket"
									 ")*",
									 nestedString]];
		}
		
		g_nested_brackets = [nestedString copy];
		
		// Table of hash values for escaped characters:
		NSMutableDictionary *escapeTable = [[NSMutableDictionary alloc] initWithCapacity:16];
		unsigned char escapeChars[16] = "\\`*_{}[]()>#+-.!";
		for (int i = 0; i < 16; i++) {
			NSString *thisChar = [NSString stringWithFormat:@"%c", escapeChars[i]];
			[escapeTable setObject:[thisChar md5] forKey:thisChar];
		}
		g_escape_table = escapeTable;
		
		// Global hashes, used by various utility routines
		NSMutableDictionary *aDict = [NSMutableDictionary dictionaryWithCapacity:10];
		g_urls = aDict;
		
		NSMutableDictionary *bDict = [NSMutableDictionary dictionaryWithCapacity:10];
		g_titles = bDict;
		
		NSMutableDictionary *cDict = [NSMutableDictionary dictionaryWithCapacity:10];
		g_html_blocks = cDict;
		
		// Used to track when we're inside an ordered or unordered list
		// (see _ProcessListItems() for details):
		g_list_level = 0;
		
	}
	return self;
}

- (NSString *)htmlForMarkdown:(NSString *)text
{
	NSMutableString *aString = [NSMutableString stringWithString:text];

	//
	// Main function. The order in which other subs are called here is
	// essential. Link and image substitutions need to happen before
	// _EscapeSpecialChars(), so that any *'s or _'s in the <a>
	// and <img> tags get encoded.
	//
	
	// Clear the global hashes. If we don't clear these, you get conflicts
	// from other articles when generating a page which contains more than
	// one article (e.g. an index page that shows the N most recent
	// articles):
	[g_urls removeAllObjects];
	[g_titles removeAllObjects];
	[g_html_blocks removeAllObjects];
	
	
	// Standardize line endings:
	[aString replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, [aString length])]; // DOS to Unix
	[aString replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, [aString length])];	// Mac to Unix

	// Make sure $text ends with a couple of newlines:
	[aString appendString:@"\n\n"]; // $text .= "\n\n";
	
	// Convert all tabs to spaces.
	[aString setString:[self detab:aString]];// $text = _Detab($text);
	
	// Strip any lines consisting only of spaces and tabs.
	// This makes subsequent regexen easier to write, because we can
	// match consecutive blank lines with /\n+/ instead of something
	// contorted like /[ \t]*\n+/ .
	[aString setString:[aString stringByReplacingPattern:@"^[ \\t]+$"
												   flags:MD_regex_modifier_m
												 options:0
											withTemplate:@""]]; //$text =~ s/^[ \t]+$//mg;
	
	
	// Turn block-level HTML blocks into hash entries
	[aString setString:[self hashHTMLBlocks:aString]]; // $text = _HashHTMLBlocks($text);
	
	// Strip link definitions, store in hashes.
	[aString setString:[self stripLinkDefinitions:aString]]; // $text = _StripLinkDefinitions($text);
	
	
	[aString setString:[self runBlockGamut:aString]]; // $text = _RunBlockGamut($text);
	
	[aString setString:[self unescapeSpecialChars:aString]]; // $text = _UnescapeSpecialChars($text);
	
	return [aString stringByAppendingString:@"\n"];
}


- (NSString *)stripLinkDefinitions:(NSString *)aString
{
	NSError *error;
	//
	// Strips link definitions from text, stores the URLs and titles in
	// hash references.
	//
	int less_than_tab = MD_g_tab_width - 1;
	
	// Link defs are in the form: ^[id]: url "optional title"
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:
								  [NSString stringWithFormat:
								   @"	^[\\N{SPACE}]{0,%i}\\[(.+)\\]:		" //  id = $1	
								   "	  [\\N{SPACE}\\t]*		" //
								   "	  \\n?					" //  maybe *one* newline	
								   "	  [\\N{SPACE}\\t]*		" //
								   "	<?(\\S+?)>?				" //  url = $2	
								   "	  [\\N{SPACE}\\t]*		" //
								   "	  \\n?					" //  maybe one newline	
								   "	  [\\N{SPACE}\\t]*		" //
								   "	(?:		" // 
								   "		(?<=\\s)				" //  lookbehind for whitespace	
								   "		[\"(]		" // 
								   "		(.+?)				" //  title = $3	
								   "		[\")]		" // 
								   "		[\\N{SPACE}\\t]*		" //
								   "	)?		" //  title is optional	
								   "	(?:\\n+|\\Z)",
								   less_than_tab]
																		   options:MD_regex_modifier_m | MD_regex_modifier_x
																			 error:&error];
	
	
	NSArray *matches = [regex matchesInString:aString options:0 range:NSMakeRange(0, [aString length])];
	
	for (NSTextCheckingResult *match in matches) {
		NSString *anId = [aString substringWithRange:[match rangeAtIndex:1]];
		NSString *aURL = [aString substringWithRange:[match rangeAtIndex:2]];
		NSRange titleRange	= [match rangeAtIndex:3];
		
		[g_urls setObject:[self encodeAmpsAndAngles:aURL] forKey:[anId lowercaseString]]; // $g_urls{lc $1} = _EncodeAmpsAndAngles( $2 );	# Link IDs are case-insensitive
		
		if ((titleRange.location != NSNotFound) && (titleRange.length > 0)) { // if ($3) {
			NSString *aTitle = [[aString substringWithRange:titleRange] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]; // 			$g_titles{lc $1} =~ s/"/&quot;/g; #swapped order here - Ben
			
			[g_titles setObject:[anId lowercaseString] forKey:aTitle]; // 			$g_titles{lc $1} = $3;
		}
	}
	
	return [regex stringByReplacingMatchesInString:aString options:0 range:NSMakeRange(0, [aString length]) withTemplate:@""];
}


- (NSString *)hashHTMLBlocks:(NSString *)aString {
	int less_than_tab = MD_g_tab_width - 1;
	
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;

	// Hashify HTML blocks:
	// We only want to do this for block-level HTML tags, such as headers,
	// lists, and tables. That's because we still want to wrap <p>s around
	// "paragraphs" that are wrapped in non-block-level tags, such as anchors,
	// phrase emphasis, and spans. The list of tags we're looking for is
	// hard-coded:
	NSString *block_tags_a = @"p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math|ins|del|footer|header|article";
	NSString *block_tags_b = @"p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math";
	
	// First, look for nested blocks, e.g.:
	// 	<div>
	// 		<div>
	// 		tags for inner block must be indented.
	// 		</div>
	// 	</div>
	//
	// The outermost tags must start at the left margin for this to match, and
	// the inner nested divs must be indented.
	// We need to do this before the next, more liberal match, because the next
	// match will start at the first `<div>` and stop at the first `</div>`.
	
	NSString * (^replacementBlock)(NSArray *groups) = ^(NSArray *matches){
		NSString *key = [[matches objectAtIndex:1] md5];						// 	my $key = md5_hex($1);
		[g_html_blocks setObject:[matches objectAtIndex:1] forKey:key];		// $g_html_blocks{$key} = $1;
		return [NSString stringWithFormat:@"\n\n%@\n\n", key];				// "\n\n" . $key . "\n\n";
	};
	
	[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
													@"(							" //  save in $1
													"	^						" //  start of line  (with /m)
													"	<(%@)		" //  start tag = $2
													"	\\b						" //  word break
													"	(.*\\n)*?				" //  any number of lines, minimally matching
													"	</\\2>					" //  the matching end tag
													"	[\\N{SPACE}\\t]*					" //  trailing spaces/tabs
													"	(?=\\n+|\\Z)		" //  followed by a newline or end of document
													")",
													block_tags_a]
											 flags:MD_regex_modifier_m | MD_regex_modifier_x
										   options:0
										usingBlock:replacementBlock]];
	

	[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
										@"(							" //  save in $1
										"	^						" //  start of line  (with /m)
										"	<(%@)					" //  start tag = $2
										"	\\b						" //  word break
										"	(.*\\n)*?				" //  any number of lines, minimally matching
										"	.*</\\2>					" //  the matching end tag
										"	[\\N{SPACE}\\t]*					" //  trailing spaces/tabs
										"	(?=\\n+|\\Z)				" //  followed by a newline or end of document
										")",
										block_tags_b]
																				  flags:MD_regex_modifier_m | MD_regex_modifier_x
																				options:0
																			 usingBlock:replacementBlock]];
	
	// Special case just for <hr />. It was easier to make a special case than
	// to make the other regex more complicated.
	
	[text setString:[text stringByReplacingPattern:
					 [NSString stringWithFormat:
					  @"(?:					"
					  "		(?<=\\n\\n)		"//   Starting after a blank line
					  "		|				"//   or
					  "		\\A\\n?			"//   the beginning of the doc
					  "	)						"
					  "	(						"//   save in $1
					  "		[\\N{SPACE}]{0,%i}"
					  "		<(hr)				"//   start tag = $2
					  "		\\b					"//   word break
					  "		([^<>])*?			"
					  "		/?>					"//   the matching end tag
					  "		[\\N{SPACE}\\t]*				"
					  "		(?=\\n{2,}|\\Z)		"//   followed by a blank line or end of document
					  "	)",
					  less_than_tab]
											 flags:MD_regex_modifier_x
										   options:0
										usingBlock:replacementBlock]];
	
	
	// Special case for standalone HTML comments:
	[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
										  @"				(?:\n"
										  "					(?<=\\n\\n)			" //  Starting after a blank line
										  "					|					" //  or
										  "					\\A\\n?				" //  the beginning of the doc
										  "				)\n"
										  "				(							" //  save in $1
										  "					[\\N{SPACE}]{0,%i}\n"
										  "					(?s:\n"
										  "						<!\n"
										  "						(--.*?--\\s*)+\n"
										  "						>\n"
										  "					)\n"
										  "					[\\N{SPACE}\\t]*\n"
										  "					(?=\\n{2,}|\\Z)			" //  followed by a blank line or end of document
										  "				)\n",
										  less_than_tab]
											 flags:MD_regex_modifier_x
										   options:0
										usingBlock:replacementBlock]];
	return text;
}


- (NSString *)runBlockGamut:(NSString *)aString {
	//
	// These are all the transformations that form block-level
	// tags like paragraphs, headers, and list items.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	[text setString:[self doHeaders:text]]; //$text = _DoHeaders($text);
	
	// Do Horizontal Rules:
	[text setString:[text stringByReplacingPattern:@"^[ ]{0,2}([ ]?\\*[ ]?){3,}[ \\t]*$" flags:MD_regex_modifier_m options:0 withTemplate:@"\n<hr />"]]; // 	$text =~ s{^[ ]{0,2}([ ]?\*[ ]?){3,}[ \t]*$}{\n<hr$g_empty_element_suffix\n}gmx;

	[text setString:[text stringByReplacingPattern:@"^[ ]{0,2}([ ]? -[ ]?){3,}[ \\t]*$" flags:MD_regex_modifier_m options:0 withTemplate:@"\n<hr />"]]; // 	$text =~ s{^[ ]{0,2}([ ]? -[ ]?){3,}[ \t]*$}{\n<hr$g_empty_element_suffix\n}gmx;

	[text setString:[text stringByReplacingPattern:@"^[ ]{0,2}([ ]? _[ ]?){3,}[ \\t]*$" flags:MD_regex_modifier_m options:0 withTemplate:@"\n<hr />"]]; // 	$text =~ s{^[ ]{0,2}([ ]? _[ ]?){3,}[ \t]*$}{\n<hr$g_empty_element_suffix\n}gmx;
	
	[text setString:[self doLists:text]]; // $text = _DoLists($text);
	
	[text setString:[self doCodeBlocks:text]]; // $text = _DoCodeBlocks($text);
	
	[text setString:[self doBlockQuotes:text]]; // $text = _DoBlockQuotes($text);
	
	// We already ran _HashHTMLBlocks() before, in Markdown(), but that
	// was to escape raw HTML in the original Markdown source. This time,
	// we're escaping the markup we've just created, so that we don't wrap
	// <p> tags around block-level tags.
	[text setString:[self hashHTMLBlocks:text]]; //$text = _HashHTMLBlocks($text);
	
	[text setString:[self formParagraphs:text]]; //$text = _FormParagraphs($text);
	
	return text;
}

- (NSString *)runSpanGamut:(NSString *)aString {
	//
	// These are all the transformations that occur *within* block-level
	// tags like paragraphs, headers, and list items.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;

	[text setString:[self doCodeSpans:text]]; // $text = _DoCodeSpans($text);
	
	[text setString:[self escapeSpecialChars:text]]; // $text = _EscapeSpecialChars($text);
	
	// Process anchor and image tags. Images must come first,
	// because ![foo][f] looks like an anchor.
	[text setString:[self doImages:text]]; // $text = _DoImages($text);
	[text setString:[self doAnchors:text]]; // $text = _DoAnchors($text);
	
	// Make links out of things like `<http://example.com/>`
	// Must come after _DoAnchors(), because you can use < and >
	// delimiters in inline links like [this](<url>).
	[text setString:[self doAutoLinks:text]]; //$text = _DoAutoLinks($text);
	
	[text setString:[self encodeAmpsAndAngles:text]]; //$text = _EncodeAmpsAndAngles($text);
	
	[text setString:[self doItalicsAndBold:text]]; //$text = _DoItalicsAndBold($text);
	
	// Do hard breaks:
	[text setString:[text stringByReplacingPattern:@" {2,}\\n" flags:0 options:0 withTemplate:@" <br />"]]; // $text =~ s/ {2,}\n/ <br$g_empty_element_suffix\n/g;
	return text;
}

- (NSString *)escapeStarAndUnderscore:(NSString *)aString {
	NSMutableString *newString = [NSMutableString stringWithString:aString];
	[newString replaceOccurrencesOfString:@"*" withString:[g_escape_table objectForKey:@"*"] options:0 range:NSMakeRange(0, [newString length])]; // $cur_token->[1] =~  s! \* !$g_escape_table{'*'}!gx;
	[newString replaceOccurrencesOfString:@"_" withString:[g_escape_table objectForKey:@"_"] options:0 range:NSMakeRange(0, [newString length])]; // $cur_token->[1] =~  s! _  !$g_escape_table{'_'}!gx;
	return aString;
}

- (NSString *)escapeSpecialChars:(NSString *)aString {
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	NSArray *tokens = [self tokenizeHTML:text];							// my $tokens ||= _TokenizeHTML($text);
	
	[text setString:@""]; // $text = '';   # rebuild $text from the tokens
	// 	my $in_pre = 0;	 # Keep track of when we're inside <pre> or <code> tags.
	// 	my $tags_to_skip = qr!<(/?)(?:pre|code|kbd|script|math)[\s>]!;
	
	for (NSArray *cur_token in tokens) {							// foreach my $cur_token (@$tokens) {
		NSMutableString *token = [NSMutableString stringWithString:[cur_token objectAtIndex:1]];
		if ([[cur_token objectAtIndex:0] isEqualToString:@"tag"]) {		// if ($cur_token->[0] eq "tag") {
			// Within tags, encode * and _ so they don't conflict
			// with their use in Markdown for italics and strong.
			// We're replacing each such character with its
			// corresponding MD5 checksum value; this is likely
			// overkill, but it should prevent us from colliding
			// with the escape values by accident.
			[token setString:[self escapeStarAndUnderscore:token]]; // $cur_token->[1] =~  s! \* !$g_escape_table{'*'}!gx;  $cur_token->[1] =~  s! _  !$g_escape_table{'_'}!gx;

			[text appendString:token]; //	$text .= $cur_token->[1];
		} else {
			[text appendString:[self encodeBackslashEscapes:token]];  // $t = _EncodeBackslashEscapes($t); $text .= $t;
		}
	}
	return text;
}

- (NSString *)doAnchors:(NSString *)aString {
	//
	// Turn Markdown link shortcuts into XHTML <a> tags.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	
	//
	// First, handle reference-style links: [link text] [id]
	//
	[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
									@"		(						" //  wrap whole match in $1
									"		  \\["
									"		    (%@)				" //  link text = $2
									"		  \\]"
									"		  [\\N{SPACE}]?					" //  one optional space
									"		  (?:\\n[\\N{SPACE}]*)?			" //  one optional newline followed by spaces
									"		  \\["
									"		    (.*?)				" //  id = $3
									"		  \\]"
									"		)",
									g_nested_brackets]
							 flags:MD_regex_modifier_x | MD_regex_modifier_s options:0 usingBlock:^(NSArray *matches)
	 {
		 NSMutableString *result = [NSMutableString stringWithString:@""];
		 
		 NSString *whole_match = [matches objectAtIndex:1];						//  my $whole_match = $1;
		 NSString *link_text   = [matches objectAtIndex:2];						// my $link_text   = $2;
		 NSString *link_id     = [[matches objectAtIndex:3] lowercaseString];	// my $link_id     = lc $3;
		 
		 if (!link_id || [link_id isEqualToString:@""]) {						// if ($link_id eq "") {
			 link_id = [link_text lowercaseString];								// $link_id = lc $link_text;     # for shortcut links like [this][].
		}
		 
		 if ([g_urls objectForKey:link_id]) {									//  if (defined $g_urls{$link_id}) {
			 [result appendFormat:@"<a href=\"%@\"",
								[self escapeStarAndUnderscore:[g_urls objectForKey:link_id]]]; //  my $title = $g_titles{$link_id}; $url =~ s! \* !$g_escape_table{'*'}!gx; $url =~ s!  _ !$g_escape_table{'_'}!gx;	 $result = "<a href=\"$url\"";
			 
			 if ([g_titles objectForKey:link_id]) {									//  if (defined $g_titles{$link_id}) {
				 [result appendFormat:@" title=\"%@\"",
				  [self escapeStarAndUnderscore:[g_titles objectForKey:link_id]]]; //my $title = $g_titles{$link_id};  $title =~ s! \* !$g_escape_table{'*'}!gx;  $title =~ s!  _ !$g_escape_table{'_'}!gx; $result .=  " title=\"$title\"";
			 }
			 [result appendFormat:@">%@</a>", link_text]; // $result .= ">$link_text</a>";
		 } else {
			 [result setString:whole_match];
		 }
		 return result;
	 }]];
	
	//
	// Next, inline-style links: [link text](url "optional title")
	//
	
	[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
									@"		(					" //  wrap whole match in $1
									"		  \\["
									"		    (%@)		" //  link text = $2
									"		  \\]"
									"		  \\(				" //  literal paren
									"		  	[\\N{SPACE}\\t]*"
									"			<?(.*?)>?		" //  href = $3
									"		  	[\\N{SPACE}\\t]*"
									"			(				" //  $4
									"			  (['\"])		" //  quote char = $5
									"			  (.*?)			" //  Title = $6
									"			  \\5			" //  matching quote
									"			)?				" //  title is optional
									"		  \\)"
									"		)",
									g_nested_brackets]
							 flags:MD_regex_modifier_s | MD_regex_modifier_x options:0 usingBlock:^(NSArray *matches)
	 {
		 NSMutableString *result = [NSMutableString stringWithFormat:@"<a href=\"%@\"",
									[self escapeStarAndUnderscore:[matches objectAtIndex:3]]]; // my $result;  $url =~ s! \* !$g_escape_table{'*'}!gx; $url =~ s!  _ !$g_escape_table{'_'}!gx;	 $result = "<a href=\"$url\"";
		 if (([matches count] > 5) && (![[matches objectAtIndex:6] isEqualToString:@""])) { // if (defined $title) {
			 NSMutableString *title = [NSMutableString stringWithString:[matches objectAtIndex:6]];
			 [title replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, [title length])]; // $title =~ s/\"/&quot;/g;"
			 [title setString:[NSString stringWithFormat:@" title=\"%@\"", [self escapeStarAndUnderscore:title]]]; // 			 $title =~ s! \* !$g_escape_table{'*'}!gx; $title =~ s!  _ !$g_escape_table{'_'}!gx; $result .=  " title=\"$title\"";

		 }
		 [result appendFormat:@">%@</a>", [matches objectAtIndex:2]]; // $result .= ">$link_text</a>";
		 return result;
	 }]];
	return text;
}

- (NSString *)doImages:(NSString *)aString {
	//
	// Turn Markdown image shortcuts into <img> tags.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	
	//
	// First, handle reference-style labeled images: ![alt text][id]
	//
	[text setString:[text stringByReplacingPattern:
	 @"		(					" //  wrap whole match in $1
	 "		  !\\["
	 "		    (.*?)			" //  alt text = $2
	 "		  \\]"
	 "		  [\\N{SPACE}]?					" //  one optional space
	 "		  (?:\\n[\\N{SPACE}]*)?			" //  one optional newline followed by spaces
	 "		  \\["
	 "		    (.*?)			" //  id = $3
	 "		  \\]"
	 "		)"
							 flags:MD_regex_modifier_s | MD_regex_modifier_x options:0 usingBlock:^(NSArray *matches)
	 {
		 NSMutableString *result = [NSMutableString stringWithString:@""]; //  my $result;
		 NSString *whole_match = [matches objectAtIndex:1]; //  my $whole_match = $1;
		 NSString *alt_text    = [matches objectAtIndex:2]; //  my $alt_text    = $2;
		 NSString *link_id     = [[matches objectAtIndex:3] lowercaseString]; // my $link_id     = lc $3;
		 
		 if ([link_id isEqualToString:@""]) { //if ($link_id eq "") {
			 link_id = [alt_text lowercaseString]; // $link_id = lc $alt_text;     # for shortcut links like ![this][].
		 }
		 alt_text = [alt_text stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]; //$alt_text =~ s/"/&quot;/g;
		 if ([g_urls objectForKey:link_id]) { //if (defined $g_urls{$link_id}) {
			 NSMutableString *url = [NSMutableString stringWithString:[g_urls objectForKey:link_id]];// my $url = $g_urls{$link_id};
			 [url setString:[self escapeStarAndUnderscore:url]]; // 			 $url =~ s! \* !$g_escape_table{'*'}!gx;	  $url =~ s!  _ !$g_escape_table{'_'}!gx;

			 [result appendFormat:@"<img src=\"%@\" alt=\"%@\"", url, alt_text]; // $result = "<img src=\"$url\" alt=\"$alt_text\"";
			 if ([g_titles objectForKey:link_id]) { // if (defined $g_titles{$link_id}) {
				 [result appendFormat:@" title=\"%@\"", [self escapeStarAndUnderscore:[g_titles objectForKey:link_id]]]; // 				 my $title = $g_titles{$link_id}; $title =~ s! \* !$g_escape_table{'*'}!gx; $title =~ s!  _ !$g_escape_table{'_'}!gx; $result .=  " title=\"$title\"";

			 }
			 [result appendString:@" />"]; // $result .= $g_empty_element_suffix;
		 } else {
			 // If there's no such link ID, leave intact:
			 [result setString:whole_match]; // $result = $whole_match;
		 }
		 return result;
	 }]];
	//
	// Next, handle inline images:  ![alt text](url "optional title")
	// Don't forget: encode * and _
	
	[text setString:[text stringByReplacingPattern:
	 @"		(					" //  wrap whole match in $1
	 "		  !\\["
	 "		    (.*?)			" //  alt text = $2
	 "		  \\]"
	 "		  \\(				" //  literal paren
	 "		  	[\\N{SPACE}\\t]*"
	 "			<?(\\S+?)>?		" //  src url = $3
	 "		  	[\\N{SPACE}\\t]*"
	 "			(				" //  $4
	 "			  (['\"])		" //  quote char = $5
	 "			  (.*?)			" //  title = $6
	 "			  \\5			" //  matching quote
	 "			  [\\N{SPACE}\\t]*"
	 "			)?				" //  title is optional
	 "		  \\)"
	 "		)"
							 flags:MD_regex_modifier_s | MD_regex_modifier_x options:0 usingBlock:^(NSArray *matches)
	 {
		 NSMutableString *result = [NSMutableString stringWithString:@""]; //  my $result;
																		   // NSString *whole_match	= [matches objectAtIndex:1]; //  my $whole_match = $1;
		 NSString *alt_text		= [matches objectAtIndex:2]; //  my $alt_text    = $2;
		 NSString *url			= [matches objectAtIndex:3]; // my $url = $3
		 NSString *title		= @""; // my $title		= '';
		 if (([matches count] > 5) && (![[matches objectAtIndex:6] isEqualToString:@""])) { // if (defined($6)) {
			 title = [matches objectAtIndex:6]; // $title		= $6;
		 }
		 alt_text = [alt_text stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]; // $alt_text =~ s/"/&quot;/g;
		 title = [title stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]; //  $title    =~ s/"/&quot;/g;
		 [result appendFormat:@"<img src=\"%@\" alt=\"%@\"", [self escapeStarAndUnderscore:url], alt_text]; // 		 $url =~ s! \* !$g_escape_table{'*'}!gx; $url =~ s!  _ !$g_escape_table{'_'}!gx; $result = "<img src=\"$url\" alt=\"$alt_text\"";

		 if (![title isEqualToString:@""]) { // if (defined $title) {
			 [result appendFormat:@" title=\"%@\"", [self escapeStarAndUnderscore:title]]; // 			 $title =~ s! \* !$g_escape_table{'*'}!gx;  $title =~ s!  _ !$g_escape_table{'_'}!gx;  $result .=  " title=\"$title\"";
		 }
		 [result appendFormat:@" />"]; // $result .= $g_empty_element_suffix;
		 return result;
	 }]];
	 
	 return text;
}

- (NSString *)doHeaders:(NSString *)aString {
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	
	// Setext-style headers:
	//	  Header 1
	//	  ========
	//
	//	  Header 2
	//	  --------
	//
	[text setString:[text stringByReplacingPattern:@"^(.+)[ \\t]*\n=+[ \\t]*\\n+"
											 flags:MD_regex_modifier_m
										   options:0
										usingBlock:^(NSArray *matches)
					 {
						 return [NSString stringWithFormat:@"<h1>%@</h1>\n\n", [self runSpanGamut:[matches objectAtIndex:1]]];
					 }]]; // $text =~ s{ ^(.+)[ \t]*\n=+[ \t]*\n+ }{"<h1>"  .  _RunSpanGamut($1)  .  "</h1>\n\n";}egmx;


	[text setString:[text stringByReplacingPattern:@"^(.+)[ \\t]*\\n-+[ \\t]*\\n+"
											 flags:MD_regex_modifier_m
										   options:0
										usingBlock:^(NSArray *matches)
					 {
						 return [NSString stringWithFormat:@"<h2>%@</h2>\n\n", [self runSpanGamut:[matches objectAtIndex:1]]];
					 }]]; // $text =~ s{ ^(.+)[ \t]*\n-+[ \t]*\n+ }{"<h2>"  .  _RunSpanGamut($1)  .  "</h2>\n\n";}egmx;

	// atx-style headers:
	//	# Header 1
	//	## Header 2
	//	## Header 2 with closing hashes ##
	//	...
	//	###### Header 6
	//
	
//	$text =~ s{
//		^(\#{1,6})	# $1 = string of #'s
//		[ \t]*
//		(.+?)		# $2 = Header text
//		[ \t]*
//		\#*			# optional closing #'s (not counted)
//		\n+
//	}{
//		my $h_level = length($1);
//		"<h$h_level>"  .  _RunSpanGamut($2)  .  "</h$h_level>\n\n";
//	}egmx;
	
	[text setString:[text stringByReplacingPattern:
					 @"			^(\\#{1,6})	"// $1 = string of 	#'s
					 "			[\\N{SPACE}\\t]*"
					 "			(.+?)			" //  $2 = Header text
					 "			[\\N{SPACE}\\t]*"
					 "			\\#*			"//# optional closing 	#'s (not counted)
					 "			\\n+"
											 flags:MD_regex_modifier_m | MD_regex_modifier_x
										   options:0
										usingBlock:^(NSArray *matches)
					 {
						 NSUInteger h_level = [[matches objectAtIndex:1] length]; // my $h_level = length($1);
						 return [NSString stringWithFormat:@"<h%li>%@</h%li>\n\n",
								 (unsigned long)h_level,
								 [self runSpanGamut:[matches objectAtIndex:2]],
								 (unsigned long)h_level]; // "<h$h_level>"  .  _RunSpanGamut($2)  .  "</h$h_level>\\n\\n\";"
						 

					 }]];
	
	return text;
}

- (NSString *)doLists:(NSString *)aString {
	NSError *regexError;
	//
	// Form HTML ordered (numbered) and unordered (bulleted) lists.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	int less_than_tab = MD_g_tab_width - 1;
	
	// Re-usable patterns to match list item bullets and number markers:
	NSString *marker_ul = @"[*+-]"; // my $marker_ul  = qr/[*+-]/;
	NSString *marker_ol = @"\\d+[.]"; // my $marker_ol  = qr/\d+[.]/;
	NSString *marker_any = [NSString stringWithFormat:@"(?:%@|%@)", marker_ul, marker_ol]; // my $marker_any = qr/(?:$marker_ul|$marker_ol)/;
	
	NSRegularExpression *markerUlRegex = [NSRegularExpression regularExpressionWithPattern:marker_ul options:0 error:&regexError];
	
	// Re-usable pattern to match any entirel ul or ol list:
	//	my $whole_list = qr{
	//		(								# $1 = whole list
	//		 (								# $2
	//		  [ ]{0,$less_than_tab}
	//		  (${marker_any})				# $3 = first list item marker
	//		  [ \t]+
	//		  )
	//		 (?s:.+?)
	//		 (								# $4
	//		  \z
	//		  |
	//		  \n{2,}
	//		  (?=\S)
	//		  (?!						# Negative lookahead for another list item marker
	//		   [ \t]*
	//		   ${marker_any}[ \t]+
	//		   )
	//		  )
	//		 )
	//	}mx;
	NSString *whole_list = [NSString stringWithFormat:
							@"		(									" //  $1 = whole list
							"		  (									" //  $2
							"			[\\N{SPACE}]{0,%i}"
							"			(%@)					" //  $3 = first list item marker
							"			[\\N{SPACE}\\t]+"
							"		  )"
							"		  (?s:.+?)"
							"		  (									" //  $4
							"			  \\z"
							"			|"
							"			  \\n{2,}"
							"			  (?=\\S)"
							"			  (?!							" //  Negative lookahead for another list item marker
							"				[\\N{SPACE}\\t]*"
							"				%@[\\N{SPACE}\\t]+"
							"			  )"
							"		  )"
							"		)",
							less_than_tab,
							marker_any,
							marker_any];
	
	
	// We use a different prefix before nested lists than top-level lists.
	// See extended comment in _ProcessListItems().
	//
	// Note: There's a bit of duplication here. My original implementation
	// created a scalar regex pattern as the conditional result of the test on
	// $g_list_level, and then only ran the $text =~ s{...}{...}egmx
	// substitution once, using the scalar as the pattern. This worked,
	// everywhere except when running under MT on my hosting account at Pair
	// Networks. There, this caused all rebuilds to be killed by the reaper (or
	// perhaps they crashed, but that seems incredibly unlikely given that the
	// same script on the same server ran fine *except* under MT. I've spent
	// more time trying to figure out why this is happening than I'd like to
	// admit. My only guess, backed up by the fact that this workaround works,
	// is that Perl optimizes the substition when it can figure out that the
	// pattern will never change, and when this optimization isn't on, we run
	// afoul of the reaper. Thus, the slightly redundant code to that uses two
	// static s/// patterns rather than one conditional pattern.
	
	NSString * (^replacementBlock)(NSArray *groups) = ^(NSArray *matches){
		NSMutableString *list = [NSMutableString stringWithString:[matches objectAtIndex:1]]; // my $list = $1;
		NSRange markerRange = [markerUlRegex rangeOfFirstMatchInString:[matches objectAtIndex:3] options:0 range:NSMakeRange(0, [[matches objectAtIndex:3] length])]; // my $list_type = ($3 =~ m/$marker_ul/) ? "ul" : "ol";
		NSString *list_type = ((markerRange.location != NSNotFound) && (markerRange.length > 0)) ? @"ul" : @"ol";
		
		// Turn double returns into triple returns, so that we can make a
		// paragraph for the last item in a list, if necessary:
		
		[list setString:[list stringByReplacingPattern:@"\\n{2,}" flags:0 options:0 withTemplate:@"\n\n\n"]]; // $list =~ s/\n{2,}/\n\n\n/g;
		
		NSMutableString *result = [NSMutableString stringWithString:[self processListItems:list withMarkerPattern:marker_any]]; //  my $result = _ProcessListItems($list, $marker_any);
		[result setString:[NSString stringWithFormat:@"<%@>\n%@</%@>\n",
						   list_type,
						   result,
						   list_type]];
		return result;
	};
	
	if (g_list_level > 0) { // if ($g_list_level) {
		[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
						 @"				^"
						 "				%@",
														whole_list]
												 flags:MD_regex_modifier_m | MD_regex_modifier_x
											   options:0
											usingBlock:replacementBlock]];
	} else {
		[text setString:[text stringByReplacingPattern:[NSString stringWithFormat:
														@"				(?:(?<=\\n\\n)|\\A\\n?)"
														"				%@",
														whole_list]
												 flags:MD_regex_modifier_m | MD_regex_modifier_x
											   options:0
											usingBlock:replacementBlock]];
	}
	
	return text;
}

- (NSString *)processListItems:(NSString *)aString
				withMarkerPattern:(NSString *)aMarkerRegex {
	//
	//	Process the contents of a single ordered or unordered list, splitting it
	//	into individual list items.
	//
	
	NSMutableString *list_str = [NSMutableString stringWithString:aString]; // my $list_str = shift;
	NSString *marker_any = [aMarkerRegex copy]; // my $marker_any = shift;
	
	
	// The $g_list_level global keeps track of when we're inside a list.
	// Each time we enter a list, we increment it; when we leave a list,
	// we decrement. If it's zero, we're not in a list anymore.
	//
	// We do this because when we're not inside a list, we want to treat
	// something like this:
	//
	//		I recommend upgrading to version
	//		8. Oops, now this line is treated
	//		as a sub-list.
	//
	// As a single paragraph, despite the fact that the second line starts
	// with a digit-period-space sequence.
	//
	// Whereas when we're inside a list (or sub-list), that line will be
	// treated as the start of a sub-list. What a kludge, huh? This is
	// an aspect of Markdown's syntax that's hard to parse perfectly
	// without resorting to mind-reading. Perhaps the solution is to
	// change the syntax rules such that sub-lists must start with a
	// starting cardinal number; e.g. "1." or "a.".
	
	g_list_level++;
	
	// trim trailing blank lines:
	
	[list_str setString:[list_str stringByReplacingPattern:@"\\n{2,}\\z" flags:0 options:0 withTemplate:@"\n"]]; // $list_str =~ s/\n{2,}\z/\n/;
	[list_str setString:[list_str stringByReplacingPattern:[NSString stringWithFormat:
															@"		(\\n)?								" //  leading line = $1
															"		(^[\\N{SPACE}\\t]*)							" //  leading whitespace = $2
															"		(%@) [\\N{SPACE}\\t]+				" //  list marker = $3
															"		((?s:.+?)							" //  list item text   = $4
															"		(\\n{1,2}))"
															"		(?= \\n* (\\z | \\2 (%@) [\\N{SPACE}\\t]+))",
															marker_any,
															marker_any]
													 flags:MD_regex_modifier_x | MD_regex_modifier_m
												   options:0
												usingBlock:^(NSArray *matches)
						 {
							 NSMutableString *item = [NSMutableString stringWithString:[matches objectAtIndex:4]]; // my $item = $4;
							 NSString *leading_line = [matches objectAtIndex:1]; // my $leading_line = $1;
																				 // NSString *leading_space = [matches objectAtIndex:2]; //  my $leading_space = $2;
							 
							 NSError *error;
							 NSRegularExpression *newlineRegex = [NSRegularExpression regularExpressionWithPattern:@"\\n{2,}" options:0 error:&error];
							 NSUInteger matchCount = [newlineRegex numberOfMatchesInString:item options:0 range:NSMakeRange(0, [item length])];
							 
							 if ((![leading_line isEqualToString:@""]) || (matchCount > 0)) { // if ($leading_line or ($item =~ m/\n{2,}/)) {
								 [item setString:[self runBlockGamut:[self outdent:item]]];// $item = _RunBlockGamut(_Outdent($item));
							 } else {
								 // Recursion for sub-lists:
								 [item setString:[self doLists:[self outdent:item]]]; //  $item = _DoLists(_Outdent($item));
								 if ([item hasSuffix:@"\n"]) [item replaceCharactersInRange:NSMakeRange([item length] - 1, 1) withString:@""]; // chomp $item;
								 [item setString:[self runSpanGamut:item]]; // $item = _RunSpanGamut($item);
							 }
							
							 [item setString:[NSString stringWithFormat:@"<li>%@</li>\n", item]]; // "<li>" . $item . "</li>\n";
							 return item;
						 }]];
	
	g_list_level--;
	return list_str;
}

- (NSString *)doCodeBlocks:(NSString *)aString {
	//
	//	Process Markdown `<pre><code>` blocks.
	//
	
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	[text setString:[text stringByReplacingPattern:
					 [NSString stringWithFormat:
					  @"		(?:\\n\\n|\\A)"
					  "			(	            	" //  $1 = the code block -- one or more lines, starting with a space/tab
					  "			  (?:			"
					  "			    (?:[\\N{SPACE}]{%i} | \\t)  	" //  Lines must start with a tab or a tab-width of spaces
					  "			    .*\\n+"
					  "			  )+				"
					  "			)"
					  "			((?=^[\\N{SPACE}]{0,%i}\\S)|\\Z)	# Lookahead for non-space at line-start, or end of doc",
					  MD_g_tab_width,
					  MD_g_tab_width]
											 flags:MD_regex_modifier_x | MD_regex_modifier_m
										   options:0
										usingBlock:^(NSArray *matches)
					 {
						 NSMutableString *codeblock = [NSMutableString stringWithString:[matches objectAtIndex:1]]; // my $codeblock = $1;
						//my $result; # return value
						 
						 [codeblock setString:[self encodeCode:[self outdent:codeblock]]];//  $codeblock = _EncodeCode(_Outdent($codeblock));
						 [codeblock setString:[self detab:codeblock]]; // $codeblock = _Detab($codeblock);
						 
						 [codeblock setString:[codeblock stringByReplacingPattern:@"\\A\\n+" flags:0 options:0 withTemplate:@""]]; // $codeblock =~ s/\A\n+//; # trim leading newlines
						 [codeblock setString:[codeblock stringByReplacingPattern:@"\\s+\\z" flags:0 options:0 withTemplate:@""]]; // $codeblock =~ s/\s+\z//; # trim trailing whitespace
						 
						 return [NSString stringWithFormat:@"\n\n<pre><code>%@\n</code></pre>\n\n",
								 codeblock];
					 }]];
	
	return text;
}

- (NSString *)doCodeSpans:(NSString *)aString {
	//
	// 	*	Backtick quotes are used for <code></code> spans.
	//
	// 	*	You can use multiple backticks as the delimiters if you want to
	// 		include literal backticks in the code span. So, this input:
	//
	//         Just type ``foo `bar` baz`` at the prompt.
	//
	//     	Will translate to:
	//
	//         <p>Just type <code>foo `bar` baz</code> at the prompt.</p>
	//
	//		There's no arbitrary limit to the number of backticks you
	//		can use as delimters. If you need three consecutive backticks
	//		in your code, use four for delimiters, etc.
	//
	//	*	You can use spaces to get literal backticks at the edges:
	//
	//         ... type `` `bar` `` ...
	//
	//     	Turns to:
	//
	//         ... type <code>`bar`</code> ...
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	[text setString:[text stringByReplacingPattern:
					 @"			(`+)			" //  $1 = Opening run of `
					 "			(.+?)			" //  $2 = The code block
					 "			(?<!`)"
					 "			\\1				" //  Matching closer
					 "			(?!`)"
											  flags:MD_regex_modifier_x | MD_regex_modifier_m
										   options:0
										usingBlock:^(NSArray *matches)
					 {
						 NSMutableString *c = [NSMutableString stringWithString:[matches objectAtIndex:2]]; //  my $c = "$2";
						 [c setString:[c stringByReplacingPattern:@"^[ \t]*" flags:0 options:0 withTemplate:@""]]; // $c =~ s/^[ \t]*//g; # leading whitespace
						 [c setString:[c stringByReplacingPattern:@"[ \t]*$" flags:0 options:0 withTemplate:@""]]; //  $c =~ s/[ \t]*$//g; # trailing whitespace
						 return [NSString stringWithFormat:@"<code>%@</code>", [self encodeCode:c]]; // $c = _EncodeCode($c); "<code>$c</code>";
					 }]];
	return text;
}

- (NSString *)encodeCode:(NSString *)aString {
	//
	// Encode/escape certain characters inside Markdown code runs.
	// The point is that in code, these characters are literals,
	// and lose their special Markdown meanings.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
    	
	// Encode all ampersands; HTML entities are not
	// entities within a Markdown code span.
	[text replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [text length])]; // s/&/&amp;/g;
	
	// Encode $'s, but only if we're running under Blosxom.
	// (Blosxom interpolates Perl variables in article bodies.)
	/*{
		no warnings 'once';
    	if (defined($blosxom::version)) {
    		s/\$/&	" // 036;/g;
    	}
    }*/
	
	
	// Do the angle bracket song and dance:
	[text replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [text length])]; // s! <  !&lt;!gx;
	[text replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [text length])]; // s! <  !&lt;!gx;

	// Now, escape characters that are magic in Markdown:
	[text replaceOccurrencesOfString:@"*" withString:[g_escape_table objectForKey:@"*"] options:0 range:NSMakeRange(0, [text length])]; // s! \* !$g_escape_table{'*'}!gx;
	[text replaceOccurrencesOfString:@"_" withString:[g_escape_table objectForKey:@"_"] options:0 range:NSMakeRange(0, [text length])]; // s! _  !$g_escape_table{'_'}!gx;
	[text replaceOccurrencesOfString:@"{" withString:[g_escape_table objectForKey:@"{"] options:0 range:NSMakeRange(0, [text length])]; // s! {  !$g_escape_table{'{'}!gx;
	[text replaceOccurrencesOfString:@"}" withString:[g_escape_table objectForKey:@"}"] options:0 range:NSMakeRange(0, [text length])]; // s! }  !$g_escape_table{'}'}!gx;
	[text replaceOccurrencesOfString:@"[" withString:[g_escape_table objectForKey:@"["] options:0 range:NSMakeRange(0, [text length])]; // s! \[ !$g_escape_table{'['}!gx;
	[text replaceOccurrencesOfString:@"]" withString:[g_escape_table objectForKey:@"]"] options:0 range:NSMakeRange(0, [text length])]; // s! \] !$g_escape_table{']'}!gx;
	[text replaceOccurrencesOfString:@"\\" withString:[g_escape_table objectForKey:@"\\"] options:0 range:NSMakeRange(0, [text length])]; // s! \\ !$g_escape_table{'\\'}!gx;
	
	return text;
}

- (NSString *)doItalicsAndBold:(NSString *)aString {
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
	
	// <strong> must go first:
	[text setString:[text stringByReplacingPattern:@"(\\*\\*|__) (?=\\S) (.+?[*_]*) (?<=\\S) \\1"
											 flags:MD_regex_modifier_s | MD_regex_modifier_x
										   options:0
									  withTemplate:@"<strong>$2</strong>"] ]; // $text =~ s{ (\*\*|__) (?=\S) (.+?[*_]*) (?<=\S) \1 } {<strong>$2</strong>}gsx;
	
	
	[text setString:[text stringByReplacingPattern:@"(\\*|_) (?=\\S) (.+?) (?<=\\S) \\1"
											 flags:MD_regex_modifier_s | MD_regex_modifier_x
										   options:0
									  withTemplate:@"<em>$2</em>"]]; // $text =~ s{ (\*|_) (?=\S) (.+?) (?<=\S) \1 } {<em>$2</em>}gsx;
	
	return text;
}

- (NSString *)doBlockQuotes:(NSString *)aString {
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
	[text setString:[text stringByReplacingPattern:
					 @"		  (									" //  Wrap whole match in $1
					 "			("
					 "			  ^[\\N{SPACE}\\t]*>[\\N{SPACE}\\t]?				" //  '>' at the start of a line
					 "			    .+\\n						" //  rest of the first line
					 "			  (.+\\n)*						" //  subsequent consecutive lines
					 "			  \\n*							" //  blanks
					 "			)+"
					 "		  )"
											 flags:MD_regex_modifier_m | MD_regex_modifier_x
										   options:0
										usingBlock:^(NSArray *matches)
					 {
						 NSMutableString *bq = [NSMutableString stringWithString:[matches objectAtIndex:1]]; // my $bq = $1;
						 [bq setString:[bq stringByReplacingPattern:@"^[\\t]*>[ \\t]?" flags:MD_regex_modifier_m options:0 withTemplate:@""]]; //  $bq =~ s/^[ \t]*>[ \t]?//gm;	# trim one level of quoting
						 [bq setString:[bq stringByReplacingPattern:@"^[ \\t]+$" flags:MD_regex_modifier_m options:0 withTemplate:@""]]; // $bq =~ s/^[ \t]+$//mg;			# trim whitespace-only lines
						 [bq setString:[self runBlockGamut:bq]]; // $bq = _RunBlockGamut($bq);		# recurse
						 
						 [bq insertString:@"  " atIndex:0]; //  $bq =~ s/^/  /g;
						
						 // These leading spaces screw with <pre> content, so we need to fix that:
						 [bq setString:[bq stringByReplacingPattern:@"(\\s*<pre>.+?</pre>)" flags:MD_regex_modifier_s options:0 usingBlock:^(NSArray *bqMatches){
							 NSString *pre = [bqMatches objectAtIndex:1]; //  my $pre = $1;
							 if ([pre hasPrefix:@"  "]) return [pre substringFromIndex:2];  // $pre =~ s/^  //mg;
							 return pre;
						 }]];
						 return [NSString stringWithFormat:@"<blockquote>\n%@\n</blockquote>\n\n", bq];
						 
					 }]];

	return text;
}

- (NSString *)formParagraphs:(NSString *)aString {
	//
	//	Params:
	//		$text - string to process with html <p> tags
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
	
	// Strip leading and trailing lines:
	[text setString:[text stringByReplacingPattern:@"\\A\\n+" flags:0 options:0 withTemplate:@""]]; // $codeblock =~ s/\A\n+//; # trim leading newlines
	[text setString:[text stringByReplacingPattern:@"\\s+\\z" flags:0 options:0 withTemplate:@""]]; // $codeblock =~ s/\s+\z//; 	" //  trim trailing whitespace
	
	[text setString:[text stringByReplacingPattern:@"\\n{3,}" flags:0 options:0 withTemplate:@"\n\n"]];

	NSArray *grafs = [text componentsSeparatedByString:@"\n\n"]; // my @grafs = split(/\n{2,}/, $text);
	
	//
	// Wrap <p> tags.
	//
	NSMutableArray *newGrafs = [NSMutableArray arrayWithCapacity:[grafs count]];
	for (NSString *component in grafs) {					// foreach (@grafs) {
		if (![g_html_blocks objectForKey:component]) {	//		unless (defined( $g_html_blocks{$_} )) {
			NSMutableString *newString  = [NSMutableString stringWithString:[self runSpanGamut:component]]; // $_ = _RunSpanGamut($_);
			[newString setString:[newString stringByReplacingPattern:@"^([ \\t]*)"
															   flags:0
															 options:0
														withTemplate:@"<p>"]]; // s/^([ \t]*)/<p>/;
			[newString appendString:@"</p>"]; // $_ .= "</p>";
			[newGrafs addObject:newString];
		} else {
			[newGrafs addObject:component];
		}
	}
	
	//
	// Unhashify HTML blocks
	//
	NSMutableString *returnString = [NSMutableString stringWithString:@""];
	for (NSString *component in newGrafs) { // foreach (@grafs) {
		[returnString appendString:@"\n\n"];
		if ([g_html_blocks objectForKey:component]) { // if (defined( $g_html_blocks{$_} )) {
			[returnString appendString:[g_html_blocks objectForKey:component]]; // $_ = $g_html_blocks{$_};
		} else {
			[returnString appendString:component];
		}
	}
	return [returnString stringByReplacingCharactersInRange:NSMakeRange(0, 2) withString:@""]; // return join "\n\n", @grafs;
}

- (NSString *)encodeAmpsAndAngles:(NSString *)aString {
	// Smart processing for ampersands and angle brackets that need to be encoded.
	
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
	
	// Ampersand-encoding based entirely on Nat Irons's Amputator MT plugin:
	//   http://bumppo.net/projects/amputator/
	
	[text setString:[text stringByReplacingPattern:@"&(?!#?[xX]?(?:[0-9a-fA-F]+|\\w+);)"
											 flags:0
										   options:0
									  withTemplate:@"&amp;"]]; // $text =~ s/&(?!	" // ?[xX]?(?:[0-9a-fA-F]+|\w+);)/&amp;/g;
	
	// Encode naked <'s 	
	[text setString:[text stringByReplacingPattern:@"<(?![a-z/?\\$!])"
											 flags:MD_regex_modifier_i
										   options:0
									  withTemplate:@"&lt;"]]; // $text =~ s{<(?![a-z/?\$!])}{&lt;}gi;
	
	return text;
}

- (NSString *)encodeBackslashEscapes:(NSString *)aString {
	//
	//   Parameter:  String.
	//   Returns:    The string, with after processing the following backslash
	//               escape sequences.
	//
   
//	 s! \\\\  !$g_escape_table{'\\'}!gx;
//    s! \\`   !$g_escape_table{'`'}!gx;
//    s! \\\*  !$g_escape_table{'*'}!gx;
//    s! \\_   !$g_escape_table{'_'}!gx;
//    s! \\\{  !$g_escape_table{'{'}!gx;
//	s! \\\}  !$g_escape_table{'}'}!gx;
//    s! \\\[  !$g_escape_table{'['}!gx;
//	s! \\\]  !$g_escape_table{']'}!gx;
//    s! \\\(  !$g_escape_table{'('}!gx;
//	s! \\\)  !$g_escape_table{')'}!gx;
//    s! \\>   !$g_escape_table{'>'}!gx;
//    s! \\\#  !$g_escape_table{'#'}!gx;
//    s! \\\+  !$g_escape_table{'+'}!gx;
//    s! \\\-  !$g_escape_table{'-'}!gx;
//    s! \\\.  !$g_escape_table{'.'}!gx;
//    s{ \\!  }{$g_escape_table{'!'}}gx;
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
	[text replaceOccurrencesOfString:@"\\\\" withString:[g_escape_table objectForKey:@"\\"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\`" withString:[g_escape_table objectForKey:@"`"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\*" withString:[g_escape_table objectForKey:@"*"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\_" withString:[g_escape_table objectForKey:@"_"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\{" withString:[g_escape_table objectForKey:@"{"] options:0 range:NSMakeRange(0, [text length])];
	[text replaceOccurrencesOfString:@"\\}" withString:[g_escape_table objectForKey:@"}"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\[" withString:[g_escape_table objectForKey:@"["] options:0 range:NSMakeRange(0, [text length])];
	[text replaceOccurrencesOfString:@"\\]" withString:[g_escape_table objectForKey:@"]"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\(" withString:[g_escape_table objectForKey:@"("] options:0 range:NSMakeRange(0, [text length])];
	[text replaceOccurrencesOfString:@"\\)" withString:[g_escape_table objectForKey:@")"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\>" withString:[g_escape_table objectForKey:@">"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\#" withString:[g_escape_table objectForKey:@"#"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\+" withString:[g_escape_table objectForKey:@"+"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\-" withString:[g_escape_table objectForKey:@"-"] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\." withString:[g_escape_table objectForKey:@"."] options:0 range:NSMakeRange(0, [text length])];
    [text replaceOccurrencesOfString:@"\\!" withString:[g_escape_table objectForKey:@"!"] options:0 range:NSMakeRange(0, [text length])];
	
    return text;
}

- (NSString *)doAutoLinks:(NSString *)aString {
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;
	
	[text setString:[text stringByReplacingPattern:@"<((https?|ftp):[^'\">\\s]+)>"
											  flags:MD_regex_modifier_i
										   options:0
									  withTemplate:@"<a href=\"$1\">$1</a>"]]; // $text =~ s{<((https?|ftp):[^'">\s]+)>}{<a href="$1">$1</a>}gi;
	// Email addresses: <address@domain.foo>
	[text setString:[text stringByReplacingPattern:
					 @"		<"
					 "        (?:mailto:)?"
					 "		("
					 "			[-.\\w]+"
					 "			\\@"
					 "			[-a-z0-9]+(\\.[-a-z0-9]+)*\\.[a-z]+"
					 "		)"
					 "		>"
					 
											 flags:MD_regex_modifier_i | MD_regex_modifier_x
										   options:0 usingBlock:^(NSArray *matches)
					 {
						 return [self encodeEmailAddress:[self unescapeSpecialChars:[matches objectAtIndex:1]]]; // _EncodeEmailAddress( _UnescapeSpecialChars($1) );
						 
					 }]];
	
	return text;
}


- (NSString *)encodeEmailAddress:(NSString *)aString {
	//
	//	Input: an email address, e.g. "foo@example.com"
	//
	//	Output: the email address as a mailto link, with each character
	//		of the address encoded as either a decimal or hex entity, in
	//		the hopes of foiling most address harvesting spam bots. E.g.:
	//
	//	  <a href="&#x6D;&#97;&#105;&#108;&#x74;&#111;:&#102;&#111;&#111;&#64;&#101;
	//       x&#x61;&#109;&#x70;&#108;&#x65;&#x2E;&#99;&#111;&#109;">&#102;&#111;&#111;
	//       &#64;&#101;x&#x61;&#109;&#x70;&#108;&#x65;&#x2E;&#99;&#111;&#109;</a>
	//
	//	Based on a filter by Matthew Wickline, posted to the BBEdit-Talk
	//	mailing list: <http://tinyurl.com/yu7ue>
	//
	
	NSMutableString *text = [NSMutableString stringWithString:aString];	// local $_ = shift;

	// We'll skip this for now. 
	return [NSString stringWithFormat:@"<a href=\"mailto:%@\">%@</a>", text, text];
	
//	my $addr = shift;
//	
//	srand;
//	my @encode = (
//				  sub { '&#' .                 ord(shift)   . ';' },
//				  sub { '&#x' . sprintf( "%X", ord(shift) ) . ';' },
//				  sub {                            shift          },
//				  );
//	
//	$addr = "mailto:" . $addr;
//	
//	$addr =~ s{(.)}{
//		my $char = $1;
//		if ( $char eq '@' ) {
//			// this *must* be encoded. I insist.
//			$char = $encode[int rand 1]->($char);
//		} elsif ( $char ne ':' ) {
//			// leave ':' alone (to spot mailto: later)
//			my $r = rand;
//			// roughly 10% raw, 45% hex, 45% dec
//			$char = (
//					 $r > .9   ?  $encode[2]->($char)  :
//					 $r < .45  ?  $encode[1]->($char)  :
//					 $encode[0]->($char)
//					 );
//		}
//		$char;
//	}gex;
//	
//	$addr = qq{<a href="$addr">$addr</a>};
//	$addr =~ s{">.+?:}{">}; # strip the mailto: from the visible part
//	
//	return $addr;
}

- (NSString *)unescapeSpecialChars:(NSString *)aString {
	//
	// Swap back in all the special characters we've hidden.
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	
	for (NSString *key in [g_escape_table allKeys]) { // while( my($char, $hash) = each(%g_escape_table) ) {
		[text replaceOccurrencesOfString:[g_escape_table objectForKey:key]
							  withString:key
								 options:0
								   range:NSMakeRange(0, [text length])]; // $text =~ s/$hash/$char/g;
	}
    return text;
}

- (NSArray *)tokenizeHTML:(NSString *)aString {
	//
	//   Parameter:  String containing HTML markup.
	//   Returns:    Reference to an array of the tokens comprising the input
	//               string. Each token is either a tag (possibly with nested,
	//               tags contained therein, such as <a href="<MTFoo>">, or a
	//               run of text between tags. Each element of the array is a
	//               two-element array; the first is either 'tag' or 'text';
	//               the second is the actual value.
	//
	//
	//   Derived from the _tokenize() subroutine from Brad Choate's MTRegex plugin.
	//       <http://www.bradchoate.com/past/mtregex.php>
	//
	
	NSMutableString *str = [NSMutableString stringWithString:aString];	//  my $str = shift;
   
    NSUInteger pos = 0; // my $pos = 0;
    NSUInteger len = [str length];// my $len = length $str;
    NSMutableArray *tokens = [NSMutableArray arrayWithCapacity:100];		// my @tokens;
	
    int depth = 6; // my $depth = 6;
   //my $nested_tags = join('|', ('(?:<[a-z/!$](?:[^<>]') x $depth) . (')*>)' x  $depth);
	NSMutableString *nested_tags = [NSMutableString stringWithString:@""];
	for (int i = 0; i < depth; i++) {
		[nested_tags appendString:@"(?:<[a-z/!$](?:[^<>]"];
		if (i < (depth - 1)) {
			[nested_tags appendString:@"|"];
		}
	}
	for (int i = 0; i < depth; i++) [nested_tags appendString:@")*>)"];
	
	NSError *regexError;
	NSString *matchString = [NSString stringWithFormat:
					   @"((?s: <! ( -- .*? -- \\s* )+ > ) |  	" //  comment
					   "                   (?s: <\\? .*? \\?> ) |              	" //  processing instruction
					   "                   %@)", nested_tags]; // my $match = qr/(?s: <! ( -- .*? -- \s* )+ > ) |  # comment (?s: <\? .*? \?> ) |              # processing instruction $nested_tags/ix;                   	" //  nested tags
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:matchString options:MD_regex_modifier_x | MD_regex_modifier_i error:&regexError];
	
	NSArray *matches = [regex matchesInString:str options:0 range:NSMakeRange(0, [str length])];
	
	for (NSTextCheckingResult *match in matches) { // while ($str =~ m/($match)/g) {
		NSRange matchRange = [match rangeAtIndex:0];
		NSString *whole_tag = [str substringWithRange:[match rangeAtIndex:1]]; // my $whole_tag = $1;
		
		NSUInteger sec_start = matchRange.location + matchRange.length; // my $sec_start = pos $str;

		NSUInteger tag_start = matchRange.location; // my $tag_start = $sec_start - length $whole_tag;
                
        if (pos < tag_start) {
			[tokens addObject:[NSArray arrayWithObjects: @"text", [str substringWithRange:NSMakeRange(pos, tag_start - pos)], nil]]; // push @tokens, ['text', substr($str, $pos, $tag_start - $pos)];
            
        }
		[tokens addObject:[NSArray arrayWithObjects: @"tag", whole_tag, nil]]; // push @tokens, ['tag', $whole_tag]
        pos = sec_start;
    }
	[tokens addObject:[NSArray arrayWithObjects: @"text", [str substringWithRange:NSMakeRange(pos, len - pos)], nil]]; // push @tokens, ['tag', $whole_tag]
	return tokens;
}

- (NSString *)outdent:(NSString *)aString {
	//
	// Remove one level of line-leading tabs or spaces
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	return [text stringByReplacingPattern:[NSString stringWithFormat:
										   @"^(\\t|[ ]{1,%i})",
										   MD_g_tab_width ]
															   flags:MD_regex_modifier_m
															 options:0
														withTemplate:@""]; // $text =~ s/^(\t|[ ]{1,$g_tab_width})//gm;
}

- (NSString *)detab:(NSString *)aString {
	//
	// Cribbed from a post by Bart Lateur:
	// <http://www.nntp.perl.org/group/perl.macperl.anyperl/154>
	//
	NSMutableString *text = [NSMutableString stringWithString:aString];	// my $text = shift;
	return [text stringByReplacingPattern:@"(.*?)\\t"
									flags:MD_regex_modifier_m
								  options:0 usingBlock:^(NSArray *matches)
			{
				//$1.(' ' x ($g_tab_width - length($1) % $g_tab_width))
				NSString *component = [matches objectAtIndex:1];
				NSMutableString *returnString = [NSMutableString stringWithString:component];
				int count = MD_g_tab_width - [component length] % MD_g_tab_width;
				for (int i = 0; i < count; i++) {
					[returnString appendString:@" "];
				}
				return returnString;
			}]; // 	$text =~ s{(.*?)\t}{$1.(' ' x ($g_tab_width - length($1) % $g_tab_width))}ge;
}


@end
