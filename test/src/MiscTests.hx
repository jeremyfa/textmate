// Test suite of the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// Behaviors of the port that the other suites do not reach.

import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.OrderedMap;
import textmate.Plist;
import textmate.Registry;
import textmate.Textmate;

class MiscTests {
    public static function run(onigLib:IOnigLib, backend:String):Void {
        T.suite('misc [$backend]');

        T.test('time limit stops early and the state can be reused', () -> {
            var raw = Textmate.parseRawGrammar(Fs.readText('fixtures/grammars/javascript.json'), 'javascript.json');
            var registry = new Registry({onigLib: onigLib, loadGrammar: (s) -> s == raw.scopeName ? raw : null});
            var grammar = registry.loadGrammar('source.js');
            var buf = new StringBuf();
            for (i in 0...4000) {
                buf.add('var a$i = "s" + $i * (b - c) / 2; ');
            }
            var r = grammar.tokenizeLine(buf.toString(), null, 1);
            T.equals(r.stoppedEarly, true, 'stoppedEarly');
            var r2 = grammar.tokenizeLine('var x = 1;', r.ruleStack);
            T.equals(r2.stoppedEarly, false);
            T.isTrue(r2.tokens.length > 0);
            registry.dispose();
        });

        T.test('UTF-16 offsets with astral characters', () -> {
            var raw = Textmate.parseRawGrammar(Fs.readText('fixtures/grammars/json.json'), 'json.json');
            var registry = new Registry({onigLib: onigLib, loadGrammar: (s) -> s == raw.scopeName ? raw : null});
            var grammar = registry.loadGrammar('source.json');
            var line = '{"\u{1F600}": "é\u{1F680}x", "k": 1}';
            var r = grammar.tokenizeLine(line, null);
            var values = [for (t in r.tokens) line.substring(t.startIndex, t.endIndex)];
            T.same(values, ['{', '"', '\u{1F600}', '"', ':', ' ', '"', 'é\u{1F680}x', '"', ',', ' ', '"', 'k', '"', ':', ' ', '1', '}']);
            T.equals(r.tokens[2].endIndex - r.tokens[2].startIndex, 2, 'a surrogate pair is two UTF-16 code units');
            registry.dispose();
        });

        T.test('StateStack equals and clone', () -> {
            var raw = Textmate.parseRawGrammar(Fs.readText('fixtures/grammars/javascript.json'), 'javascript.json');
            var registry = new Registry({onigLib: onigLib, loadGrammar: (s) -> s == raw.scopeName ? raw : null});
            var grammar = registry.loadGrammar('source.js');
            var a = grammar.tokenizeLine('/* open', null).ruleStack;
            var b = grammar.tokenizeLine('/* other', null).ruleStack;
            var c = grammar.tokenizeLine('var x;', null).ruleStack;
            T.isTrue(a.equals(b), 'same comment state');
            T.isTrue(!a.equals(c), 'different state');
            T.isTrue(a.clone() == a, 'clone returns the same immutable object');
            T.equals(a.depth, 2);
            T.isTrue(Textmate.INITIAL.depth == 1);
            registry.dispose();
        });

        T.test('plist values', () -> {
            var v:OrderedMap<Dynamic> = Plist.parsePLIST('<?xml version="1.0"?><!DOCTYPE plist><plist version="1.0"><dict>'
                + '<key>a</key><string>x &lt;&amp;&gt; &#65;&#x42; &quot;&apos;</string><key>b</key><integer>42</integer><key>c</key><real>1.5</real>'
                + '<key>d</key><true/><key>e</key><false/><key>f</key><array><string>1</string><dict/></array><key>g</key><string/></dict></plist>');
            T.equals(v.get('a'), 'x <&> AB "\'');
            T.equals(v.get('b'), 42.0);
            T.equals(v.get('c'), 1.5);
            T.equals(v.get('d'), true);
            T.equals(v.get('e'), false);
            var f:Array<Dynamic> = v.get('f');
            T.equals(f.length, 2);
            T.equals(v.get('g'), '');
        });

        T.test('addGrammar and injections through getInjections', () -> {
            var g = textmate.RawGrammar.IRawGrammar.fromDynamic({
                scopeName: 'source.test',
                patterns: ([{match: 'foo', name: 'keyword.foo'}, {begin: '"', end: '"', name: 'string.quoted'}] : Array<Dynamic>)
            });
            var inj = textmate.RawGrammar.IRawGrammar.fromDynamic({
                scopeName: 'inject.test',
                injectionSelector: 'L:string.quoted',
                patterns: [{match: 'foo', name: 'constant.injected'}]
            });
            var registry = new Registry({
                onigLib: onigLib,
                loadGrammar: (s) -> s == 'inject.test' ? inj : null,
                getInjections: (s) -> s == 'source.test' ? ['inject.test'] : null
            });
            var grammar = registry.loadGrammar('inject.test');
            T.isTrue(grammar != null);
            var main = registry.addGrammar(g, ['inject.test']);
            var r = main.tokenizeLine('foo "foo"', null);
            T.same([for (t in r.tokens) t.scopes.join(' ')], [
                'source.test keyword.foo',
                'source.test',
                'source.test string.quoted',
                'source.test string.quoted constant.injected',
                'source.test string.quoted'
            ]);
            registry.dispose();
        });
    }
}
