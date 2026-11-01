// Test suite of the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// Replays the tokenization of real grammars recorded with vscode-textmate and
// vscode-oniguruma by test/record/record.mjs: scopes (tokenizeLine) and
// metadata (tokenizeLine2, with themes), token by token.

import haxe.ds.StringMap;
import textmate.IGrammar;
import textmate.Json;
import textmate.OnigLib.IOnigLib;
import textmate.OrderedMap;
import textmate.Plist;
import textmate.RawGrammar;
import textmate.Registry;
import textmate.Textmate;
import textmate.Theme.IRawTheme;

class CorpusTests {
    public static var timings:Array<{backend:String, name:String, lines:Int, ms:Float, warmMs:Float}> = [];

    static final ASSERTION = ~/^\/\/\s*(\^|<-)/;

    public static function corpusLines(text:String, stripAssertions:Bool):Array<String> {
        var lines = StringTools.replace(text, '\r\n', '\n').split('\n');
        if (stripAssertions) {
            lines = lines.filter(l -> !ASSERTION.match(l));
        }
        return lines;
    }

    public static function readRawTheme(def:Dynamic):IRawTheme {
        function load(file:String):IRawTheme {
            var text = Fs.readText('fixtures/' + file);
            if (StringTools.endsWith(file, '.json')) {
                var obj:OrderedMap<Dynamic> = Json.parseJSON(text, null, false);
                if (obj.exists('tokenColors')) {
                    // A VS Code / shiki theme: the editor colors become the default rule
                    var colors:OrderedMap<Dynamic> = obj.get('colors');
                    var settings:Array<Dynamic> = [
                        {
                            settings: {
                                foreground: colors != null ? colors.get('editor.foreground') : null,
                                background: colors != null ? colors.get('editor.background') : null
                            }
                        }
                    ];
                    var tokenColors:Array<Dynamic> = obj.get('tokenColors');
                    return IRawTheme.fromDynamic({name: obj.get('name'), settings: settings.concat(tokenColors)});
                }
                return IRawTheme.fromDynamic(obj);
            }
            return IRawTheme.fromDynamic(Plist.parsePLIST(text));
        }
        var theme = load(def.path);
        if (def.include != null) {
            var inc = load(def.include);
            theme.settings = inc.settings.concat(theme.settings);
        }
        return theme;
    }

    static var manifest:Null<Dynamic> = null;
    static var rawGrammars:Null<StringMap<IRawGrammar>> = null;
    static var caseDefs:Null<StringMap<Dynamic>> = null;

    public static function load():Void {
        if (manifest != null) {
            return;
        }
        manifest = haxe.Json.parse(Fs.readText('fixtures/corpus.json'));
        rawGrammars = new StringMap();
        for (scopeName in Reflect.fields(manifest.grammars)) {
            var file:String = Reflect.field(manifest.grammars, scopeName);
            rawGrammars.set(scopeName, Textmate.parseRawGrammar(Fs.readText('fixtures/' + file), file));
        }
        // The manifest is read again with the port's parser to keep the key order of `config` (token types)
        var ordered:OrderedMap<Dynamic> = Json.parseJSON(Fs.readText('fixtures/corpus.json'), null, false);
        caseDefs = new StringMap();
        for (c in (ordered.get('cases') : Array<Dynamic>)) {
            var cm:OrderedMap<Dynamic> = c;
            caseDefs.set(cm.get('name'), cm);
        }
    }

    static function caseDefFor(name:String):OrderedMap<Dynamic> {
        var def = caseDefs.get(name);
        if (def == null) {
            var slash = name.indexOf('/');
            def = caseDefs.get(name.substring(0, slash));
        }
        return def;
    }

    static function configOf(def:OrderedMap<Dynamic>):Null<OrderedMap<Dynamic>> {
        return def.get('config');
    }

    /**
     * Shared registries per theme (for the cases without a configuration: the
     * grammars are cached by scope name, like in vscode-textmate).
     */
    static var sharedRegistries:Null<StringMap<Registry>> = null;

    static function makeRegistry(onigLib:IOnigLib, themeName:String):Registry {
        return new Registry({
            onigLib: onigLib,
            theme: readRawTheme(Reflect.field(manifest.themes, themeName)),
            loadGrammar: (scopeName) -> rawGrammars.get(scopeName)
        });
    }

    public static function run(onigLib:IOnigLib, backend:String, ?onlyLoreline:Bool = false):Void {
        load();
        T.suite('corpus [$backend]');
        sharedRegistries = new StringMap();
        var index:Array<Dynamic> = haxe.Json.parse(Fs.readText('fixtures/truth/corpus-index.json'));
        var totalLines = 0;
        var totalMs = 0.0;
        var totalWarmMs = 0.0;
        var totalWarmLines = 0;
        for (entry in index) {
            var name:String = entry.name;
            T.test(name, () -> {
                var truth:Dynamic = haxe.Json.parse(Fs.readText('fixtures/truth/' + entry.truth));
                var def = caseDefFor(name);
                var text = Fs.readText('fixtures/' + truth.file);
                var lines = corpusLines(text, def.get('stripAssertions') == true);
                T.equals(lines.length, (truth.lineCount : Int), 'line count');
                var config = configOf(def);
                var scopeTable:Array<String> = truth.scopeTable;
                var expectedTokens:Array<Array<Int>> = truth.tokens;
                var themeNames:Array<String> = def.get('themes');
                var first = true;
                for (themeName in themeNames) {
                    var registry:Registry;
                    var grammar:IGrammar;
                    if (config == null) {
                        registry = sharedRegistries.get(themeName);
                        if (registry == null) {
                            registry = makeRegistry(onigLib, themeName);
                            sharedRegistries.set(themeName, registry);
                        }
                        grammar = registry.loadGrammar(truth.scopeName);
                    } else {
                        registry = makeRegistry(onigLib, themeName);
                        var embedded:Null<OrderedMap<Int>> = null;
                        var emb:OrderedMap<Dynamic> = config.get('embeddedLanguages');
                        if (emb != null) {
                            embedded = new OrderedMap<Int>();
                            for (k in emb.keys()) {
                                embedded.set(k, Std.int(emb.get(k)));
                            }
                        }
                        var tokenTypes:Null<OrderedMap<textmate.EncodedTokenAttributes.StandardTokenType>> = null;
                        var tt:OrderedMap<Dynamic> = config.get('tokenTypes');
                        if (tt != null) {
                            tokenTypes = new OrderedMap();
                            for (k in tt.keys()) {
                                tokenTypes.set(k, Std.int(tt.get(k)));
                            }
                        }
                        var initialLanguage:Dynamic = config.get('initialLanguage');
                        grammar = registry.loadGrammarWithConfiguration(truth.scopeName, initialLanguage != null ? Std.int(initialLanguage) : 0, {
                            embeddedLanguages: embedded,
                            tokenTypes: tokenTypes,
                            balancedBracketSelectors: config.get('balancedBracketSelectors'),
                            unbalancedBracketSelectors: config.get('unbalancedBracketSelectors')
                        });
                    }
                    var themeTruth:Dynamic = Reflect.field(truth.themes, themeName);
                    T.same(registry.getColorMap(), themeTruth.colorMap, '$themeName color map');
                    var expectedBinary:Array<Array<Int>> = themeTruth.lines;

                    if (first) {
                        var state:Null<StateStack> = null;
                        var start = haxe.Timer.stamp();
                        var results = [];
                        for (line in lines) {
                            var r = grammar.tokenizeLine(line, state);
                            results.push(r.tokens);
                            state = r.ruleStack;
                        }
                        var ms = (haxe.Timer.stamp() - start) * 1000;
                        totalMs += ms;
                        totalLines += lines.length;
                        // A second pass, with every scanner already compiled
                        var warmMs = -1.0;
                        if (lines.length >= 100) {
                            var state:Null<StateStack> = null;
                            var start = haxe.Timer.stamp();
                            for (line in lines) {
                                state = grammar.tokenizeLine(line, state).ruleStack;
                            }
                            warmMs = (haxe.Timer.stamp() - start) * 1000;
                            totalWarmMs += warmMs;
                            totalWarmLines += lines.length;
                        }
                        timings.push({backend: backend, name: name, lines: lines.length, ms: ms, warmMs: warmMs});
                        for (i in 0...lines.length) {
                            var tokens = results[i];
                            var exp = expectedTokens[i];
                            var ok = tokens.length * 3 == exp.length;
                            if (ok) {
                                for (k in 0...tokens.length) {
                                    var t = tokens[k];
                                    if (t.startIndex != exp[k * 3] || t.endIndex != exp[k * 3 + 1] || t.scopes.join(' ') != scopeTable[exp[k * 3 + 2]]) {
                                        ok = false;
                                        break;
                                    }
                                }
                            }
                            if (!ok) {
                                var actualStr = [for (t in tokens) t.startIndex + '-' + t.endIndex + ' ' + t.scopes.join(' ')].join(' | ');
                                var expStr = [for (k in 0...Std.int(exp.length / 3)) exp[k * 3] + '-' + exp[k * 3 + 1] + ' ' + scopeTable[exp[k * 3 + 2]]].join(' | ');
                                throw 'scopes of line ${i + 1} `${lines[i]}`:\n    expected $expStr\n    actual   $actualStr';
                            }
                        }
                        first = false;
                    }

                    var state2:Null<StateStack> = null;
                    for (i in 0...lines.length) {
                        var r2 = grammar.tokenizeLine2(lines[i], state2);
                        var exp = expectedBinary[i];
                        var ok = r2.tokens.length == exp.length;
                        if (ok) {
                            for (k in 0...exp.length) {
                                if (((r2.tokens[k] : Int) | 0) != exp[k]) {
                                    ok = false;
                                    break;
                                }
                            }
                        }
                        if (!ok) {
                            throw '$themeName metadata of line ${i + 1} `${lines[i]}`: expected $exp actual ' + [for (k in 0...r2.tokens.length) ((r2.tokens[k] : Int) | 0)];
                        }
                        if (state2 != null) {
                            var diff = Textmate.diffStateStacksRefEq(state2, r2.ruleStack);
                            state2 = Textmate.applyStateStackDiff(state2, diff);
                        } else {
                            state2 = r2.ruleStack;
                        }
                    }
                    if (config != null) {
                        registry.dispose();
                    }
                }
            });
        }
        timings.push({backend: backend, name: '(total)', lines: totalLines, ms: totalMs, warmMs: -1});
        timings.push({backend: backend, name: '(total of the warm passes)', lines: totalWarmLines, ms: totalWarmMs, warmMs: -1});
    }
}
