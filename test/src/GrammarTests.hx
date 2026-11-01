// Ported from vscode-textmate 9.2.0: src/tests/grammar.test.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import textmate.EncodedTokenAttributes;
import textmate.Theme.FontStyle;

class GrammarTests {
    static function assertEquals(metadata:Int, languageId:Int, tokenType:StandardTokenType, containsBalancedBrackets:Bool, fontStyle:Int, foreground:Int,
            background:Int):Void {
        var actual = [
            EncodedTokenAttributes.getLanguageId(metadata),
            EncodedTokenAttributes.getTokenType(metadata),
            EncodedTokenAttributes.containsBalancedBrackets(metadata) ? 1 : 0,
            EncodedTokenAttributes.getFontStyle(metadata),
            EncodedTokenAttributes.getForeground(metadata),
            EncodedTokenAttributes.getBackground(metadata)
        ];
        var expected = [languageId, (tokenType : Int), containsBalancedBrackets ? 1 : 0, fontStyle, foreground, background];
        T.same(actual, expected, 'equals for ' + EncodedTokenAttributes.toBinaryStr(metadata));
    }

    public static function run():Void {
        T.suite('grammar');

        T.test('StackElementMetadata works', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);
        });

        T.test('StackElementMetadata can overwrite languageId', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 2, OptionalStandardTokenType.NotSet, 0, FontStyle.NotSet, 0, 0);
            assertEquals(value, 2, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);
        });

        T.test('StackElementMetadata can overwrite tokenType', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.Comment, 0, FontStyle.NotSet, 0, 0);
            assertEquals(value, 1, StandardTokenType.Comment, false, FontStyle.Underline | FontStyle.Bold, 101, 102);
        });

        T.test('StackElementMetadata can overwrite font style', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.NotSet, 0, FontStyle.None, 0, 0);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.None, 101, 102);
        });

        T.test('StackElementMetadata can overwrite font style with strikethrough', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Strikethrough, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Strikethrough, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.NotSet, 0, FontStyle.None, 0, 0);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.None, 101, 102);
        });

        T.test('StackElementMetadata can overwrite foreground', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.NotSet, 0, FontStyle.NotSet, 5, 0);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 5, 102);
        });

        T.test('StackElementMetadata can overwrite background', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.NotSet, 0, FontStyle.NotSet, 0, 7);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 7);
        });

        T.test('StackElementMetadata can overwrite balanced backet bit', () -> {
            var value = EncodedTokenAttributes.set(0, 1, OptionalStandardTokenType.RegEx, 0, FontStyle.Underline | FontStyle.Bold, 101, 102);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.NotSet, 1, FontStyle.NotSet, 0, 0);
            assertEquals(value, 1, StandardTokenType.RegEx, true, FontStyle.Underline | FontStyle.Bold, 101, 102);

            value = EncodedTokenAttributes.set(value, 0, OptionalStandardTokenType.NotSet, 0, FontStyle.NotSet, 0, 0);
            assertEquals(value, 1, StandardTokenType.RegEx, false, FontStyle.Underline | FontStyle.Bold, 101, 102);
        });

        T.test('StackElementMetadata can work at max values', () -> {
            var maxLangId = 255;
            var maxTokenType:StandardTokenType = StandardTokenType.Comment | StandardTokenType.Other | StandardTokenType.RegEx | StandardTokenType.String;
            var maxFontStyle = FontStyle.Bold | FontStyle.Italic | FontStyle.Underline;
            var maxForeground = 511;
            var maxBackground = 254;

            var value = EncodedTokenAttributes.set(0, maxLangId, (maxTokenType : Int), 1, maxFontStyle, maxForeground, maxBackground);
            assertEquals(value, maxLangId, maxTokenType, true, maxFontStyle, maxForeground, maxBackground);
        });
    }
}
