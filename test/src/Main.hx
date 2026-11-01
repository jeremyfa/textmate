// Test runner of the Haxe port of vscode-textmate 9.2.0.
// Usage (from the test folder):
//   node bin/test.js [--onig=haxe|wasm|both] [--verbose] [--bench] [filter]
//   bin/cpp/Main [--verbose] [filter]
// The wasm backend (JavaScript only) needs vscode-oniguruma 2.0.1: set
// VSCODE_ONIGURUMA to its package folder, or make it resolvable by require.

import textmate.OnigLib.IOnigLib;

class Main {
    static function main() {
        var args = getArgs();
        var backends = ['haxe'];
        var bench = false;
        for (a in args) {
            if (StringTools.startsWith(a, '--onig=')) {
                var v = a.substring(7);
                backends = v == 'both' ? ['haxe', 'wasm'] : [v];
            } else if (a == '--bench') {
                bench = true;
            } else if (a == '--verbose') {
                T.verbose = true;
            } else if (!StringTools.startsWith(a, '--')) {
                T.filter = a;
            }
        }
        #if js
        if (backends.indexOf('wasm') != -1) {
            var onig:Dynamic = loadVscodeOniguruma();
            var fs:Dynamic = js.Lib.require('fs');
            var path:Dynamic = js.Lib.require('path');
            var wasm = fs.readFileSync(path.join(onigPackageDir(), 'release/onig.wasm')).buffer;
            onig.loadWASM(wasm).then((_) -> bench ? runBench(backends, onig) : runAll(backends, onig));
            return;
        }
        #end
        if (bench) {
            runBench(backends, null);
        } else {
            runAll(backends, null);
        }
    }

    static function runBench(backends:Array<String>, wasmModule:Dynamic):Void {
        T.println('tokenizeLine on the large samples (best of 3 warm passes):');
        for (backend in backends) {
            Bench.run(libFor(backend, wasmModule), backend, 3);
        }
    }

    #if js
    static function onigPackageDir():String {
        var env:Dynamic = js.Syntax.code("process.env.VSCODE_ONIGURUMA");
        if (env != null) {
            return env;
        }
        var path:Dynamic = js.Lib.require('path');
        return path.dirname(js.Syntax.code("require.resolve('vscode-oniguruma/package.json')"));
    }

    static function loadVscodeOniguruma():Dynamic {
        return js.Lib.require(onigPackageDir());
    }
    #end

    static function getArgs():Array<String> {
        #if js
        var argv:Array<String> = js.Syntax.code("process.argv");
        return argv.slice(2);
        #else
        return Sys.args();
        #end
    }

    static function libFor(backend:String, wasmModule:Dynamic):IOnigLib {
        return switch backend {
            case 'haxe':
                new OnigurumaOnigLib();
            #if js
            case 'wasm':
                new textmate.onig.WasmOnigLib(wasmModule);
            #end
            default:
                throw 'Unknown backend ' + backend;
        }
    }

    static function runAll(backends:Array<String>, wasmModule:Dynamic):Void {
        var start = haxe.Timer.stamp();
        MatcherTests.run();
        GrammarTests.run();
        ThemeUnitTests.run();
        JsonTests.run();
        for (backend in backends) {
            var lib = libFor(backend, wasmModule);
            TokenizationTests.run(lib, backend);
            ThemeFileTests.run(lib, backend);
            MiscTests.run(lib, backend);
            LorelineSyntaxTests.run(lib, backend);
            CorpusTests.run(lib, backend);
        }
        T.endSuite();

        for (f in T.failures) {
            T.println('FAIL ' + f);
        }
        T.println('');
        for (s in T.suiteResults) {
            if (s.passed + s.failed == 0) {
                continue;
            }
            T.println('${s.name}: ${s.passed} passed, ${s.failed} failed (${Math.round(s.ms)} ms)');
        }
        if (LorelineSyntaxTests.assertionCount > 0) {
            T.println('loreline-syntax assertions checked (last backend): ${LorelineSyntaxTests.assertionCount}');
        }
        T.println('');
        T.println('Corpus tokenizeLine timings:');
        var big = ['javascript/shiki-vscode-textmate.js', 'javascript/vscode-textmate-main.min.js', 'typescript/grammar.ts', 'rust/rope.rs', 'yaml/pnpm-lock.yaml', 'haxe/Rule.hx', 'shell/perltest.sh', 'markdown/vscode-textmate-README.md', '(total)', '(total of the warm passes)'];
        for (t in CorpusTests.timings) {
            if (big.indexOf(t.name) != -1) {
                var perLine = t.lines > 0 ? t.ms / t.lines : 0.0;
                var warm = t.warmMs >= 0 ? ', warm ${Math.round(t.warmMs)} ms (${Math.round(t.warmMs / t.lines * 1000) / 1000} ms/line)' : '';
                T.println('  [${t.backend}] ${t.name}: ${t.lines} lines, ${Math.round(t.ms)} ms, ${Math.round(perLine * 1000) / 1000} ms/line$warm');
            }
        }
        T.println('');
        T.println('${T.passed} passed, ${T.failed} failed in ${Math.round((haxe.Timer.stamp() - start) * 1000)} ms');
        #if js
        js.Syntax.code("process.exitCode = {0}", T.failed == 0 ? 0 : 1);
        #else
        Sys.exit(T.failed == 0 ? 0 : 1);
        #end
    }
}
