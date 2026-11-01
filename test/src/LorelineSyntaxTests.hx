// Test suite of the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// The syntax coloring assertions of Loreline (loreline/test-syntax/run.mjs,
// MIT, Copyright (c) 2025 Jérémy Faivre), checked on the scopes of this port.
// The parsing and checking logic is translated from run.mjs.

import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.Registry;
import textmate.Textmate;

private typedef Assertion = {
    codeIndex:Int,
    columns:Array<Int>,
    scopes:Array<String>,
    negative:Bool,
    sourceLine:Int,
    text:String
}

class LorelineSyntaxTests {
    static final ASSERTION = ~/^\/\/\s*(\^|<-)/;
    static final ARROW = ~/^\/\/\s*<(-+)(.*)$/;

    public static var assertionCount = 0;

    /**
     * Splits a test file into the code to tokenize and its assertions.
     */
    static function parseTestFile(source:String):{code:Array<{text:String, sourceLine:Int}>, assertions:Array<Assertion>} {
        var lines = StringTools.replace(source, '\r\n', '\n').split('\n');
        var code = [];
        var assertions:Array<Assertion> = [];
        for (i in 0...lines.length) {
            var line = lines[i];
            if (!ASSERTION.match(line)) {
                code.push({text: line, sourceLine: i + 1});
                continue;
            }
            if (code.length == 0) {
                throw 'line ${i + 1}: assertion without a code line above it';
            }
            var columns:Array<Int> = [];
            var rest:String;
            if (ARROW.match(line)) {
                columns = [for (c in 0...ARROW.matched(1).length) c];
                rest = ARROW.matched(2);
            } else {
                var c = 2;
                while (c < line.length && (line.charAt(c) == '^' || line.charAt(c) == ' ')) {
                    if (line.charAt(c) == '^') {
                        columns.push(c);
                    }
                    c++;
                }
                rest = line.substring(c);
            }
            rest = textmate.Utils.jsTrim(rest);
            var negative = StringTools.startsWith(rest, '- ');
            var scopes = ~/\s+/g.split(textmate.Utils.jsTrim(negative ? rest.substring(2) : rest)).filter(s -> s.length > 0);
            if (scopes.length == 0) {
                throw 'line ${i + 1}: assertion without any scope';
            }
            assertions.push({codeIndex: code.length - 1, columns: columns, scopes: scopes, negative: negative, sourceLine: i + 1, text: line});
        }
        return {code: code, assertions: assertions};
    }

    /**
     * Scope stack of every column of every line, without the root scope.
     */
    static function scopesByColumn(grammar:IGrammar, code:Array<{text:String, sourceLine:Int}>):Array<Array<Array<String>>> {
        var state:Null<StateStack> = null;
        var result = [];
        for (l in code) {
            var r = grammar.tokenizeLine(l.text, state);
            state = r.ruleStack;
            var columns = [];
            for (token in r.tokens) {
                var scopes = token.scopes.filter(s -> s != 'source.loreline');
                for (k in token.startIndex...token.endIndex) {
                    columns.push(scopes);
                }
            }
            result.push(columns);
        }
        return result;
    }

    static function hasScope(stack:Array<String>, expected:String):Bool {
        for (s in stack) {
            if (s == expected || StringTools.startsWith(s, expected + '.')) {
                return true;
            }
        }
        return false;
    }

    public static function run(onigLib:IOnigLib, backend:String):Void {
        T.suite('loreline-syntax [$backend]');
        var raw = Textmate.parseRawGrammar(Fs.readText('fixtures/loreline/loreline.tmLanguage.json'), 'loreline.tmLanguage.json');
        var registry = new Registry({onigLib: onigLib, loadGrammar: (s) -> s == raw.scopeName ? raw : null});
        var grammar = registry.loadGrammar(raw.scopeName);
        assertionCount = 0;
        for (file in Fs.readDir('fixtures/loreline/test-syntax').filter(f -> StringTools.endsWith(f, '.lor'))) {
            T.test(file, () -> {
                var parsed = parseTestFile(Fs.readText('fixtures/loreline/test-syntax/' + file));
                var columns = scopesByColumn(grammar, parsed.code);
                var failures = [];
                for (assertion in parsed.assertions) {
                    assertionCount++;
                    var line = parsed.code[assertion.codeIndex];
                    var lineScopes = columns[assertion.codeIndex];
                    for (c in assertion.columns) {
                        var stack = c < lineScopes.length ? lineScopes[c] : null;
                        var problem:Null<String> = null;
                        if (stack == null) {
                            problem = 'column is past the end of the line';
                        } else {
                            for (scope in assertion.scopes) {
                                if (hasScope(stack, scope) == assertion.negative) {
                                    problem = assertion.negative ? 'has $scope' : 'lacks $scope';
                                    break;
                                }
                            }
                        }
                        if (problem != null) {
                            failures.push('line ${assertion.sourceLine} column $c: $problem (`${line.text}`, scopes ${stack})');
                            // One failure per assertion is enough to point at it
                            break;
                        }
                    }
                }
                if (failures.length > 0) {
                    throw failures.join('\n    ');
                }
            });
        }
        registry.dispose();
    }
}
