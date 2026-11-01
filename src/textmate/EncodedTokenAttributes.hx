// Ported from vscode-textmate 9.2.0: src/encodedTokenAttributes.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.Theme.FontStyle;

/**
 * Helpers to manage the "collapsed" metadata of an entire StackElement stack.
 * The following assumptions have been made:
 *  - languageId < 256 => needs 8 bits
 *  - unique color count < 512 => needs 9 bits
 *
 * The binary format is:
 * - -------------------------------------------
 *     3322 2222 2222 1111 1111 1100 0000 0000
 *     1098 7654 3210 9876 5432 1098 7654 3210
 * - -------------------------------------------
 *     xxxx xxxx xxxx xxxx xxxx xxxx xxxx xxxx
 *     bbbb bbbb ffff ffff fFFF FBTT LLLL LLLL
 * - -------------------------------------------
 *  - L = LanguageId (8 bits)
 *  - T = StandardTokenType (2 bits)
 *  - B = Balanced bracket (1 bit)
 *  - F = FontStyle (4 bits)
 *  - f = foreground color (9 bits)
 *  - b = background color (9 bits)
 *
 * The values are 32 bit integers: on Haxe targets with signed integers, a
 * value with the highest background bit set is negative (vscode-textmate gives
 * the same bits as an unsigned number).
 */
class EncodedTokenAttributes {
    public static inline var LANGUAGEID_MASK = 0x000000FF;
    public static inline var TOKEN_TYPE_MASK = 0x00000300;
    public static inline var BALANCED_BRACKETS_MASK = 0x00000400;
    public static inline var FONT_STYLE_MASK = 0x00007800;
    public static inline var FOREGROUND_MASK = 0x00FF8000;
    public static inline var BACKGROUND_MASK = 0xFF000000;

    public static inline var LANGUAGEID_OFFSET = 0;
    public static inline var TOKEN_TYPE_OFFSET = 8;
    public static inline var BALANCED_BRACKETS_OFFSET = 10;
    public static inline var FONT_STYLE_OFFSET = 11;
    public static inline var FOREGROUND_OFFSET = 15;
    public static inline var BACKGROUND_OFFSET = 24;

    public static function toBinaryStr(encodedTokenAttributes:Int):String {
        var r = '';
        for (i in 0...32) {
            r = ((encodedTokenAttributes >>> i) & 1 == 1 ? '1' : '0') + r;
        }
        return r;
    }

    public static inline function getLanguageId(encodedTokenAttributes:Int):Int {
        return (encodedTokenAttributes & LANGUAGEID_MASK) >>> LANGUAGEID_OFFSET;
    }

    public static inline function getTokenType(encodedTokenAttributes:Int):StandardTokenType {
        return (encodedTokenAttributes & TOKEN_TYPE_MASK) >>> TOKEN_TYPE_OFFSET;
    }

    public static inline function containsBalancedBrackets(encodedTokenAttributes:Int):Bool {
        return (encodedTokenAttributes & BALANCED_BRACKETS_MASK) != 0;
    }

    public static inline function getFontStyle(encodedTokenAttributes:Int):Int {
        return (encodedTokenAttributes & FONT_STYLE_MASK) >>> FONT_STYLE_OFFSET;
    }

    public static inline function getForeground(encodedTokenAttributes:Int):Int {
        return (encodedTokenAttributes & FOREGROUND_MASK) >>> FOREGROUND_OFFSET;
    }

    public static inline function getBackground(encodedTokenAttributes:Int):Int {
        return (encodedTokenAttributes & BACKGROUND_MASK) >>> BACKGROUND_OFFSET;
    }

    /**
     * Updates the fields in `metadata`.
     * A value of `0`, `NotSet` or `null` indicates that the corresponding field should be left as is.
     * `containsBalancedBrackets` is -1 (null), 0 (false) or 1 (true).
     */
    public static function set(encodedTokenAttributes:Int, languageId:Int, tokenType:OptionalStandardTokenType, containsBalancedBrackets:Int, fontStyle:Int,
            foreground:Int, background:Int):Int {
        var _languageId = getLanguageId(encodedTokenAttributes);
        var _tokenType:Int = getTokenType(encodedTokenAttributes);
        var _containsBalancedBracketsBit = EncodedTokenAttributes.containsBalancedBrackets(encodedTokenAttributes) ? 1 : 0;
        var _fontStyle = getFontStyle(encodedTokenAttributes);
        var _foreground = getForeground(encodedTokenAttributes);
        var _background = getBackground(encodedTokenAttributes);

        if (languageId != 0) {
            _languageId = languageId;
        }
        if (tokenType != OptionalStandardTokenType.NotSet) {
            _tokenType = fromOptionalTokenType(tokenType);
        }
        if (containsBalancedBrackets != -1) {
            _containsBalancedBracketsBit = containsBalancedBrackets != 0 ? 1 : 0;
        }
        if (fontStyle != FontStyle.NotSet) {
            _fontStyle = fontStyle;
        }
        if (foreground != 0) {
            _foreground = foreground;
        }
        if (background != 0) {
            _background = background;
        }

        return ((_languageId << LANGUAGEID_OFFSET)
            | (_tokenType << TOKEN_TYPE_OFFSET)
            | (_containsBalancedBracketsBit << BALANCED_BRACKETS_OFFSET)
            | (_fontStyle << FONT_STYLE_OFFSET)
            | (_foreground << FOREGROUND_OFFSET)
            | (_background << BACKGROUND_OFFSET));
    }

    public static inline function toOptionalTokenType(standardType:StandardTokenType):OptionalStandardTokenType {
        return (standardType : Int);
    }

    static inline function fromOptionalTokenType(standardType:OptionalStandardTokenType):StandardTokenType {
        return (standardType : Int);
    }
}

enum abstract StandardTokenType(Int) from Int to Int {
    var Other = 0;
    var Comment = 1;
    var String = 2;
    var RegEx = 3;
}

// Must have the same values as `StandardTokenType`!
enum abstract OptionalStandardTokenType(Int) from Int to Int {
    var Other = 0;
    var Comment = 1;
    var String = 2;
    var RegEx = 3;
    // Indicates that no token type is set.
    var NotSet = 8;
}
