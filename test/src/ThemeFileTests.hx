// Ported from vscode-textmate 9.2.0: src/tests/themes.test.ts, themeTest.ts and themedTokenizer.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import textmate.EncodedTokenAttributes;
import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.OrderedMap;
import textmate.Plist;
import textmate.Registry;
import textmate.Textmate;
import textmate.Theme.IRawTheme;

class ThemeFileTests {
    static final THEMES_TEST_PATH = 'fixtures/vscode-textmate/themes';

    static function loadThemeFile(filename:String):IRawTheme {
        var fileContents = Fs.readText(Fs.join(THEMES_TEST_PATH, filename));
        if (StringTools.endsWith(filename, '.json')) {
            return IRawTheme.fromDynamic(textmate.Json.parseJSON(fileContents, null, false));
        }
        return IRawTheme.fromDynamic(Plist.parsePLIST(fileContents));
    }

    static function createTheme(filename:String, ?includeFilename:String):IRawTheme {
        var theme = loadThemeFile(filename);
        if (includeFilename != null) {
            var includeTheme = loadThemeFile(includeFilename);
            theme.settings = includeTheme.settings.concat(theme.settings);
        }
        return theme;
    }

    public static function tokenizeWithTheme(colorMap:Array<String>, fileContents:String, grammar:IGrammar):Array<{content:String, color:Null<String>}> {
        var lines = ~/\r\n|\r|\n/g.split(fileContents);

        var ruleStack:Null<StateStack> = null;
        var actual = [];

        for (line in lines) {
            var result = grammar.tokenizeLine2(line, ruleStack);
            var tokensLength = Std.int(result.tokens.length / 2);
            for (j in 0...tokensLength) {
                var startIndex:Int = result.tokens[2 * j];
                var nextStartIndex:Int = j + 1 < tokensLength ? result.tokens[2 * j + 2] : line.length;
                var tokenText = line.substring(startIndex, nextStartIndex);
                if (tokenText == '') {
                    continue;
                }
                var metadata:Int = result.tokens[2 * j + 1];
                var foreground = EncodedTokenAttributes.getForeground(metadata);
                var foregroundColor = colorMap[foreground];

                actual.push({content: tokenText, color: foregroundColor});
            }

            if (ruleStack != null) {
                var diff = Textmate.diffStateStacksRefEq(ruleStack, result.ruleStack);
                ruleStack = Textmate.applyStateStackDiff(ruleStack, diff);
            } else {
                ruleStack = result.ruleStack;
            }
        }

        return actual;
    }

    public static function run(onigLib:IOnigLib, backend:String):Void {
        T.suite('themes [$backend]');
        var themes:Array<Array<String>> = [
            ['abyss', 'Abyss.tmTheme'],
            ['dark_vs', 'dark_vs.json'],
            ['light_vs', 'light_vs.json'],
            ['hc_black', 'hc_black.json'],
            ['dark_plus', 'dark_plus.json', 'dark_vs.json'],
            ['light_plus', 'light_plus.json', 'light_vs.json'],
            ['kimbie_dark', 'Kimbie_dark.tmTheme'],
            ['monokai', 'Monokai.tmTheme'],
            ['monokai_dimmed', 'dimmed-monokai.tmTheme'],
            ['quietlight', 'QuietLight.tmTheme'],
            ['red', 'red.tmTheme'],
            ['solarized_dark', 'Solarized-dark.tmTheme'],
            ['solarized_light', 'Solarized-light.tmTheme'],
            ['tomorrow_night_blue', 'Tomorrow-Night-Blue.tmTheme'],
        ];

        // Load all language/grammar metadata
        var grammars:Array<Resolver.IGrammarRegistration> = haxe.Json.parse(Fs.readText(Fs.join(THEMES_TEST_PATH, 'grammars.json')));
        for (grammar in grammars) {
            grammar.path = Fs.join(THEMES_TEST_PATH, grammar.path);
        }
        var languages:Array<Resolver.ILanguageRegistration> = haxe.Json.parse(Fs.readText(Fs.join(THEMES_TEST_PATH, 'languages.json')));
        var resolver = new Resolver(grammars, languages);

        var truth:Dynamic = haxe.Json.parse(Fs.readText('fixtures/truth/themes.json'));

        // Discover all tests
        var testFiles = Fs.readDir(Fs.join(THEMES_TEST_PATH, 'tests')).filter(f -> !StringTools.endsWith(f, '.result')
            && !StringTools.endsWith(f, '.result.patch') && !StringTools.endsWith(f, '.actual') && !StringTools.endsWith(f, '.diff.html'));
        testFiles = testFiles.filter(f -> T.enabled(f));

        // Upstream keeps one registry per theme alive for the whole suite. The
        // themes are run one after the other here, each registry disposed before
        // the next one, so that the memory of one set of grammars is enough
        // (same results: the registries are independent).
        var actualByFile = new haxe.ds.StringMap<Array<{theme:String, actual:Dynamic}>>();
        for (t in themes) {
            var registry = new Registry({onigLib: onigLib, loadGrammar: resolver.loadGrammar});
            registry.setTheme(createTheme(t[1], t[2]));
            for (testFile in testFiles) {
                var list = actualByFile.get(testFile);
                if (list == null) {
                    list = [];
                    actualByFile.set(testFile, list);
                }
                var actual:Dynamic;
                try {
                    var contents = Fs.readText(Fs.join(Fs.join(THEMES_TEST_PATH, 'tests'), testFile));
                    var language = resolver.findLanguageByExtension(Fs.extname(testFile));
                    if (language == null) {
                        language = resolver.findLanguageByFilename(testFile);
                    }
                    if (language == null) {
                        throw 'Could not determine language for ' + testFile;
                    }
                    var grammar = resolver.findGrammarByLanguage(language);

                    var embeddedLanguages = new OrderedMap<Int>();
                    if (grammar.embeddedLanguages != null) {
                        for (scopeName in Reflect.fields(grammar.embeddedLanguages)) {
                            embeddedLanguages.set(scopeName, resolver.language2id.get(Reflect.field(grammar.embeddedLanguages, scopeName)));
                        }
                    }
                    var g = registry.loadGrammarWithEmbeddedLanguages(grammar.scopeName, resolver.language2id.get(language), embeddedLanguages);
                    if (g == null) {
                        throw 'Cannot load grammar for ' + grammar.scopeName;
                    }
                    actual = tokenizeWithTheme(registry.getColorMap(), contents, g);
                } catch (e:Dynamic) {
                    actual = 'error: ' + Std.string(e);
                }
                list.push({theme: t[0], actual: actual});
            }
            registry.dispose();
        }

        for (testFile in testFiles) {
            T.test(testFile, () -> {
                var entry:Dynamic = Reflect.field(truth, testFile);
                // The recorder keeps the actual output of vscode-textmate only when it differs from the .result file
                var expected:Dynamic = entry.matchesUpstream == true ? haxe.Json.parse(Fs.readText(Fs.join(Fs.join(THEMES_TEST_PATH, 'tests'),
                    testFile + '.result'))) : entry.actual;
                for (r in actualByFile.get(testFile)) {
                    if (Std.isOfType(r.actual, String)) {
                        throw r.theme + ': ' + r.actual;
                    }
                    var exp:Array<Dynamic> = Reflect.field(expected, r.theme);
                    var expPlain = [for (e in exp) {content: e.content, color: e.color}];
                    T.same(r.actual, expPlain, r.theme);
                }
            });
        }
    }
}
