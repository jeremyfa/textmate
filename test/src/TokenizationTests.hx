// Ported from vscode-textmate 9.2.0: src/tests/tokenization.test.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import haxe.ds.StringMap;
import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.RawGrammar.IRawGrammar;
import textmate.Registry;
import textmate.Textmate;

class TokenizationTests {
    public static function run(onigLib:IOnigLib, backend:String):Void {
        assertTokenizationSuite('first-mate', 'fixtures/vscode-textmate/first-mate/tests.json', onigLib, backend);
        assertTokenizationSuite('suite1', 'fixtures/vscode-textmate/suite1/tests.json', onigLib, backend);
        assertTokenizationSuite('suite1-while', 'fixtures/vscode-textmate/suite1/whileTests.json', onigLib, backend);
    }

    static function assertTokenizationSuite(name:String, testLocation:String, onigLib:IOnigLib, backend:String):Void {
        T.suite('$name [$backend]');
        var tests:Array<Dynamic> = haxe.Json.parse(Fs.readText(testLocation));
        var truth:Array<Dynamic> = haxe.Json.parse(Fs.readText('fixtures/truth/$name.json'));
        for (i in 0...tests.length) {
            var tst = tests[i];
            var expected = truth[i];
            T.test(tst.desc, () -> performTest(tst, expected, testLocation, onigLib));
        }
    }

    static function performTest(test:Dynamic, truth:Dynamic, testLocation:String, onigLib:IOnigLib):Void {
        var grammarScopeName:Null<String> = test.grammarScopeName;
        var grammarByScope = new StringMap<IRawGrammar>();
        var grammars:Array<String> = test.grammars;
        for (grammarPath in grammars) {
            var content = Fs.readText(Fs.join(Fs.dirname(testLocation), grammarPath));
            var rawGrammar = Textmate.parseRawGrammar(content, grammarPath);
            grammarByScope.set(rawGrammar.scopeName, rawGrammar);
            if (grammarScopeName == null && grammarPath == test.grammarPath) {
                grammarScopeName = rawGrammar.scopeName;
            }
        }
        if (grammarScopeName == null) {
            throw 'I HAVE NO GRAMMAR FOR TEST';
        }

        var injections:Null<Array<String>> = test.grammarInjections;
        var registry = new Registry({
            onigLib: onigLib,
            loadGrammar: (scopeName) -> grammarByScope.get(scopeName),
            getInjections: (scopeName) -> scopeName == grammarScopeName ? injections : null
        });
        var grammar = registry.loadGrammar(grammarScopeName);
        if (grammar == null) {
            throw 'I HAVE NO GRAMMAR FOR TEST';
        }
        var prevState:Null<StateStack> = null;
        var lines:Array<Dynamic> = test.lines;
        var truthLines:Array<Dynamic> = truth.lines;
        for (i in 0...lines.length) {
            prevState = assertLineTokenization(grammar, lines[i], truthLines[i], prevState);
        }
        registry.dispose();
    }

    static function assertLineTokenization(grammar:IGrammar, testCase:Dynamic, truthLine:Dynamic, prevState:Null<StateStack>):StateStack {
        var line:String = testCase.line;
        var actual = grammar.tokenizeLine(line, prevState);

        var actualTokens = [for (token in actual.tokens) {value: line.substring(token.startIndex, token.endIndex), scopes: token.scopes}];

        // TODO@Alex: fix tests instead of working around
        var expectedTokens:Array<Dynamic> = testCase.tokens;
        if (line.length > 0) {
            // Remove empty tokens...
            expectedTokens = expectedTokens.filter((token) -> (token.value : String).length > 0);
        }
        var expected = [for (t in expectedTokens) {value: t.value, scopes: t.scopes}];

        T.same(actualTokens, expected, 'Tokenizing line ' + line);
        // The recorded output of vscode-textmate (the same as the upstream expectation)
        T.same(actualTokens, truthLine.tokens, 'Tokenizing line (recorded) ' + line);

        var ruleStack = actual.ruleStack;
        if (prevState != null) {
            var diff = Textmate.diffStateStacksRefEq(prevState, actual.ruleStack);
            ruleStack = Textmate.applyStateStackDiff(prevState, diff);
        }

        return ruleStack;
    }
}
