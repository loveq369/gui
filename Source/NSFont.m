/** <title>NSFont</title>

   <abstract>The font class</abstract>

   Copyright (C) 1996 Free Software Foundation, Inc.

   Author: Ovidiu Predescu <ovidiu@net-community.com>
   Date: February 1997
   A completely rewritten version of the original source by Scott Christley.
   
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/ 

#include <gnustep/gui/config.h>
#include <Foundation/NSString.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSSet.h>
#include <Foundation/NSMapTable.h>
#include <Foundation/NSException.h>

#include <AppKit/NSGraphicsContext.h>
#include <AppKit/NSFont.h>
#include <AppKit/NSFontManager.h>
#include <AppKit/GSFontInfo.h>
#include <AppKit/NSView.h>

/* We cache all the 4 default fonts after we first get them.
   But when a default font is changed, the variable is set to YES 
   so all default fonts are forced to be recomputed. */
static BOOL systemCacheNeedsRecomputing = NO;
static BOOL boldSystemCacheNeedsRecomputing = NO;
static BOOL userCacheNeedsRecomputing = NO;
static BOOL userFixedCacheNeedsRecomputing = NO;
static NSFont	*placeHolder = nil;

@interface NSFont (Private)
- (id) initWithName: (NSString*)name 
	     matrix: (const float*)fontMatrix
	        fix: (BOOL)explicitlySet;
@end

static int currentVersion = 2;

/*
 * Just to ensure that we use a standard name in the cache.
 */
static NSString*
newNameWithMatrix(NSString *name, const float *matrix, BOOL fix)
{
  NSString	*nameWithMatrix;

  nameWithMatrix = [[NSString alloc] initWithFormat:
    @"%@ %.3f %.3f %.3f %.3f %.3f %.3f %c", name,
    matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5],
    (fix == NO) ? 'N' : 'Y'];
  return nameWithMatrix;
}

/**
  <unit>
  <heading>NSFont</heading>

  <p>The NSFont class allows control of the fonts used for displaying
  text anywhere on the screen. The primary methods for getting a
  particular font are -fontWithName:matrix: and -fontWithName:size: which
  take the name and size of a particular font and return the NSFont object
  associated with that font. In addition there are several convenience
  mathods which make it easier to get certain types of fonts. </p>
  
  <p>In particular, there are several methods to get the standard fonts
  used by the Application to display text for a partiuclar purpose. See
  the class methods listed below for more information. These default
  fonts can be set using the user defaults system. The default
  font names available are:
  </p>
  <list>
    <item>NSBoldFont                Helvetica-Bold</item>
    <item>NSControlContentFont      Helvetica</item>
    <item>NSFont                    Helvetica (System Font)</item>
    <item>NSLabelFont               Helvetica</item>
    <item>NSMenuFont                Helvetica</item>
    <item>NSMessageFont             Helvetica</item>
    <item>NSPaletteFont             Helvetica-Bold</item>
    <item>NSTitleBarFont            Helvetica-Bold</item>
    <item>NSToolTipsFont            Helvetica</item>
    <item>NSUserFixedPitchFont      Courier</item>
    <item>NSUserFont                Helvetica</item>
  </list>
  <p>
  The default sizes are:
  </p>
  <list>
    <item>NSBoldFontSize            (none)</item>
    <item>NSControlContentFontSize  (none)</item>
    <item>NSFontSize                12 (System Font Size)</item>
    <item>NSLabelFontSize           12</item>
    <item>NSMenuFontSize            (none)</item>
    <item>NSMessageFontSize         (none)</item>
    <item>NSPaletteFontSize         (none)</item>
    <item>NSSmallFontSize           9</item>
    <item>NSTitleBarFontSize        (none)</item>
    <item>NSToolTipsFontSize        (none)</item>
    <item>NSUserFixedPitchFontSize  (none)</item>
    <item>NSUserFontSize            (none)</item>
  </list>
  <p>
  Font sizes list with (none) default to NSFontSize.
  </p>

  </unit> */
  
@implementation NSFont

/* Class variables*/

/* Fonts that are preferred by the application */
NSArray *_preferredFonts;

/* Class for fonts */
static Class	NSFontClass = 0;

/* Cache all created fonts for reuse. */
static NSMapTable* globalFontMap = 0;

static NSUserDefaults	*defaults = nil;

NSFont*
getNSFont(NSString* key, NSString* defaultFontName, float fontSize)
{
  NSString* fontName;

  fontName = [defaults objectForKey: key];
  if (fontName == nil)
    fontName = defaultFontName;

  if (fontSize == 0)
    {
      fontSize = [defaults floatForKey:
	[NSString stringWithFormat: @"%@Size", key]];
    }

  return [NSFontClass fontWithName: fontName size: fontSize];
}

void
setNSFont(NSString* key, NSFont* font)
{
  [defaults setObject: [font fontName] forKey: key];

  systemCacheNeedsRecomputing = YES;
  boldSystemCacheNeedsRecomputing = YES;
  userCacheNeedsRecomputing = YES;
  userFixedCacheNeedsRecomputing = YES;

  /* Don't care about errors */
  [defaults synchronize];
}

//
// Class methods
//
+ (void) initialize
{
  if (self == [NSFont class])
    {
      NSFontClass = self;

      /*
       * The placeHolder is a dummy NSFont instance which is never used
       * as a font ... the initialiser knows that whenever it gets the
       * placeHolder it should either return a cached font or return a
       * newly allocated font to replace it.  This mechanism stops the
       * +fontWithName:... methods from having to allocete fonts instances
       * which would immediately have to be released for replacement by
       * a cache object.
       */
      placeHolder = [self alloc];
      globalFontMap = NSCreateMapTable(NSObjectMapKeyCallBacks,
	NSNonRetainedObjectMapValueCallBacks, 64);

      if (defaults == nil)
	{
	  defaults = RETAIN([NSUserDefaults standardUserDefaults]);
	}

      [self setVersion: currentVersion];
    }
}

/* Getting the preferred user fonts.  */

/** 
 * Return the default bold font for use in menus and heading in standard
 * gui components.<br />
 * This is deprecated in MacOSX
 */
+ (NSFont*) boldSystemFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSBoldFont", @"Helvetica-Bold", fontSize);
    }
  else
    {
      if ((font == nil) || (boldSystemCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSBoldFont", @"Helvetica-Bold", 0));
	  boldSystemCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

/** 
 * Return the default font for use in menus and heading in standard
 * gui components.<br />
 * This is deprecated in MacOSX
 */
+ (NSFont*) systemFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (systemCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSFont", @"Helvetica", 0));
	  systemCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

/** 
 * Return the default fixed pitch font for use in locations other
 * than standard gui components.
 */
+ (NSFont*) userFixedPitchFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSUserFixedPitchFont", @"Courier", fontSize);
    }
  else
    {
      if ((font == nil) || (userFixedCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSUserFixedPitchFont", @"Courier", 0));
	  userFixedCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

/** 
 * Return the default font for use in locations other
 * than standard gui components.
 */
+ (NSFont*) userFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSUserFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (userCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSUserFont", @"Helvetica", 0));
	  userCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

/** 
 * Return an array of the names of preferred fonts.
 */
+ (NSArray*) preferredFontNames
{
  return _preferredFonts;
}

/* Setting the preferred user fonts*/

+ (void) setUserFixedPitchFont: (NSFont*)aFont
{
  setNSFont (@"NSUserFixedPitchFont", aFont);
}

+ (void) setUserFont: (NSFont*)aFont
{
  setNSFont (@"NSUserFont", aFont);
}

+ (void) setPreferredFontNames: (NSArray*)fontNames
{
  ASSIGN(_preferredFonts, fontNames);
}

/* Getting various fonts*/

+ (NSFont*) controlContentFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSControlContentFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (userCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSControlContentFont", @"Helvetica", 0));
	  userCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

+ (NSFont*) labelFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSLabelFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (userCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSLabelFont", @"Helvetica", 0));
	  userCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

+ (NSFont*) menuFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSMenuFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (userCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSMenuFont", @"Helvetica", 0));
	  userCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

+ (NSFont*) titleBarFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSTitleBarFont", @"Helvetica-Bold", fontSize);
    }
  else
    {
      if ((font == nil) || (boldSystemCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSTitleBarFont", @"Helvetica-Bold", 0));
	  boldSystemCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

+ (NSFont*) messageFontOfSize: (float)fontSize
{
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSMessageFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (userCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSMessageFont", @"Helvetica", 0));
	  userCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

+ (NSFont*) paletteFontOfSize: (float)fontSize
{
  // Not sure on this one.
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSPaletteFont", @"Helvetica-Bold", fontSize);
    }
  else
    {
      if ((font == nil) || (boldSystemCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSPaletteFont", @"Helvetica-Bold", 0));
	  boldSystemCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

+ (NSFont*) toolTipsFontOfSize: (float)fontSize
{
  // Not sure on this one.
  static NSFont *font = nil;

  if (fontSize != 0)
    {
      return getNSFont (@"NSToolTipsFont", @"Helvetica", fontSize);
    }
  else
    {
      if ((font == nil) || (userCacheNeedsRecomputing == YES))
	{
	  ASSIGN (font, getNSFont (@"NSToolTipsFont", @"Helvetica", 0));
	  userCacheNeedsRecomputing = NO;
	}
      return font;
    }
}

//
// Font Sizes
//
+ (float) labelFontSize
{
  float fontSize = [defaults floatForKey: @"NSLabelFontSize"];
  
  if (fontSize == 0)
    {
      fontSize = 12;
    }

  return fontSize;
}

+ (float) smallSystemFontSize
{
  float fontSize = [defaults floatForKey: @"NSSmallFontSize"];
  
  if (fontSize == 0)
    {
      fontSize = 9;
    }

  return fontSize;
}

+ (float) systemFontSize
{
  float fontSize = [defaults floatForKey: @"NSFontSize"];
  
  if (fontSize == 0)
    {
      fontSize = 12;
    }

  return fontSize;
}

/**
 * Returns an autoreleased font with name aFontName and matrix fontMatrix.<br />
 * The fontMatrix is a standard size element matrix as used in PostScript
 * to describe the scaling of the font, typically it just includes
 * the font size as [fontSize 0 0 fontSize 0 0].  You can use the constant
 * NSFontIdentityMatrix in place of [1 0 0 1 0 0]. If NSFontIdentityMatrix, 
 * then the font will automatically flip itself when set in a flipped view.
 */
+ (NSFont*) fontWithName: (NSString*)aFontName 
		  matrix: (const float*)fontMatrix
{
  NSFont	*font;
  BOOL		fix;

  if (fontMatrix == NSFontIdentityMatrix)
    fix = NO;
  else
    fix = YES;

  font = [placeHolder initWithName: aFontName matrix: fontMatrix fix: fix];

  return AUTORELEASE(font);
}

/**
 * Returns an autoreleased font with name aFontName and size fontSize.<br />
 * Fonts created using this method will automatically flip themselves
 * when set in a flipped view.
 */
+ (NSFont*) fontWithName: (NSString*)aFontName
		    size: (float)fontSize
{
  NSFont	*font;
  float		fontMatrix[6] = { 0, 0, 0, 0, 0, 0 };

  if (fontSize == 0)
    {
      fontSize = [defaults floatForKey: @"NSUserFontSize"];
      if (fontSize == 0)
	{
	  fontSize = 12;
	}
    }
  fontMatrix[0] = fontSize;
  fontMatrix[3] = fontSize;

  font = [placeHolder initWithName: aFontName matrix: fontMatrix fix: NO];
  return AUTORELEASE(font);
}

+ (void) useFont: (NSString*)aFontName
{
  [GSCurrentContext() useFont: aFontName];
}

//
// Instance methods
//
- (id) init
{
  [NSException raise: NSInternalInconsistencyException
	      format: @"Called -init on NSFont ... illegal"];
  return self;
}

/** <init />
 * Initializes a newly created font instance from the name and
 * information given in the fontMatrix. The fontMatrix is a standard
 * size element matrix as used in PostScript to describe the scaling
 * of the font, typically it just includes the font size as
 * [fontSize 0 0 fontSize 0 0].<br />
 * This method may destroy the receiver and return a cached instance.
 */
- (id) initWithName: (NSString*)name
	     matrix: (const float*)fontMatrix
		fix: (BOOL)explicitlySet
{
  NSString	*nameWithMatrix;
  NSFont	*font;

  /* Should never be called on an initialised font! */
  NSAssert(fontName == nil, NSInternalInconsistencyException);

  /* Check whether the font is cached */
  nameWithMatrix = newNameWithMatrix(name, fontMatrix, explicitlySet);
  font = (id)NSMapGet(globalFontMap, (void*)nameWithMatrix);
  if (font == nil)
    {
      if (self == placeHolder)
	{
	  /*
	   * If we are initialising the placeHolder, we actually want to
	   * leave it be (for later re-use) and initialise a newly created
	   * instance instead.
	   */
	  self = [NSFontClass alloc];
	}
      fontName = [name copy];
      memcpy(matrix, fontMatrix, sizeof(matrix));
      matrixExplicitlySet = explicitlySet;
      fontInfo = RETAIN([GSFontInfo fontInfoForFontName: fontName
						 matrix: fontMatrix]);
      /* Cache the font for later use */
      NSMapInsert(globalFontMap, (void*)nameWithMatrix, (void*)self);
    }
  else
    {
      RELEASE(self);
      self = RETAIN(font);
    }
  RELEASE(nameWithMatrix);

  return self;
}

- (void) dealloc
{
  if (fontName != nil)
    {
      NSString	*nameWithMatrix;

      nameWithMatrix = newNameWithMatrix(fontName, matrix, matrixExplicitlySet);
      NSMapRemove(globalFontMap, (void*)nameWithMatrix);
      RELEASE(nameWithMatrix);
      RELEASE(fontName);
    }
  TEST_RELEASE(fontInfo);
  [super dealloc];
}

- (NSString *) description
{
  NSString	*nameWithMatrix;
  NSString	*description;

  nameWithMatrix = newNameWithMatrix(fontName, matrix, matrixExplicitlySet);
  description = [[super description] stringByAppendingFormat: @" %@",
    nameWithMatrix];
  RELEASE(nameWithMatrix);
  return description;
}

- (BOOL) isEqual: (id)anObject
{
  int i;
  const float*obj_matrix;
  if (anObject == self)
    return YES;
  if ([anObject isKindOfClass: self->isa] == NO)
    return NO;
  if ([[anObject fontName] isEqual: fontName] == NO)
    return NO;
  obj_matrix = [anObject matrix];
  for (i = 0; i < 6; i++)
    if (obj_matrix[i] != matrix[i])
      return NO;
  return YES;
}

- (unsigned) hash
{
  int i, sum;
  sum = 0;
  for (i = 0; i < 6; i++)
    sum += matrix[i]* ((i+1)* 17);
  return ([fontName hash] + sum);
}

/**
 * The NSFont class caches instances ... to actually make copies
 * of instances would defeat the whole point of caching, so the
 * effect of copying an NSFont is imply to retain it.
 */
- (id) copyWithZone: (NSZone*)zone
{
  return RETAIN(self);
}

- (NSFont *)_flippedViewFont
{
  float fontMatrix[6];
  memcpy(fontMatrix, matrix, sizeof(matrix));
  fontMatrix[3] *= -1;
  return [NSFont fontWithName: fontName matrix: fontMatrix];
}

//
// Setting the Font
//
/** Sets the receiver as the font used for text drawing operations. If the
    current view is a flipped view, the reciever automatically flips itself
    to display correctly in the flipped view, as long as the font was created
    without explicitly setting the font matrix */
- (void) set
{
  NSGraphicsContext *ctxt = GSCurrentContext();

  if (matrixExplicitlySet == NO && [[NSView focusView] isFlipped])
    [ctxt GSSetFont: [self _flippedViewFont]];
  else
    [ctxt GSSetFont: self];

  [ctxt useFont: fontName];
}

//
// Querying the Font
//
- (float) pointSize		{ return [fontInfo pointSize]; }
- (NSString*) fontName		{ return fontName; }
- (const float*) matrix		{ return matrix; }

- (NSString*) encodingScheme	{ return [fontInfo encodingScheme]; }
- (NSString*) familyName	{ return [fontInfo familyName]; }
- (NSRect) boundingRectForFont	{ return [fontInfo boundingRectForFont]; }
- (BOOL) isFixedPitch		{ return [fontInfo isFixedPitch]; }
- (BOOL) isBaseFont		{ return [fontInfo isBaseFont]; }

/* Usually the display name of font is the font name.*/
- (NSString*) displayName	{ return fontName; }

- (NSDictionary*) afmDictionary	{ return [fontInfo afmDictionary]; }
- (NSString*) afmFileContents	{ return [fontInfo afmFileContents]; }
- (NSFont*) printerFont		{ return self; }
- (NSFont*) screenFont		{ return self; }
- (float) ascender		{ return [fontInfo ascender]; }
- (float) descender		{ return [fontInfo descender]; }
- (float) capHeight		{ return [fontInfo capHeight]; }
- (float) italicAngle		{ return [fontInfo italicAngle]; }
- (NSSize) maximumAdvancement	{ return [fontInfo maximumAdvancement]; }
- (NSSize) minimumAdvancement	{ return [fontInfo minimumAdvancement]; }
- (float) underlinePosition	{ return [fontInfo underlinePosition]; }
- (float) underlineThickness	{ return [fontInfo underlineThickness]; }
- (float) xHeight		{ return [fontInfo xHeight]; }
- (float) defaultLineHeightForFont { return [fontInfo defaultLineHeightForFont]; }

/* Computing font metrics attributes*/
- (float) widthOfString: (NSString*)string
{
  return [fontInfo widthOfString: string];
}

/* The following methods have to be implemented by backends */

//
// Manipulating Glyphs
//
- (NSSize) advancementForGlyph: (NSGlyph)aGlyph
{
  return [fontInfo advancementForGlyph: aGlyph];
}

- (NSRect) boundingRectForGlyph: (NSGlyph)aGlyph
{
  return [fontInfo boundingRectForGlyph: aGlyph];
}

- (BOOL) glyphIsEncoded: (NSGlyph)aGlyph
{
  return [fontInfo glyphIsEncoded: aGlyph];
}

- (NSMultibyteGlyphPacking) glyphPacking
{
  return [fontInfo glyphPacking];
}

- (NSGlyph) glyphWithName: (NSString*)glyphName
{
  return [fontInfo glyphWithName: glyphName];
}

- (NSPoint) positionOfGlyph: (NSGlyph)curGlyph
	    precededByGlyph: (NSGlyph)prevGlyph
		  isNominal: (BOOL*)nominal
{
  return [fontInfo positionOfGlyph: curGlyph precededByGlyph: prevGlyph
                         isNominal: nominal];
}

- (NSPoint) positionOfGlyph: (NSGlyph)aGlyph 
	       forCharacter: (unichar)aChar 
	     struckOverRect: (NSRect)aRect
{
  return [fontInfo positionOfGlyph: aGlyph 
		      forCharacter: aChar 
		    struckOverRect: aRect];
}

- (NSPoint) positionOfGlyph: (NSGlyph)aGlyph 
	    struckOverGlyph: (NSGlyph)baseGlyph 
	       metricsExist: (BOOL *)flag
{
  return [fontInfo positionOfGlyph: aGlyph 
		   struckOverGlyph: baseGlyph 
		      metricsExist: flag];
}

- (NSPoint) positionOfGlyph: (NSGlyph)aGlyph 
	     struckOverRect: (NSRect)aRect 
	       metricsExist: (BOOL *)flag
{
  return [fontInfo positionOfGlyph: aGlyph 
		    struckOverRect: aRect 
		      metricsExist: flag];
}

- (NSPoint) positionOfGlyph: (NSGlyph)aGlyph 
	       withRelation: (NSGlyphRelation)relation 
		toBaseGlyph: (NSGlyph)baseGlyph
	   totalAdvancement: (NSSize *)offset 
	       metricsExist: (BOOL *)flag
{
  return [fontInfo positionOfGlyph: aGlyph 
		      withRelation: relation 
		       toBaseGlyph: baseGlyph
		  totalAdvancement: offset 
		      metricsExist: flag];
}

- (int) positionsForCompositeSequence: (NSGlyph *)glyphs 
		       numberOfGlyphs: (int)numGlyphs 
			   pointArray: (NSPoint *)points
{
  int i;
  NSGlyph base = glyphs[0];

  points[0] = NSZeroPoint;

  for (i = 1; i < numGlyphs; i++)
    {
      BOOL flag;
      // This only places the glyphs relative to the base glyph 
      // not to each other
      points[i] = [self positionOfGlyph: glyphs[i] 
			struckOverGlyph: base 
			   metricsExist: &flag];
      if (!flag)
	return i - 1;
    }

  return i;
}

- (NSStringEncoding) mostCompatibleStringEncoding
{
  return [fontInfo mostCompatibleStringEncoding];
}

//
// NSCoding protocol
//
- (Class) classForCoder
{
  return NSFontClass;
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  [aCoder encodeObject: fontName];
  [aCoder encodeArrayOfObjCType: @encode(float)  count: 6  at: matrix];
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &matrixExplicitlySet];
}

- (id) initWithCoder: (NSCoder*)aDecoder
{
  int version = [aDecoder versionForClassName: @"NSFont"];
  id	name;
  float	fontMatrix[6];
  BOOL	fix;

  name = [aDecoder decodeObject];
  [aDecoder decodeArrayOfObjCType: @encode(float)
			    count: 6
			       at: fontMatrix];
  if (version == currentVersion)
    {
      [aDecoder decodeValueOfObjCType: @encode(BOOL)
				   at: &fix];
    }
  else
    {
      if (fontMatrix[0] == fontMatrix[3]
        && fontMatrix[1] == 0.0 && fontMatrix[2] == 0.0)
	fix = NO;
      else
	fix = YES;
    }

  self = [self initWithName: name  matrix: fontMatrix fix: fix];
  return self;
}

@end /* NSFont */

@implementation NSFont (GNUstep)
//
// Private method for NSFontManager and backend
//
- (GSFontInfo*) fontInfo
{
  return fontInfo;
}

@end


int NSConvertGlyphsToPackedGlyphs(NSGlyph *glBuf, 
				  int count, 
				  NSMultibyteGlyphPacking packing, 
				  char *packedGlyphs)
{
// TODO
  return 0;
}
