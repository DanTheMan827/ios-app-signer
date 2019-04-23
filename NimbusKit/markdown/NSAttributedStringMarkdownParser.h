//
// Copyright 2011-2014 NimbusKit
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
  #import <UIKit/UIKit.h>
  #define UINSFont UIFont
#else
  #import <AppKit/AppKit.h>
  #define UINSFont NSFont
#endif

typedef enum {
  NSAttributedStringMarkdownParserHeader1,
  NSAttributedStringMarkdownParserHeader2,
  NSAttributedStringMarkdownParserHeader3,
  NSAttributedStringMarkdownParserHeader4,
  NSAttributedStringMarkdownParserHeader5,
  NSAttributedStringMarkdownParserHeader6,

} NSAttributedStringMarkdownParserHeader;

@protocol NSAttributedStringMarkdownStylesheet;

@interface NSAttributedStringMarkdownLink : NSObject
@property (nonatomic, readonly, strong) NSURL* url;
@property (nonatomic, readonly, assign) NSRange range;
@property (nonatomic, readonly, copy) NSString *tooltip;
@end

/**
 * The NSAttributedStringMarkdownParser class parses a given markdown string into an
 * NSAttributedString.
 *
 * @ingroup NimbusMarkdown
 */
@interface NSAttributedStringMarkdownParser : NSObject <NSCopying>

- (NSAttributedString *)attributedStringFromMarkdownString:(NSString *)string;
- (NSArray *)links; // Array of NSAttributedStringMarkdownLink

@property (nonatomic, strong) UINSFont* paragraphFont; // Default: systemFontOfSize:12
@property (nonatomic, copy) NSString* boldFontName; // Default: boldSystemFont
@property (nonatomic, copy) NSString* italicFontName; // Default: Helvetica-Oblique
@property (nonatomic, copy) NSString* boldItalicFontName; // Default: Helvetica-BoldOblique
@property (nonatomic, copy) NSString* codeFontName; // Default: Courier

- (void)setFont:(UINSFont *)font forHeader:(NSAttributedStringMarkdownParserHeader)header;
- (UINSFont *)fontForHeader:(NSAttributedStringMarkdownParserHeader)header;

@end
