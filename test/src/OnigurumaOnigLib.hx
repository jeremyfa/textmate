// Test helper of the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// It plays the role of vscode-textmate's src/tests/onigLibs.ts for the pure
// Haxe `oniguruma` library. The `textmate` library itself does not depend on
// `oniguruma`: an application passes this kind of adapter as `onigLib`.

import textmate.OnigLib;

class OnigurumaOnigLib implements IOnigLib {
    public function new() {}

    public function createOnigScanner(sources:Array<String>):OnigScanner {
        return new OnigurumaScanner(new oniguruma.OnigScanner(sources));
    }

    public function createOnigString(str:String):OnigString {
        return new OnigurumaString(new oniguruma.OnigString(str));
    }
}

private class OnigurumaScanner implements OnigScanner {
    final scanner:oniguruma.OnigScanner;

    public function new(scanner:oniguruma.OnigScanner) {
        this.scanner = scanner;
    }

    public function findNextMatchSync(string:OnigString, startPosition:Int, options:Int):Null<IOnigMatch> {
        var s = (cast string : OnigurumaString).onigString;
        var m = if (options == 0) {
            scanner.findNextMatchSync(s, startPosition);
        } else {
            var opts:Array<oniguruma.FindOption> = [];
            if (options & FindOption.NotBeginString != 0) opts.push(oniguruma.FindOption.NotBeginString);
            if (options & FindOption.NotEndString != 0) opts.push(oniguruma.FindOption.NotEndString);
            if (options & FindOption.NotBeginPosition != 0) opts.push(oniguruma.FindOption.NotBeginPosition);
            if (options & FindOption.DebugCall != 0) opts.push(oniguruma.FindOption.DebugCall);
            scanner.findNextMatchSync(s, startPosition, opts);
        }
        if (m == null) {
            return null;
        }
        #if js
        // Same fields on plain JavaScript objects
        return cast m;
        #else
        var src = m.captureIndices;
        var captures = new Array<IOnigCaptureIndex>();
        captures.resize(src.length);
        for (i in 0...src.length) {
            var c = src[i];
            captures[i] = new IOnigCaptureIndex(c.start, c.end, c.length);
        }
        return new IOnigMatch(m.index, captures);
        #end
    }

    public function dispose():Void {
        scanner.dispose();
    }
}

private class OnigurumaString implements OnigString {
    public final onigString:oniguruma.OnigString;

    public var content(get, never):String;

    inline function get_content():String {
        return onigString.content;
    }

    public function new(onigString:oniguruma.OnigString) {
        this.onigString = onigString;
    }

    public function dispose():Void {
        onigString.dispose();
    }
}
