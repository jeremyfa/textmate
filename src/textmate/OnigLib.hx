// Ported from vscode-textmate 9.2.0: src/onigLib.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

/**
 * The regular expression engine used by the tokenizer. It is given to the
 * `Registry` through `RegistryOptions.onigLib`. vscode-textmate does not depend
 * on a concrete engine: any object creating Oniguruma compatible scanners and
 * strings works (the pure Haxe `oniguruma` library, vscode-oniguruma's onig.wasm
 * on the JavaScript target through `textmate.onig.WasmOnigLib`, ...).
 */
interface IOnigLib {
    function createOnigScanner(sources:Array<String>):OnigScanner;
    function createOnigString(str:String):OnigString;
}

/**
 * A capture range, in UTF-16 code units.
 */
class IOnigCaptureIndex {
    public var start:Int;
    public var end:Int;
    public var length:Int;

    public inline function new(start:Int, end:Int, length:Int) {
        this.start = start;
        this.end = end;
        this.length = length;
    }
}

/**
 * The result of `OnigScanner.findNextMatchSync`.
 */
class IOnigMatch {
    public var index:Int;
    public var captureIndices:Array<IOnigCaptureIndex>;

    public inline function new(index:Int, captureIndices:Array<IOnigCaptureIndex>) {
        this.index = index;
        this.captureIndices = captureIndices;
    }
}

enum abstract FindOption(Int) from Int to Int {
    var None = 0;
    /**
     * equivalent of ONIG_OPTION_NOT_BEGIN_STRING: (str) isn't considered as begin of string (* fail \A)
     */
    var NotBeginString = 1;
    /**
     * equivalent of ONIG_OPTION_NOT_END_STRING: (end) isn't considered as end of string (* fail \z, \Z)
     */
    var NotEndString = 2;
    /**
     * equivalent of ONIG_OPTION_NOT_BEGIN_POSITION: (start) isn't considered as start position of search (* fail \G)
     */
    var NotBeginPosition = 4;
    /**
     * used for debugging purposes.
     */
    var DebugCall = 8;
}

interface OnigScanner {
    function findNextMatchSync(string:OnigString, startPosition:Int, options:Int):Null<IOnigMatch>;
    function dispose():Void;
}

interface OnigString {
    var content(get, never):String;
    function dispose():Void;
}

class OnigLib {
    public static function disposeOnigString(str:OnigString):Void {
        str.dispose();
    }
}
