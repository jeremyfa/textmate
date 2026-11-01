// Ported from vscode-textmate 9.2.0: src/tests/themes.test.ts (the tests that do not read files)
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import textmate.Theme;
import textmate.Utils;

class ThemeUnitTests {
    static function rawTheme(settings:Array<Dynamic>):IRawTheme {
        return IRawTheme.fromDynamic({settings: settings});
    }

    static function from(path:Array<String>):ScopeStack {
        return ScopeStack.from(path);
    }

    static function ruleToPlain(r:ParsedThemeRule):Dynamic {
        return {
            scope: r.scope,
            parentScopes: r.parentScopes,
            index: r.index,
            fontStyle: r.fontStyle,
            foreground: r.foreground,
            background: r.background
        };
    }

    static function assertRules(actual:Array<ParsedThemeRule>, expected:Array<ParsedThemeRule>):Void {
        T.same([for (r in actual) ruleToPlain(r)], [for (r in expected) ruleToPlain(r)]);
    }

    static function assertThemeEqual(actual:Theme, expected:Theme):Void {
        // Don't compare cache objects. Like upstream, only the color maps are
        // compared to the expectation (upstream compares the actual defaults
        // and root with themselves).
        T.same(actual._getColorMapObject().getColorMap(), expected._getColorMapObject().getColorMap());
    }

    public static function run():Void {
        T.suite('theme');

        T.test('Theme matching gives higher priority to deeper matches', () -> {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#100000', background: '#200000'}},
                {scope: 'punctuation.definition.string.begin.html', settings: {foreground: '#300000'}},
                {scope: 'meta.tag punctuation.definition.string', settings: {foreground: '#400000'}},
            ]));
            var actual = theme.match(from(['punctuation.definition.string.begin.html']));
            T.equals(theme.getColorMap()[actual.foregroundId], '#300000');
        });

        T.test('Theme matching gives higher priority to parent matches 1', () -> {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#100000', background: '#200000'}},
                {scope: 'c a', settings: {foreground: '#300000'}},
                {scope: 'd a.b', settings: {foreground: '#400000'}},
                {scope: 'a', settings: {foreground: '#500000'}},
            ]));
            var map = theme.getColorMap();
            T.equals(map[theme.match(from(['d', 'a.b'])).foregroundId], '#400000');
        });

        T.test('Theme matching gives higher priority to parent matches 2', () -> {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#100000', background: '#200000'}},
                {scope: 'meta.tag entity', settings: {foreground: '#300000'}},
                {scope: 'meta.selector.css entity.name.tag', settings: {foreground: '#400000'}},
                {scope: 'entity', settings: {foreground: '#500000'}},
            ]));
            var result = theme.match(from(["text.html.cshtml", "meta.tag.structure.any.html", "entity.name.tag.structure.any.html"]));
            var colorMap = theme.getColorMap();
            T.equals(colorMap[result.foregroundId], '#300000');
        });

        {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#F8F8F2', background: '#272822'}},
                {scope: 'source, something', settings: {background: '#100000'}},
                {scope: ['bar', 'baz'], settings: {background: '#200000'}},
                {scope: 'source.css selector bar', settings: {fontStyle: 'bold'}},
                {scope: 'constant', settings: {fontStyle: 'italic', foreground: '#300000'}},
                {scope: 'constant.numeric', settings: {foreground: '#400000'}},
                {scope: 'constant.numeric.hex', settings: {fontStyle: 'bold'}},
                {scope: 'constant.numeric.oct', settings: {fontStyle: 'bold italic underline'}},
                {scope: 'constant.numeric.dec', settings: {fontStyle: '', foreground: '#500000'}},
                {scope: 'storage.object.bar', settings: {fontStyle: '', foreground: '#600000'}},
            ]));

            var map = theme.getColorMap();

            function match(path:Array<String>):Dynamic {
                var result = theme.match(from(path));
                if (result == null) {
                    return null;
                }
                var obj:Dynamic = {fontStyle: Theme.fontStyleToString(result.fontStyle)};
                if (result.foregroundId != 0) {
                    obj.foreground = map[result.foregroundId];
                }
                if (result.backgroundId != 0) {
                    obj.background = map[result.backgroundId];
                }
                return obj;
            }

            var cases:Array<{name:String, path:Array<String>, expected:Dynamic}> = [
                {name: 'simpleMatch1', path: ['source'], expected: {background: "#100000", fontStyle: "not set"}},
                {name: 'simpleMatch2', path: ['source.ts'], expected: {background: "#100000", fontStyle: "not set"}},
                {name: 'simpleMatch3', path: ['source.tss'], expected: {background: "#100000", fontStyle: "not set"}},
                {name: 'simpleMatch4', path: ['something'], expected: {background: "#100000", fontStyle: "not set"}},
                {name: 'simpleMatch5', path: ['something.ts'], expected: {background: "#100000", fontStyle: "not set"}},
                {name: 'simpleMatch6', path: ['something.tss'], expected: {background: "#100000", fontStyle: "not set"}},
                {name: 'simpleMatch7', path: ['baz'], expected: {background: "#200000", fontStyle: "not set"}},
                {name: 'simpleMatch8', path: ['baz.ts'], expected: {background: "#200000", fontStyle: "not set"}},
                {name: 'simpleMatch9', path: ['baz.tss'], expected: {background: "#200000", fontStyle: "not set"}},
                {name: 'simpleMatch10', path: ['constant'], expected: {foreground: "#300000", fontStyle: "italic"}},
                {name: 'simpleMatch11', path: ['constant.string'], expected: {foreground: "#300000", fontStyle: "italic"}},
                {name: 'simpleMatch12', path: ['constant.hex'], expected: {foreground: "#300000", fontStyle: "italic"}},
                {name: 'simpleMatch13', path: ['constant.numeric'], expected: {foreground: "#400000", fontStyle: "italic"}},
                {name: 'simpleMatch14', path: ['constant.numeric.baz'], expected: {foreground: "#400000", fontStyle: "italic"}},
                {name: 'simpleMatch15', path: ['constant.numeric.hex'], expected: {foreground: "#400000", fontStyle: "bold"}},
                {name: 'simpleMatch16', path: ['constant.numeric.hex.baz'], expected: {foreground: "#400000", fontStyle: "bold"}},
                {name: 'simpleMatch17', path: ['constant.numeric.oct'], expected: {foreground: "#400000", fontStyle: "italic bold underline"}},
                {name: 'simpleMatch18', path: ['constant.numeric.oct.baz'], expected: {foreground: "#400000", fontStyle: "italic bold underline"}},
                {name: 'simpleMatch19', path: ['constant.numeric.dec'], expected: {foreground: "#500000", fontStyle: "none"}},
                {name: 'simpleMatch20', path: ['constant.numeric.dec.baz'], expected: {foreground: "#500000", fontStyle: "none"}},
                {name: 'simpleMatch21', path: ['storage.object.bar'], expected: {foreground: "#600000", fontStyle: "none"}},
                {name: 'simpleMatch22', path: ['storage.object.bar.baz'], expected: {foreground: "#600000", fontStyle: "none"}},
                {name: 'simpleMatch23', path: ['storage.object.bart'], expected: {fontStyle: "not set"}},
                {name: 'simpleMatch24', path: ['storage.object'], expected: {fontStyle: "not set"}},
                {name: 'simpleMatch25', path: ['storage'], expected: {fontStyle: "not set"}},
                {name: 'defaultMatch1', path: [''], expected: {fontStyle: "not set"}},
                {name: 'defaultMatch2', path: ['bazz'], expected: {fontStyle: "not set"}},
                {name: 'defaultMatch3', path: ['asdfg'], expected: {fontStyle: "not set"}},
                {name: 'multiMatch1', path: ['bar'], expected: {background: "#200000", fontStyle: "not set"}},
                {name: 'multiMatch2', path: ['source.css', 'selector', 'bar'], expected: {background: "#200000", fontStyle: "bold"}},
            ];
            for (c in cases) {
                T.test('Theme matching can match ' + c.name, () -> T.same(match(c.path), c.expected));
            }
        }

        T.test('Theme matching Microsoft/vscode#23460', () -> {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#aec2e0', background: '#14191f'}},
                {name: 'JSON String', scope: 'meta.structure.dictionary.json string.quoted.double.json', settings: {foreground: '#FF410D'}},
                {scope: 'meta.structure.dictionary.json string.quoted.double.json', settings: {foreground: '#ffffff'}},
                {scope: 'meta.structure.dictionary.value.json string.quoted.double.json', settings: {foreground: '#FF410D'}}
            ]));
            var path = from(["source.json", "meta.structure.dictionary.json", "meta.structure.dictionary.value.json", "string.quoted.double.json"]);
            var result = theme.match(path);
            T.equals(theme.getColorMap()[result.foregroundId], '#FF410D');
        });

        T.test('Theme parsing can parse', () -> {
            var actual = Theme.parseTheme(rawTheme([
                {settings: {foreground: '#F8F8F2', background: '#272822'}},
                {scope: 'source, something', settings: {background: '#100000'}},
                {scope: ['bar', 'baz'], settings: {background: '#010000'}},
                {scope: 'source.css selector bar', settings: {fontStyle: 'bold'}},
                {scope: 'constant', settings: {fontStyle: 'italic', foreground: '#ff0000'}},
                {scope: 'constant.numeric', settings: {foreground: '#00ff00'}},
                {scope: 'constant.numeric.hex', settings: {fontStyle: 'bold'}},
                {scope: 'constant.numeric.oct', settings: {fontStyle: 'bold italic underline'}},
                {scope: 'constant.numeric.bin', settings: {fontStyle: 'bold strikethrough'}},
                {scope: 'constant.numeric.dec', settings: {fontStyle: '', foreground: '#0000ff'}},
                {scope: 'foo', settings: {fontStyle: '', foreground: '#CFA'}},
            ]));

            var expected = [
                new ParsedThemeRule('', null, 0, FontStyle.NotSet, '#F8F8F2', '#272822'),
                new ParsedThemeRule('source', null, 1, FontStyle.NotSet, null, '#100000'),
                new ParsedThemeRule('something', null, 1, FontStyle.NotSet, null, '#100000'),
                new ParsedThemeRule('bar', null, 2, FontStyle.NotSet, null, '#010000'),
                new ParsedThemeRule('baz', null, 2, FontStyle.NotSet, null, '#010000'),
                new ParsedThemeRule('bar', ['selector', 'source.css'], 3, FontStyle.Bold, null, null),
                new ParsedThemeRule('constant', null, 4, FontStyle.Italic, '#ff0000', null),
                new ParsedThemeRule('constant.numeric', null, 5, FontStyle.NotSet, '#00ff00', null),
                new ParsedThemeRule('constant.numeric.hex', null, 6, FontStyle.Bold, null, null),
                new ParsedThemeRule('constant.numeric.oct', null, 7, FontStyle.Bold | FontStyle.Italic | FontStyle.Underline, null, null),
                new ParsedThemeRule('constant.numeric.bin', null, 8, FontStyle.Bold | FontStyle.Strikethrough, null, null),
                new ParsedThemeRule('constant.numeric.dec', null, 9, FontStyle.None, '#0000ff', null),
                new ParsedThemeRule('foo', null, 10, FontStyle.None, '#CFA', null),
            ];

            assertRules(actual, expected);
        });

        T.test('Theme resolving strcmp works', () -> {
            var actual = ['bar', 'z', 'zu', 'a', 'ab', ''];
            haxe.ds.ArraySort.sort(actual, Utils.strcmp);
            T.same(actual, ['', 'a', 'ab', 'bar', 'z', 'zu']);
        });

        T.test('Theme resolving strArrCmp works', () -> {
            function assertStrArrCmp(testCase:String, a:Null<Array<String>>, b:Null<Array<String>>, expected:Int):Void {
                T.equals(Utils.strArrCmp(a, b), expected, testCase);
            }
            assertStrArrCmp('001', null, null, 0);
            assertStrArrCmp('002', null, [], -1);
            assertStrArrCmp('003', null, ['a'], -1);
            assertStrArrCmp('004', [], null, 1);
            assertStrArrCmp('005', ['a'], null, 1);
            assertStrArrCmp('006', [], [], 0);
            assertStrArrCmp('007', [], ['a'], -1);
            assertStrArrCmp('008', ['a'], [], 1);
            assertStrArrCmp('009', ['a'], ['a'], 0);
            assertStrArrCmp('010', ['a', 'b'], ['a'], 1);
            assertStrArrCmp('011', ['a'], ['a', 'b'], -1);
            assertStrArrCmp('012', ['a', 'b'], ['a', 'b'], 0);
            assertStrArrCmp('013', ['a', 'b'], ['a', 'c'], -1);
            assertStrArrCmp('014', ['a', 'c'], ['a', 'b'], 1);
        });

        function el(rule:ThemeTrieElementRule, ?rules:Array<ThemeTrieElementRule>, ?children:Array<{k:String, v:ThemeTrieElement}>):ThemeTrieElement {
            var map = new textmate.OrderedMap<ThemeTrieElement>();
            if (children != null) {
                for (c in children) {
                    map.set(c.k, c.v);
                }
            }
            return new ThemeTrieElement(rule, rules, map);
        }

        T.test('Theme resolving always has defaults', () -> {
            var actual = Theme.createFromParsedTheme([]);
            var colorMap = new ColorMap();
            var _NOT_SET = 0;
            var _A = colorMap.getId('#000000');
            var _B = colorMap.getId('#ffffff');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.None, _A, _B), el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, _NOT_SET, _NOT_SET)));
            assertThemeEqual(actual, expected);
        });

        for (k in 0...5) {
            var incoming = [
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, null, null),
                new ParsedThemeRule('', null, -1, FontStyle.None, null, null),
                new ParsedThemeRule('', null, -1, FontStyle.Bold, null, null),
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#ff0000', null),
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, null, '#ff0000')
            ][k];
            T.test('Theme resolving respects incoming defaults ' + (k + 1), () -> {
                var actual = Theme.createFromParsedTheme([incoming]);
                var colorMap = new ColorMap();
                var _NOT_SET = 0;
                var _A = colorMap.getId(k == 3 ? '#ff0000' : '#000000');
                var _B = colorMap.getId(k == 4 ? '#ff0000' : '#ffffff');
                var expected = new Theme(colorMap, new StyleAttributes(k == 2 ? FontStyle.Bold : FontStyle.None, _A, _B),
                    el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, _NOT_SET, _NOT_SET)));
                assertThemeEqual(actual, expected);
                T.equals(actual.getDefaults().fontStyle, k == 2 ? FontStyle.Bold : FontStyle.None);
            });
        }

        T.test('Theme resolving can merge incoming defaults', () -> {
            var actual = Theme.createFromParsedTheme([
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, null, '#ff0000'),
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#00ff00', null),
                new ParsedThemeRule('', null, -1, FontStyle.Bold, null, null),
            ]);
            var colorMap = new ColorMap();
            var _NOT_SET = 0;
            var _A = colorMap.getId('#00ff00');
            var _B = colorMap.getId('#ff0000');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.Bold, _A, _B), el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, _NOT_SET, _NOT_SET)));
            assertThemeEqual(actual, expected);
        });

        T.test('Theme resolving defaults are inherited', () -> {
            var actual = Theme.createFromParsedTheme([
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#F8F8F2', '#272822'),
                new ParsedThemeRule('var', null, -1, FontStyle.NotSet, '#ff0000', null)
            ]);
            var colorMap = new ColorMap();
            var _NOT_SET = 0;
            var _A = colorMap.getId('#F8F8F2');
            var _B = colorMap.getId('#272822');
            var _C = colorMap.getId('#ff0000');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.None, _A, _B),
                el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, _NOT_SET, _NOT_SET), [],
                    [{k: 'var', v: el(new ThemeTrieElementRule(1, null, FontStyle.NotSet, _C, _NOT_SET))}]));
            assertThemeEqual(actual, expected);
        });

        T.test('Theme resolving same rules get merged', () -> {
            var actual = Theme.createFromParsedTheme([
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#F8F8F2', '#272822'),
                new ParsedThemeRule('var', null, 1, FontStyle.Bold, null, null),
                new ParsedThemeRule('var', null, 0, FontStyle.NotSet, '#ff0000', null),
            ]);
            var colorMap = new ColorMap();
            var _A = colorMap.getId('#F8F8F2');
            var _B = colorMap.getId('#272822');
            var _C = colorMap.getId('#ff0000');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.None, _A, _B),
                el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, 0, 0), [], [{k: 'var', v: el(new ThemeTrieElementRule(1, null, FontStyle.Bold, _C, 0))}]));
            assertThemeEqual(actual, expected);
        });

        T.test('Theme resolving rules are inherited 1', () -> {
            var actual = Theme.createFromParsedTheme([
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#F8F8F2', '#272822'),
                new ParsedThemeRule('var', null, -1, FontStyle.Bold, '#ff0000', null),
                new ParsedThemeRule('var.identifier', null, -1, FontStyle.NotSet, '#00ff00', null),
            ]);
            var colorMap = new ColorMap();
            var _A = colorMap.getId('#F8F8F2');
            var _B = colorMap.getId('#272822');
            var _C = colorMap.getId('#ff0000');
            var _D = colorMap.getId('#00ff00');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.None, _A, _B),
                el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, 0, 0), [], [
                    {
                        k: 'var',
                        v: el(new ThemeTrieElementRule(1, null, FontStyle.Bold, _C, 0), [],
                            [{k: 'identifier', v: el(new ThemeTrieElementRule(2, null, FontStyle.Bold, _D, 0))}])
                    }
                ]));
            assertThemeEqual(actual, expected);
        });

        T.test('Theme resolving rules are inherited 2', () -> {
            var actual = Theme.createFromParsedTheme([
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#F8F8F2', '#272822'),
                new ParsedThemeRule('var', null, -1, FontStyle.Bold, '#ff0000', null),
                new ParsedThemeRule('var.identifier', null, -1, FontStyle.NotSet, '#00ff00', null),
                new ParsedThemeRule('constant', null, 4, FontStyle.Italic, '#100000', null),
                new ParsedThemeRule('constant.numeric', null, 5, FontStyle.NotSet, '#200000', null),
                new ParsedThemeRule('constant.numeric.hex', null, 6, FontStyle.Bold, null, null),
                new ParsedThemeRule('constant.numeric.oct', null, 7, FontStyle.Bold | FontStyle.Italic | FontStyle.Underline, null, null),
                new ParsedThemeRule('constant.numeric.dec', null, 8, FontStyle.None, '#300000', null),
            ]);
            var colorMap = new ColorMap();
            var _A = colorMap.getId('#F8F8F2');
            var _B = colorMap.getId('#272822');
            colorMap.getId('#100000');
            colorMap.getId('#200000');
            colorMap.getId('#300000');
            colorMap.getId('#ff0000');
            colorMap.getId('#00ff00');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.None, _A, _B), el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, 0, 0)));
            assertThemeEqual(actual, expected);
        });

        T.test('Theme resolving rules with parent scopes', () -> {
            var actual = Theme.createFromParsedTheme([
                new ParsedThemeRule('', null, -1, FontStyle.NotSet, '#F8F8F2', '#272822'),
                new ParsedThemeRule('var', null, -1, FontStyle.Bold, '#100000', null),
                new ParsedThemeRule('var.identifier', null, -1, FontStyle.NotSet, '#200000', null),
                new ParsedThemeRule('var', ['source.css'], 1, FontStyle.Italic, '#300000', null),
                new ParsedThemeRule('var', ['source.css'], 2, FontStyle.Underline, null, null),
            ]);
            var colorMap = new ColorMap();
            var _A = colorMap.getId('#F8F8F2');
            var _B = colorMap.getId('#272822');
            colorMap.getId('#100000');
            colorMap.getId('#300000');
            colorMap.getId('#200000');
            var expected = new Theme(colorMap, new StyleAttributes(FontStyle.None, _A, _B), el(new ThemeTrieElementRule(0, null, FontStyle.NotSet, 0, 0)));
            assertThemeEqual(actual, expected);
        });

        T.test('Theme resolving a rule with child combinator', () -> {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#100000'}},
                {scope: 'b a', settings: {foreground: '#200000'}},
                {scope: 'b > a', settings: {foreground: '#300000'}},
                {scope: 'c > b > a', settings: {foreground: '#400000'}},
                {scope: 'a', settings: {foreground: '#500000'}},
            ]));
            var colorMap = theme.getColorMap();
            var match = (path:Array<String>) -> {
                var result = theme.match(from(path));
                return result == null ? null : colorMap[result.foregroundId];
            };
            T.equals(match(['b', 'a']), '#300000', 'b a');
            T.equals(match(['b', 'c', 'a']), '#200000', 'b c a');
            T.equals(match(['c', 'b', 'a']), '#400000', 'c b a');
            T.equals(match(['c', 'b', 'd', 'a']), '#200000', 'c b d a');
        });

        T.test('Theme resolving should give deeper scopes higher specificity (#233)', () -> {
            var theme = Theme.createFromRawTheme(rawTheme([
                {settings: {foreground: '#100000'}},
                {scope: 'y.z a.b', settings: {foreground: '#200000'}},
                {scope: 'x y a.b', settings: {foreground: '#300000'}},
            ]));
            var colorMap = theme.getColorMap();
            var match = (path:Array<String>) -> {
                var result = theme.match(from(path));
                if (result == null || result.foregroundId == 0) {
                    return null;
                }
                return colorMap[result.foregroundId];
            };
            // Sanity check
            T.equals(match(['x', 'a.b']), null, 'x a.b');
            T.equals(match(['y', 'a.b']), null, 'y a.b');
            T.equals(match(['y.z', 'a']), null, 'y.z a');
            T.equals(match(['x', 'y', 'a.b']), '#300000', 'x y a.b');

            // Even though the "x y a.b" rule has more scopes in its path, the "y.z a.b" rule has
            // a deeper match, so it should take precedence.
            T.equals(match(['x', 'y.z', 'a.b']), '#200000', 'y.z a.b');
        });

        T.test('Theme resolving issue #38: ignores rules with invalid colors', () -> {
            var actual = Theme.parseTheme(rawTheme([
                {settings: {background: '#222222', foreground: '#cccccc'}},
                {name: 'Variable', scope: 'variable', settings: {fontStyle: ''}},
                {name: 'Function argument', scope: 'variable.parameter', settings: {fontStyle: 'italic', foreground: ''}},
                {name: 'Library variable', scope: 'support.other.variable', settings: {fontStyle: ''}},
                {name: 'Function argument', scope: 'variable.other', settings: {foreground: '', fontStyle: 'normal'}},
                {name: 'Coffeescript Function argument', scope: 'variable.parameter.function.coffee', settings: {foreground: '#F9D423', fontStyle: 'italic'}}
            ]));
            var expected = [
                new ParsedThemeRule('', null, 0, FontStyle.NotSet, '#cccccc', '#222222'),
                new ParsedThemeRule('variable', null, 1, FontStyle.None, null, null),
                new ParsedThemeRule('variable.parameter', null, 2, FontStyle.Italic, null, null),
                new ParsedThemeRule('support.other.variable', null, 3, FontStyle.None, null, null),
                new ParsedThemeRule('variable.other', null, 4, FontStyle.None, null, null),
                new ParsedThemeRule('variable.parameter.function.coffee', null, 5, FontStyle.Italic, '#F9D423', null),
            ];
            assertRules(actual, expected);
        });

        T.test('Theme resolving issue #35: Trailing comma in a tmTheme scope selector', () -> {
            var actual = Theme.parseTheme(rawTheme([
                {settings: {background: '#25292C', foreground: '#EFEFEF'}},
                {
                    name: 'CSS at-rule keyword control',
                    scope: [
                        'meta.at-rule.return.scss,',
                        'meta.at-rule.return.scss punctuation.definition,',
                        'meta.at-rule.else.scss,',
                        'meta.at-rule.else.scss punctuation.definition,',
                        'meta.at-rule.if.scss,',
                        'meta.at-rule.if.scss punctuation.definition,'
                    ].join('\n'),
                    settings: {foreground: '#CC7832'}
                }
            ]));
            var expected = [
                new ParsedThemeRule('', null, 0, FontStyle.NotSet, '#EFEFEF', '#25292C'),
                new ParsedThemeRule('meta.at-rule.return.scss', null, 1, FontStyle.NotSet, '#CC7832', null),
                new ParsedThemeRule('punctuation.definition', ['meta.at-rule.return.scss'], 1, FontStyle.NotSet, '#CC7832', null),
                new ParsedThemeRule('meta.at-rule.else.scss', null, 1, FontStyle.NotSet, '#CC7832', null),
                new ParsedThemeRule('punctuation.definition', ['meta.at-rule.else.scss'], 1, FontStyle.NotSet, '#CC7832', null),
                new ParsedThemeRule('meta.at-rule.if.scss', null, 1, FontStyle.NotSet, '#CC7832', null),
                new ParsedThemeRule('punctuation.definition', ['meta.at-rule.if.scss'], 1, FontStyle.NotSet, '#CC7832', null),
            ];
            assertRules(actual, expected);
        });
    }
}
