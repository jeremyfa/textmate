// Minimal test registry and assertions.

class T {
    public static var passed = 0;
    public static var failed = 0;
    public static var failures:Array<String> = [];
    public static var filter:Null<String> = null;
    public static var verbose = false;
    static var currentSuite = '';
    static var suitePassed = 0;
    static var suiteFailed = 0;
    public static var suiteResults:Array<{name:String, passed:Int, failed:Int, ms:Float}> = [];
    static var suiteStart = 0.0;

    public static function suite(name:String):Void {
        endSuite();
        currentSuite = name;
        suitePassed = 0;
        suiteFailed = 0;
        suiteStart = haxe.Timer.stamp();
    }

    public static function endSuite():Void {
        if (currentSuite != '') {
            suiteResults.push({name: currentSuite, passed: suitePassed, failed: suiteFailed, ms: (haxe.Timer.stamp() - suiteStart) * 1000});
            currentSuite = '';
        }
    }

    public static function enabled(name:String):Bool {
        return filter == null || (currentSuite + ' ' + name).indexOf(filter) != -1;
    }

    public static function test(name:String, fn:Void->Void):Void {
        if (!enabled(name)) {
            return;
        }
        try {
            fn();
            passed++;
            suitePassed++;
        } catch (e:Dynamic) {
            failed++;
            suiteFailed++;
            var msg = '[$currentSuite] $name: ' + Std.string(e);
            failures.push(msg);
            if (verbose) {
                println('FAIL ' + msg);
            }
        }
    }

    public static function println(s:String):Void {
        #if js
        js.Syntax.code("console.log({0})", s);
        #else
        Sys.println(s);
        #end
    }

    public static function fail(msg:String):Void {
        throw msg;
    }

    public static function isTrue(v:Bool, ?msg:String):Void {
        if (!v) {
            throw msg != null ? msg : 'expected true';
        }
    }

    public static function equals<V>(actual:V, expected:V, ?msg:String):Void {
        if (actual != expected) {
            throw (msg != null ? msg + ': ' : '') + 'expected ' + Std.string(expected) + ' got ' + Std.string(actual);
        }
    }

    /** Deep equality of JSON like values (arrays, anonymous objects, OrderedMap, scalars). */
    public static function deepEquals(a:Dynamic, b:Dynamic):Bool {
        if (a == b) {
            return true;
        }
        if (a == null || b == null) {
            return false;
        }
        if (Std.isOfType(a, Array) && Std.isOfType(b, Array)) {
            var aa:Array<Dynamic> = a;
            var bb:Array<Dynamic> = b;
            if (aa.length != bb.length) {
                return false;
            }
            for (i in 0...aa.length) {
                if (!deepEquals(aa[i], bb[i])) {
                    return false;
                }
            }
            return true;
        }
        if ((Std.isOfType(a, Float) || Std.isOfType(a, Int)) && (Std.isOfType(b, Float) || Std.isOfType(b, Int))) {
            return (a : Float) == (b : Float);
        }
        if (Std.isOfType(a, String) || Std.isOfType(b, String) || Std.isOfType(a, Bool) || Std.isOfType(b, Bool)) {
            return false;
        }
        var ka = textmate.RawGrammar.RawValue.fields(a);
        var kb = textmate.RawGrammar.RawValue.fields(b);
        if (ka.length != kb.length) {
            return false;
        }
        for (k in ka) {
            if (!textmate.RawGrammar.RawValue.hasField(b, k)) {
                return false;
            }
            if (!deepEquals(textmate.RawGrammar.RawValue.field(a, k), textmate.RawGrammar.RawValue.field(b, k))) {
                return false;
            }
        }
        return true;
    }

    public static function same(actual:Dynamic, expected:Dynamic, ?msg:String):Void {
        if (!deepEquals(actual, expected)) {
            throw (msg != null ? msg + ': ' : '') + 'expected ' + haxe.Json.stringify(toPlain(expected)) + ' got ' + haxe.Json.stringify(toPlain(actual));
        }
    }

    public static function toPlain(v:Dynamic):Dynamic {
        if (v == null) {
            return null;
        }
        if (Std.isOfType(v, textmate.OrderedMap)) {
            var m:textmate.OrderedMap<Dynamic> = v;
            var o = {};
            for (k in m.keys()) {
                Reflect.setField(o, k, toPlain(m.get(k)));
            }
            return o;
        }
        if (Std.isOfType(v, Array)) {
            return [for (x in (v : Array<Dynamic>)) toPlain(x)];
        }
        return v;
    }
}
