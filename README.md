# textmate (Haxe port)

A pure Haxe port of [vscode-textmate](https://github.com/microsoft/vscode-textmate) **9.2.0**, the library Visual Studio Code uses to tokenize text with TextMate grammars (`.tmLanguage.json` and `.tmLanguage` plist files) and to resolve the colors and font styles of a theme. 9.2.0 is the version the shiki fork (`@shikijs/vscode-textmate` 10.0.2, used by shiki 3.23) is based on: the fork does not change the tokenization.

It supports complete grammars exactly like VS Code: `match`, `begin` / `end` and `begin` / `while` rules, back-references in `end` and `while`, `\A`, `\G` and `\z` handling, captures with nested patterns, `$self` / `$base` / repository / external includes, injections (grammar `injections` and injection grammars with `L:` / `R:` priorities), embedded languages, token types, balanced bracket selectors and time limits.

It has no dependency. The regular expressions are matched by an Oniguruma engine given to the `Registry` (`IOnigLib`, like vscode-textmate): the pure Haxe [`oniguruma`](../oniguruma) library, or vscode-oniguruma's `onig.wasm` on the JavaScript target (`textmate.onig.WasmOnigLib`). Offsets are UTF-16 code units, like vscode-textmate (Haxe strings are UTF-16 on JavaScript and hxcpp).

All credit for the design and the algorithms goes to vscode-textmate. This port translates the TypeScript sources file by file: each Haxe module starts with a header naming the file it comes from. The code is distributed under the same terms as vscode-textmate, MIT (see [LICENSE](LICENSE)).

## What is ported

The whole library:

- `main.ts`: `Registry`, `RegistryOptions`, `IGrammarConfiguration`, `IGrammar`, `ITokenizeLineResult`, `ITokenizeLineResult2`, `IToken`, `StateStack`, `INITIAL`, `parseRawGrammar`, `diffStateStacksRefEq`, `applyStateStackDiff`;
- `registry.ts` (`SyncRegistry`), `rule.ts` (rules, `RuleFactory`, `RegExpSource`, `RegExpSourceList`, `CompiledRule`), `grammar/grammar.ts` (`Grammar`, `AttributedScopeStack`, `StateStackImpl`, `BalancedBracketSelectors`, `LineTokens`), `grammar/tokenizeString.ts`, `grammar/grammarDependencies.ts`, `grammar/basicScopesAttributeProvider.ts`;
- `theme.ts` (`Theme`, `parseTheme`, scope matching with parent scopes and child combinators, `ColorMap`, the theme trie), `encodedTokenAttributes.ts`, `matcher.ts` (scope selectors), `diffStateStacks.ts`, `utils.ts`, `onigLib.ts`, `rawGrammar.ts`;
- the readers: `plist.ts` (`parsePLIST`, `parseWithLocation`), `json.ts` (`parseJSON`, with locations), `parseRawGrammar.ts`.

Not ported: the debug logging of `DebugFlags.InDebugMode` (the shiki fork removes it too; the flag still turns on location recording when parsing grammars), the RegExp literal sources of the shiki fork (sources are strings, as in vscode-textmate), and the font attributes added after 9.2.0 (9.3).

## Usage

```haxe
import textmate.IGrammar;
import textmate.Registry;
import textmate.Textmate;
import textmate.EncodedTokenAttributes;

class Main {

    static function main() {
        var raw = Textmate.parseRawGrammar(sys.io.File.getContent('JSON.tmLanguage.json'), 'JSON.tmLanguage.json');
        var registry = new Registry({
            onigLib: myOnigLib, // an IOnigLib, see below
            theme: textmate.Theme.IRawTheme.fromDynamic(myThemeObject),
            loadGrammar: scopeName -> scopeName == raw.scopeName ? raw : null
        });
        var grammar = registry.loadGrammar('source.json');

        var state:StateStack = Textmate.INITIAL;
        for (line in ['{ "a": [1, true] }']) {
            var r = grammar.tokenizeLine(line, state);
            for (token in r.tokens) {
                trace(token.startIndex + '-' + token.endIndex + ': ' + token.scopes.join(' '));
            }
            state = r.ruleStack;
        }

        var colorMap = registry.getColorMap();
        var r2 = grammar.tokenizeLine2('{ "a": 1 }', null);
        for (i in 0...Std.int(r2.tokens.length / 2)) {
            var metadata:Int = r2.tokens[2 * i + 1];
            trace(r2.tokens[2 * i] + ': ' + colorMap[EncodedTokenAttributes.getForeground(metadata)]);
        }
    }

}
```

An `IOnigLib` for the pure Haxe `oniguruma` library is a small adapter (this library does not depend on `oniguruma`): `test/src/OnigurumaOnigLib.hx` is one, and can be copied as is. On JavaScript, `new textmate.onig.WasmOnigLib(vscodeOniguruma)` wraps the vscode-oniguruma module after the host called `loadWASM` and waited for it (it loads nothing itself).

## Differences with the TypeScript API

- Synchronous, like the shiki fork: `RegistryOptions.onigLib` is the `IOnigLib` itself (not a promise), `loadGrammar` returns the raw grammar (or null), and `Registry.loadGrammar`, `loadGrammarWithEmbeddedLanguages`, `loadGrammarWithConfiguration` and `addGrammar` return the grammar directly.
- Raw grammars and themes are typed objects: `IRawGrammar`, `IRawRule`, `IRawTheme`, `IRawThemeSetting` (with `fromDynamic` to convert a parsed file or anonymous structures). `while` is `while_`, `$vscodeTextmateLocation` is `vscodeTextmateLocation`, and `IRawRule.hasBegin` stands for `typeof begin !== 'undefined'`. Values that are not strings where strings are expected are read as missing.
- The JavaScript objects used as maps (repositories, captures, injections, embedded languages, token types, the children of the theme trie) are `textmate.OrderedMap`, which iterates like a JavaScript object (array index keys first, then insertion order), so that the order of injections and token types is the same on every target. `Json.parseJSON` and `Plist.parsePLIST` return `OrderedMap<Dynamic>` objects for that reason; `parseRawGrammar` uses `Json.parseJSON` for `.json` files where vscode-textmate uses `JSON.parse` (same values).
- `Json.parseJSON` decodes the string escapes in one pass, like `JSON.parse`. The original replaces `\uXXXX` before the other escapes, so it rejects `"\\u0041"` (an escaped backslash before `u`); it only runs in debug mode upstream.
- The free functions of `main.ts` are static functions of `textmate.Textmate`. Module level functions are static functions of a class of their module: `Theme.parseTheme`, `Theme.fontStyleToString`, `Matchers.createMatchers`, `GrammarTools.createGrammar`, `GrammarDependencies.parseInclude`, `TokenizeString._tokenizeString`, `DiffStateStacks`, `Utils`, `Rules.endRuleId` / `whileRuleId`, `OnigLib.disposeOnigString`.
- `EncodedTokenAttributes` is a class of static functions on `Int` values: a metadata with the highest background bit set is a negative `Int` (the same bits). `EncodedTokenAttributes.set` takes `containsBalancedBrackets` as `-1` (null), `0` or `1`. `ITokenizeLineResult2.tokens` is a `haxe.io.UInt32Array`.
- `ScopeStack.from` takes an array, the static `ScopeStack.push(path, names)` is `ScopeStack.pushAll`, `extends` is `extends_`, `AttributedScopeStack.equals(a, b)` is `equalsStacks`.
- `OnigScanner.findNextMatchSync` takes an `OnigString` (vscode-textmate always passes one) and the options as an `Int` mask of `FindOption`. `IOnigMatch` and `IOnigCaptureIndex` are classes; on JavaScript, plain objects with the same fields can be returned (that is how `WasmOnigLib` returns vscode-oniguruma's results without copying).
- Errors are thrown as strings with upstream's messages.

## Tests

The `test` folder contains a runner that does not need Ceramic. The truth is the real vscode-textmate 9.2.0 with vscode-oniguruma 2.0.1: `test/record/record.mjs` runs them in node and writes `test/fixtures/truth`, and the runner replays it.

- vscode-textmate's own suites, translated: `matcher.test.ts` (27), `grammar.test.ts` (9), `themes.test.ts` unit tests (53), `json.test.ts` (7, plus 3 for the port), `tokenization.test.ts` on the first-mate fixtures (64), `suite1` (20) and the `while` tests (9), and the theme tests (72 files tokenized with 14 themes, compared with the recorded output, which is also equal to the upstream `.result` files);
- a corpus of real grammars from shiki's tm-grammars (JSON, JavaScript, TypeScript, Haxe, Rust, Markdown with embedded code, HTML with embedded CSS and JavaScript, CSS, YAML, shell) and Loreline's grammar on the Loreline test files: 451 cases, 33186 lines, compared token by token (scopes from `tokenizeLine`, metadata from `tokenizeLine2` with two themes each, color maps), with embedded languages, token types and balanced bracket selectors on some cases;
- the 925 coloring assertions of Loreline's `test-syntax` (the checks of its `run.mjs`), and a few behavior tests (time limit, UTF-16 offsets, state equality, plist values, injection grammars).

```sh
cd test
./run.sh                       # JavaScript build, run with node (pure Haxe oniguruma)
./run.sh --onig=both           # also with vscode-oniguruma's onig.wasm (VSCODE_ONIGURUMA=<package folder>)
haxe build-cpp.hxml && ./bin/cpp/Main   # native build (needs hxcpp)
node bin/test.js --bench --onig=both  # timings on the large samples
```

`test/record/bench.mjs` times the real vscode-textmate the same way: with onig.wasm, the port runs at the speed of vscode-textmate.

To record the truth again: `npm install vscode-textmate@9.2.0 vscode-oniguruma@2.0.1` in a scratch folder, then `VTM_NODE_MODULES=<that folder>/node_modules node test/record/record.mjs`.
