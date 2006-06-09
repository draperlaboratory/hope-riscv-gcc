/* GdkFontPeer.java -- Implements FontPeer with GTK+
   Copyright (C) 1999, 2004, 2005, 2006  Free Software Foundation, Inc.

This file is part of GNU Classpath.

GNU Classpath is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

GNU Classpath is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Classpath; see the file COPYING.  If not, write to the
Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA.

Linking this library statically or dynamically with other modules is
making a combined work based on this library.  Thus, the terms and
conditions of the GNU General Public License cover the whole
combination.

As a special exception, the copyright holders of this library give you
permission to link this library with independent modules to produce an
executable, regardless of the license terms of these independent
modules, and to copy and distribute the resulting executable under
terms of your choice, provided that you also meet, for each linked
independent module, the terms and conditions of the license of that
module.  An independent module is a module which is not derived from
or based on this library.  If you modify this library, you may extend
this exception to your version of the library, but you are not
obligated to do so.  If you do not wish to do so, delete this
exception statement from your version. */


package gnu.java.awt.peer.gtk;

import gnu.classpath.Configuration;
import gnu.java.awt.peer.ClasspathFontPeer;
import gnu.java.awt.font.opentype.NameDecoder;

import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.Toolkit;
import java.awt.font.FontRenderContext;
import java.awt.font.GlyphVector;
import java.awt.font.GlyphMetrics;
import java.awt.font.LineMetrics;
import java.awt.geom.Rectangle2D;
import java.awt.geom.Point2D;
import java.text.CharacterIterator;
import java.text.StringCharacterIterator;
import java.util.Locale;
import java.util.Map;
import java.util.ResourceBundle;
import java.nio.ByteBuffer;

public class GdkFontPeer extends ClasspathFontPeer
{
  static native void initStaticState();
  private final int native_state = GtkGenericPeer.getUniqueInteger ();
  private static ResourceBundle bundle;
  
  static 
  {
    System.loadLibrary("gtkpeer");

    initStaticState ();

    try
      {
	bundle = ResourceBundle.getBundle ("gnu.java.awt.peer.gtk.font");
      }
    catch (Throwable ignored)
      {
	bundle = null;
      }
  }

  private ByteBuffer nameTable = null;

  private native void initState ();
  private native void dispose ();
  private native void setFont (String family, int style, int size);

  native void getFontMetrics(double [] metrics);
  native void getTextMetrics(String str, double [] metrics);

  native void releasePeerGraphicsResource();


  protected void finalize ()
  {
    releasePeerGraphicsResource();
    dispose ();
  }

  /* 
   * Helpers for the 3-way overloading that this class seems to suffer
   * from. Remove them if you feel like they're a performance bottleneck,
   * for the time being I prefer my code not be written and debugged in
   * triplicate.
   */

  private String buildString(CharacterIterator iter)
  {
    StringBuffer sb = new StringBuffer();
    for(char c = iter.first(); c != CharacterIterator.DONE; c = iter.next()) 
      sb.append(c);
    return sb.toString();
  }

  private String buildString(CharacterIterator iter, int begin, int limit)
  {
    StringBuffer sb = new StringBuffer();
    int i = 0;
    for(char c = iter.first(); c != CharacterIterator.DONE; c = iter.next(), i++) 
      {
        if (begin <= i)
          sb.append(c);
        if (limit <= i)
          break;
      }
    return sb.toString();
  }
  
  private String buildString(char[] chars, int begin, int limit)
  {
    return new String(chars, begin, limit - begin);
  }

  /* Public API */

  public GdkFontPeer (String name, int style)
  {
    // All fonts get a default size of 12 if size is not specified.
    this(name, style, 12);
  }

  public GdkFontPeer (String name, int style, int size)
  {  
    super(name, style, size);    
    initState ();
    setFont (this.familyName, this.style, (int)this.size);
  }

  public GdkFontPeer (String name, Map attributes)
  {
    super(name, attributes);
    initState ();
    setFont (this.familyName, this.style, (int)this.size);
  }

  /**
   * Unneeded, but implemented anyway.
   */  
  public String getSubFamilyName(Font font, Locale locale)
  {
    String name;
    
    if (locale == null)
      locale = Locale.getDefault();
    
    name = getName(NameDecoder.NAME_SUBFAMILY, locale);
    if (name == null)
      {
	name = getName(NameDecoder.NAME_SUBFAMILY, Locale.ENGLISH);
	if ("Regular".equals(name))
	  name = null;
      }

    return name;
  }

  /**
   * Returns the bytes belonging to a TrueType/OpenType table,
   * Parameters n,a,m,e identify the 4-byte ASCII tag of the table.
   *
   * Returns null if the font is not TT, the table is nonexistant, 
   * or if some other unexpected error occured.
   *
   */
  private native byte[] getTrueTypeTable(byte n, byte a, byte m, byte e);

  /**
   * Returns the PostScript name of the font, defaults to the familyName if 
   * a PS name could not be retrieved.
   */
  public String getPostScriptName(Font font)
  {
    String name = getName(NameDecoder.NAME_POSTSCRIPT, 
			  /* any language */ null);
    if( name == null )
      return this.familyName;

    return name;
  }

  /**
   * Extracts a String from the font&#x2019;s name table.
   *
   * @param name the numeric TrueType or OpenType name ID.
   *
   * @param locale the locale for which names shall be localized, or
   * <code>null</code> if the locale does mot matter because the name
   * is known to be language-independent (for example, because it is
   * the PostScript name).
   */
  private String getName(int name, Locale locale)
  {
    if (nameTable == null)
      {
	byte[] data = getTrueTypeTable((byte)'n', (byte) 'a', 
				       (byte) 'm', (byte) 'e');
	if( data == null )
	  return null;

	nameTable = ByteBuffer.wrap( data );
      }

    return NameDecoder.getName(nameTable, name, locale);
  }

  public boolean canDisplay (Font font, char c)
  {
    // FIXME: inquire with pango
    return true;
  }

  public int canDisplayUpTo (Font font, CharacterIterator i, int start, int limit)
  {
    // FIXME: inquire with pango
    return -1;
  }
  
  public GlyphVector createGlyphVector (Font font, 
                                        FontRenderContext ctx, 
                                        CharacterIterator i)
  {
    return new FreetypeGlyphVector(font, buildString (i), ctx);
  }

  public GlyphVector createGlyphVector (Font font, 
                                        FontRenderContext ctx, 
                                        int[] glyphCodes)
  {
    return new FreetypeGlyphVector(font, glyphCodes, ctx);
  }

  public byte getBaselineFor (Font font, char c)
  {
    throw new UnsupportedOperationException ();
  }

  protected class GdkFontLineMetrics extends LineMetrics
  {
    FontMetrics fm;
    int nchars; 

    public GdkFontLineMetrics (FontMetrics m, int n)
    {
      fm = m;
      nchars = n;
    }

    public float getAscent()
    {
      return (float) fm.getAscent ();
    }
  
    public int getBaselineIndex()
    {
      return Font.ROMAN_BASELINE;
    }
    
    public float[] getBaselineOffsets()
    {
      return new float[3];
    }
    
    public float getDescent()
    {
      return (float) fm.getDescent ();
    }
    
    public float getHeight()
    {
      return (float) fm.getHeight ();
    }
    
    public float getLeading() { return 0.f; }    
    public int getNumChars() { return nchars; }
    public float getStrikethroughOffset() { return 0.f; }    
    public float getStrikethroughThickness() { return 0.f; }  
    public float getUnderlineOffset() { return 0.f; }
    public float getUnderlineThickness() { return 0.f; }

  }

  public LineMetrics getLineMetrics (Font font, CharacterIterator ci, 
                                     int begin, int limit, FontRenderContext rc)
  {
    return new GdkFontLineMetrics (getFontMetrics (font), limit - begin);
  }

  public Rectangle2D getMaxCharBounds (Font font, FontRenderContext rc)
  {
    throw new UnsupportedOperationException ();
  }

  public int getMissingGlyphCode (Font font)
  {
    throw new UnsupportedOperationException ();
  }

  public String getGlyphName (Font font, int glyphIndex)
  {
    throw new UnsupportedOperationException ();
  }

  public int getNumGlyphs (Font font)
  {
    byte[] data = getTrueTypeTable((byte)'m', (byte) 'a', 
				   (byte)'x', (byte) 'p');
    if( data == null )
      return -1;

    ByteBuffer buf = ByteBuffer.wrap( data );       
    return buf.getShort(4);
  }

  public Rectangle2D getStringBounds (Font font, CharacterIterator ci, 
                                      int begin, int limit, FontRenderContext frc)
  {
    GlyphVector gv = new FreetypeGlyphVector( font, 
					      buildString(ci, begin, limit),
					      frc);
    return gv.getVisualBounds();
  }

  public boolean hasUniformLineMetrics (Font font)
  {
    return true;
  }

  public GlyphVector layoutGlyphVector (Font font, FontRenderContext frc, 
                                        char[] chars, int start, int limit, 
                                        int flags)
  {
    int nchars = (limit - start) + 1;
    char[] nc = new char[nchars];

    for (int i = 0; i < nchars; ++i)
      nc[i] = chars[start + i];

    return createGlyphVector (font, frc, 
                              new StringCharacterIterator (new String (nc)));
  }

  public LineMetrics getLineMetrics (Font font, String str, 
                                     FontRenderContext frc)
  {
    return new GdkFontLineMetrics (getFontMetrics (font), str.length ());
  }

  public FontMetrics getFontMetrics (Font font)
  {
    // Get the font metrics through GtkToolkit to take advantage of
    // the metrics cache.
    return Toolkit.getDefaultToolkit().getFontMetrics (font);
  }
}
