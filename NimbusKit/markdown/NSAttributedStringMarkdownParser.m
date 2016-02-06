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

#import "NSAttributedStringMarkdownParser.h"

#import "MarkdownTokens.h"
#import "fmemopen.h"

#import <CoreText/CoreText.h>
#import <pthread.h>

static NSRegularExpression *_hrefRegex = nil;
static inline NSRegularExpression* hrefRegex(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _hrefRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[(.*?)\\]\\((\\S+)(\\s+(\"|\')(.*?)(\"|\'))?\\)"
                                                               options:NSRegularExpressionCaseInsensitive
                                                                 error:nil];
    });

    return _hrefRegex;
}

int markdownConsume(char* text, int token, yyscan_t scanner);

@interface NSAttributedStringMarkdownLink()
@property (nonatomic, strong) NSURL* url;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, copy) NSString *tooltip;
@end

@implementation NSAttributedStringMarkdownLink
@end

@implementation NSAttributedStringMarkdownParser {
  NSMutableDictionary* _headerFonts;

  NSMutableArray* _bulletStarts;

  NSMutableAttributedString* _accum;
  NSMutableArray* _links;

  UINSFont* _topFont;
  NSMutableDictionary* _fontCache;
}

- (id)init {
  if ((self = [super init])) {
    _headerFonts = [NSMutableDictionary dictionary];

    self.paragraphFont = [UINSFont systemFontOfSize:12];
    self.boldFontName = [UINSFont boldSystemFontOfSize:12].fontName;
    self.italicFontName = @"Helvetica-Oblique";
    self.boldItalicFontName = @"Helvetica-BoldOblique";
    self.codeFontName = @"Courier";

    NSAttributedStringMarkdownParserHeader header = NSAttributedStringMarkdownParserHeader1;
    for (CGFloat headerFontSize = 24; headerFontSize >= 14; headerFontSize -= 2, header++) {
      [self setFont:[UINSFont systemFontOfSize:headerFontSize] forHeader:header];
    }
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  NSAttributedStringMarkdownParser* parser = [[self.class allocWithZone:zone] init];
  parser.paragraphFont = self.paragraphFont;
  parser.boldFontName = self.boldFontName;
  parser.italicFontName = self.italicFontName;
  parser.boldItalicFontName = self.boldItalicFontName;
  parser.codeFontName = self.codeFontName;
  for (NSAttributedStringMarkdownParserHeader header = NSAttributedStringMarkdownParserHeader1; header <= NSAttributedStringMarkdownParserHeader6; ++header) {
    [parser setFont:[self fontForHeader:header] forHeader:header];
  }
  return parser;
}

- (id)keyForHeader:(NSAttributedStringMarkdownParserHeader)header {
  return @(header);
}

- (void)setFont:(UINSFont *)font forHeader:(NSAttributedStringMarkdownParserHeader)header {
  _headerFonts[[self keyForHeader:header]] = font;
}

- (UINSFont *)fontForHeader:(NSAttributedStringMarkdownParserHeader)header {
  return _headerFonts[[self keyForHeader:header]];
}

- (NSAttributedString *)attributedStringFromMarkdownString:(NSString *)string {
  _links = [NSMutableArray array];
  _bulletStarts = [NSMutableArray array];
  _accum = [[NSMutableAttributedString alloc] init];

  const char* cstr = [string UTF8String];
  FILE* markdownin = fmemopen((void *)cstr, [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding], "r");

  yyscan_t scanner;

  markdownlex_init(&scanner);
  markdownset_extra((__bridge void *)(self), scanner);
  markdownset_in(markdownin, scanner);
  markdownlex(scanner);
  markdownlex_destroy(scanner);

  fclose(markdownin);

  if (_bulletStarts.count > 0) {
    // Treat nested bullet points as flat ones...

    // Finish off the previous dash and start a new one.
    NSInteger lastBulletStart = [[_bulletStarts lastObject] intValue];
    [_bulletStarts removeLastObject];
    
    [_accum addAttributes:[self paragraphStyle]
                        range:NSMakeRange(lastBulletStart, _accum.length - lastBulletStart)];
  }

#if TARGET_OS_MAC
  const BOOL shouldAddLinks = YES;
#elif __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
  const BOOL shouldAddLinks = (NSLinkAttributeName != nil);
#endif
    
  if (shouldAddLinks) {
    [self addLinksToAttributedString];
  }

  return [_accum copy];
}

- (void)addLinksToAttributedString {
#if TARGET_OS_MAC || __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
  for (NSAttributedStringMarkdownLink *link in _links) {
    if (link.url) {
      [_accum addAttribute:NSLinkAttributeName value:link.url range:link.range];
    }
  }
#endif
}

- (NSArray *)links {
  return [_links copy];
}

- (NSDictionary *)paragraphStyle {
  CGFloat paragraphSpacing = 0.0;
  CGFloat paragraphSpacingBefore = 0.0;
  CGFloat firstLineHeadIndent = 15.0;
  CGFloat headIndent = 30.0;

  CGFloat firstTabStop = 35.0; // width of your indent
  CGFloat lineSpacing = 0.45;

#ifdef TARGET_OS_IPHONE
  NSTextAlignment alignment = NSTextAlignmentLeft;

  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.paragraphSpacing = paragraphSpacing;
  style.paragraphSpacingBefore = paragraphSpacingBefore;
  style.firstLineHeadIndent = firstLineHeadIndent;
  style.headIndent = headIndent;
  style.lineSpacing = lineSpacing;
  style.alignment = alignment;
  style.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:alignment location:firstTabStop options:nil]];

  return @{ NSParagraphStyleAttributeName: style };
#else
  CTTextAlignment alignment = kCTLeftTextAlignment;

  CTTextTabRef tabArray[] = { CTTextTabCreate(0, firstTabStop, NULL) };

  CFArrayRef tabStops = CFArrayCreate( kCFAllocatorDefault, (const void**) tabArray, 1, &kCFTypeArrayCallBacks );
  CFRelease(tabArray[0]);

  CTParagraphStyleSetting altSettings[] =
  {
    { kCTParagraphStyleSpecifierLineSpacing, sizeof(CGFloat), &lineSpacing},
    { kCTParagraphStyleSpecifierAlignment, sizeof(CTTextAlignment), &alignment},
    { kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat), &firstLineHeadIndent},
    { kCTParagraphStyleSpecifierHeadIndent, sizeof(CGFloat), &headIndent},
    { kCTParagraphStyleSpecifierTabStops, sizeof(CFArrayRef), &tabStops},
    { kCTParagraphStyleSpecifierParagraphSpacing, sizeof(CGFloat), &paragraphSpacing},
    { kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(CGFloat), &paragraphSpacingBefore}
  };

  CTParagraphStyleRef style;
  style = CTParagraphStyleCreate( altSettings, sizeof(altSettings) / sizeof(CTParagraphStyleSetting) );

  if ( style == NULL )
  {
    NSLog(@"*** Unable To Create CTParagraphStyle in apply paragraph formatting" );
    return nil;
  }

  return [NSDictionary dictionaryWithObjectsAndKeys:(__bridge id)style,(NSString*) kCTParagraphStyleAttributeName, nil];
#endif
}

- (UINSFont *)topFont {
  if (nil == _topFont) {
    return self.paragraphFont;
  } else {
    return _topFont;
  }
}

- (id)keyForFontWithName:(NSString *)fontName pointSize:(CGFloat)pointSize {
  return [fontName stringByAppendingFormat:@"%f", pointSize];
}

- (CTFontRef)fontRefForFontWithName:(NSString *)fontName pointSize:(CGFloat)pointSize {
  id key = [self keyForFontWithName:fontName pointSize:pointSize];
  NSValue* value = _fontCache[key];
  if (nil == value) {
    CTFontRef fontRef = CTFontCreateWithName((__bridge CFStringRef)fontName, pointSize, nil);
    value = [NSValue valueWithPointer:fontRef];
    _fontCache[key] = value;
  }
  return [value pointerValue];
}

- (NSDictionary *)attributesForFontWithName:(NSString *)fontName {
    return @{NSFontAttributeName: [UINSFont fontWithName:fontName size:self.topFont.pointSize]};
}

- (NSDictionary *)attributesForFont:(UINSFont *)font {
    return @{NSFontAttributeName: font};
}

- (void)recurseOnString:(NSString *)string withFont:(UINSFont *)font {
  NSAttributedStringMarkdownParser* recursiveParser = [self copy];
  recursiveParser->_topFont = font;
  [_accum appendAttributedString:[recursiveParser attributedStringFromMarkdownString:string]];

  // Adjust the recursive parser's links so that they are offset correctly.
  for (NSAttributedStringMarkdownLink *currentLink in recursiveParser.links) {
    NSRange range = [currentLink range];
    range.location += _accum.length;
    currentLink.range = range;
    [_links addObject:currentLink];
  }
}

- (void)consumeToken:(int)token text:(char*)text {
  NSString* textAsString = [[NSString alloc] initWithCString:text encoding:NSUTF8StringEncoding];

  NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
  [attributes addEntriesFromDictionary:[self attributesForFont:self.topFont]];

  switch (token) {
    case MARKDOWNEM: { // * *
      textAsString = [textAsString substringWithRange:NSMakeRange(1, textAsString.length - 2)];
      [attributes addEntriesFromDictionary:[self attributesForFontWithName:self.italicFontName]];
      break;
    }
    case MARKDOWNSTRONG: { // ** **
      textAsString = [textAsString substringWithRange:NSMakeRange(2, textAsString.length - 4)];
      [attributes addEntriesFromDictionary:[self attributesForFontWithName:self.boldFontName]];
      break;
    }
    case MARKDOWNSTRONGEM: { // *** ***
      textAsString = [textAsString substringWithRange:NSMakeRange(3, textAsString.length - 6)];
      [attributes addEntriesFromDictionary:[self attributesForFontWithName:self.boldItalicFontName]];
      break;
    }
    case MARKDOWNSTRIKETHROUGH: { // ~~ ~~
      textAsString = [textAsString substringWithRange:NSMakeRange(2, textAsString.length - 4)];
      [attributes addEntriesFromDictionary:@{NSStrikethroughStyleAttributeName : @(NSUnderlineStyleSingle)}];
      break;
    }
    case MARKDOWNCODESPAN: { // ` `
      textAsString = [textAsString substringWithRange:NSMakeRange(1, textAsString.length - 2)];
      [attributes addEntriesFromDictionary:[self attributesForFontWithName:self.italicFontName]];
      break;
    }
    case MARKDOWNHEADER: { // ####
      NSRange rangeOfNonHash = [textAsString rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"#"] invertedSet]];
      if (rangeOfNonHash.length > 0) {
        textAsString = [[textAsString substringFromIndex:rangeOfNonHash.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        NSAttributedStringMarkdownParserHeader header = (NSAttributedStringMarkdownParserHeader)(rangeOfNonHash.location - 1);
        [self recurseOnString:textAsString withFont:[self fontForHeader:header]];

        // We already appended the recursive parser's results in recurseOnString.
        textAsString = nil;
      }
      break;
    }
    case MARKDOWNMULTILINEHEADER: {
      NSArray* components = [textAsString componentsSeparatedByString:@"\n"];
      textAsString = [components objectAtIndex:0];
      UINSFont* font = nil;
      if ([[components objectAtIndex:1] rangeOfString:@"="].length > 0) {
        font = [self fontForHeader:NSAttributedStringMarkdownParserHeader1];
      } else if ([[components objectAtIndex:1] rangeOfString:@"-"].length > 0) {
        font = [self fontForHeader:NSAttributedStringMarkdownParserHeader2];
      }

      [self recurseOnString:textAsString withFont:font];

      // We already appended the recursive parser's results in recurseOnString.
      textAsString = nil;
      break;
    }
    case MARKDOWNPARAGRAPH: {
      textAsString = @"\n\n";
      
      if (_bulletStarts.count > 0) {
        // Treat nested bullet points as flat ones...
        
        // Finish off the previous dash and start a new one.
        NSInteger lastBulletStart = [[_bulletStarts lastObject] intValue];
        [_bulletStarts removeLastObject];
        
        [_accum addAttributes:[self paragraphStyle]
                            range:NSMakeRange(lastBulletStart, _accum.length - lastBulletStart)];
      }
      break;
    }
    case MARKDOWNBULLETSTART: {
      NSInteger numberOfDashes = [textAsString rangeOfString:@" "].location;
      if (_bulletStarts.count > 0 && _bulletStarts.count <= numberOfDashes) {
        // Treat nested bullet points as flat ones...

        // Finish off the previous dash and start a new one.
        NSInteger lastBulletStart = [[_bulletStarts lastObject] intValue];
        [_bulletStarts removeLastObject];

        [_accum addAttributes:[self paragraphStyle]
                            range:NSMakeRange(lastBulletStart, _accum.length - lastBulletStart)];
      }

      [_bulletStarts addObject:@(_accum.length)];
      textAsString = @"•\t";
      break;
    }
    case MARKDOWNNEWLINE: {
      textAsString = @"";
      break;
    }
    case MARKDOWNURL: {
      NSAttributedStringMarkdownLink* link = [[NSAttributedStringMarkdownLink alloc] init];
      link.url = [NSURL URLWithString:textAsString];
      link.range = NSMakeRange(_accum.length, textAsString.length);
      [_links addObject:link];
      break;
    }
      case MARKDOWNHREF: { // [Title] (url "tooltip")
          NSTextCheckingResult *result = [hrefRegex() firstMatchInString:textAsString options:0 range:NSMakeRange(0, textAsString.length)];

          NSRange linkTitleRange = [result rangeAtIndex:1];
          NSRange linkURLRange = [result rangeAtIndex:2];
          NSRange tooltipRange = [result rangeAtIndex:5];

          if (linkTitleRange.location != NSNotFound && linkURLRange.location != NSNotFound) {
              NSAttributedStringMarkdownLink *link = [[NSAttributedStringMarkdownLink alloc] init];

              link.url = [NSURL URLWithString:[textAsString substringWithRange:linkURLRange]];
              link.range = NSMakeRange(_accum.length, linkTitleRange.length);

              if (tooltipRange.location != NSNotFound) {
                  link.tooltip = [textAsString substringWithRange:tooltipRange];
              }

              [_links addObject:link];
              textAsString = [textAsString substringWithRange:linkTitleRange];
          }
          break;
      }
    default: {
      break;
    }
  }

  if (textAsString.length > 0) {
    NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:textAsString attributes:attributes];
    [_accum appendAttributedString:attributedString];
  }
}

@end

int markdownConsume(char* text, int token, yyscan_t scanner) {
  NSAttributedStringMarkdownParser* string = (__bridge NSAttributedStringMarkdownParser *)(markdownget_extra(scanner));
  [string consumeToken:token text:text];
  return 0;
}
