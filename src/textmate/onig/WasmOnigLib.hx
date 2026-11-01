// Written for the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// It wraps vscode-oniguruma the way vscode-textmate's tests do (src/tests/onigLibs.ts).
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate.onig;

#if js
import textmate.OnigLib;

/**
 * An `IOnigLib` backed by vscode-oniguruma (onig.wasm), on the JavaScript
 * target only.
 *
 * It does not load anything: `onigModule` is the vscode-oniguruma module
 * object (the result of `require('vscode-oniguruma')` or of its ES module
 * import), on which the host already called `loadWASM(...)` and waited for the
 * returned promise. Only `createOnigScanner`, `createOnigString` and the
 * scanner's `findNextMatchSync` are used.
 *
 * ```haxe
 * var registry = new Registry({
 *     onigLib: new WasmOnigLib(vscodeOniguruma),
 *     loadGrammar: scopeName -> ...
 * });
 * ```
 */
class WasmOnigLib implements IOnigLib {
    final onigModule:Dynamic;

    public function new(onigModule:Dynamic) {
        this.onigModule = onigModule;
    }

    public function createOnigScanner(sources:Array<String>):OnigScanner {
        return new WasmOnigScanner(onigModule.createOnigScanner(sources));
    }

    public function createOnigString(str:String):OnigString {
        return new WasmOnigString(onigModule.createOnigString(str));
    }
}

private class WasmOnigScanner implements OnigScanner {
    final scanner:Dynamic;

    public function new(scanner:Dynamic) {
        this.scanner = scanner;
    }

    public function findNextMatchSync(string:OnigString, startPosition:Int, options:Int):Null<IOnigMatch> {
        // vscode-oniguruma returns plain `{index, captureIndices: [{start, end, length}]}`
        // objects: on JavaScript they are used as they are.
        return scanner.findNextMatchSync((cast string : WasmOnigString).onigString, startPosition, options);
    }

    public function dispose():Void {
        scanner.dispose();
    }
}

private class WasmOnigString implements OnigString {
    public final onigString:Dynamic;

    public var content(get, never):String;

    inline function get_content():String {
        return onigString.content;
    }

    public function new(onigString:Dynamic) {
        this.onigString = onigString;
    }

    public function dispose():Void {
        onigString.dispose();
    }
}
#end
