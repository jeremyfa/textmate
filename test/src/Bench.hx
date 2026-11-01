// Benchmark of the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// tokenizeLine over the large samples of the corpus: a cold pass (scanners
// compiled on the way) then warm passes. test/record/bench.mjs times the real
// vscode-textmate the same way.

import haxe.ds.StringMap;
import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.RawGrammar.IRawGrammar;
import textmate.Registry;
import textmate.Textmate;

class Bench {
    public static final NAMES = [
        'javascript/shiki-vscode-textmate.js',
        'javascript/vscode-textmate-main.min.js',
        'typescript/grammar.ts',
        'haxe/Rule.hx',
        'rust/rope.rs',
        'markdown/vscode-textmate-README.md',
        'yaml/pnpm-lock.yaml',
        'shell/perltest.sh',
        'loreline-test'
    ];

    public static function run(onigLib:IOnigLib, backend:String, warmPasses:Int):Void {
        var corpus:Dynamic = haxe.Json.parse(Fs.readText('fixtures/corpus.json'));
        var raws = new StringMap<IRawGrammar>();
        for (s in Reflect.fields(corpus.grammars)) {
            var file:String = Reflect.field(corpus.grammars, s);
            raws.set(s, Textmate.parseRawGrammar(Fs.readText('fixtures/' + file), file));
        }
        var registry = new Registry({onigLib: onigLib, loadGrammar: (s) -> raws.get(s)});
        var totalLines = 0;
        var totalCold = 0.0;
        var totalWarm = 0.0;
        for (c in (corpus.cases : Array<Dynamic>)) {
            if (NAMES.indexOf(c.name) == -1 || (T.filter != null && (c.name : String).indexOf(T.filter) == -1)) {
                continue;
            }
            var files:Array<String> = [];
            if (c.dir != null) {
                for (f in Fs.readDir('fixtures/' + c.dir)) {
                    if (StringTools.endsWith(f, c.ext)) {
                        files.push(c.dir + '/' + f);
                    }
                }
            } else {
                files.push(c.file);
            }
            var texts = [for (f in files) CorpusTests.corpusLines(Fs.readText('fixtures/' + f), false)];
            var lineCount = 0;
            for (t in texts) {
                lineCount += t.length;
            }
            var grammar = registry.loadGrammar(c.scopeName);
            var times = [];
            for (pass in 0...1 + warmPasses) {
                var start = haxe.Timer.stamp();
                for (lines in texts) {
                    var state:Null<StateStack> = null;
                    for (line in lines) {
                        state = grammar.tokenizeLine(line, state).ruleStack;
                    }
                }
                times.push((haxe.Timer.stamp() - start) * 1000);
            }
            var cold = times[0];
            var warm = times.length > 1 ? Lambda.fold(times.slice(1), (a, b) -> Math.min(a, b), times[1]) : cold;
            totalLines += lineCount;
            totalCold += cold;
            totalWarm += warm;
            T.println('  [$backend] ${c.name}: $lineCount lines, cold ${fmt(cold)} ms (${fmt3(cold / lineCount)} ms/line), warm ${fmt(warm)} ms (${fmt3(warm / lineCount)} ms/line)');
        }
        T.println('  [$backend] total: $totalLines lines, cold ${fmt(totalCold)} ms (${fmt3(totalCold / totalLines)} ms/line), warm ${fmt(totalWarm)} ms (${fmt3(totalWarm / totalLines)} ms/line)');
        registry.dispose();
    }

    static function fmt(v:Float):String {
        return Std.string(Math.round(v));
    }

    static function fmt3(v:Float):String {
        return Std.string(Math.round(v * 1000) / 1000);
    }
}
