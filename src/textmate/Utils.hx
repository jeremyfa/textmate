// Ported from vscode-textmate 9.2.0: src/utils.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import haxe.ds.StringMap;
import textmate.OnigLib.IOnigCaptureIndex;

class Utils {
    public static function mergeObjects<T>(target:OrderedMap<T>, sources:Array<OrderedMap<T>>):OrderedMap<T> {
        for (source in sources) {
            if (source == null) {
                continue;
            }
            for (key in source.keys()) {
                target.set(key, source.get(key));
            }
        }
        return target;
    }

    public static function basename(path:String):String {
        var idx = ~path.lastIndexOf('/');
        if (idx == 0) {
            idx = ~path.lastIndexOf('\\');
        }
        if (idx == 0) {
            return path;
        } else if (~idx == path.length - 1) {
            return basename(path.substring(0, path.length - 1));
        } else {
            return path.substr(~idx + 1);
        }
    }

    public static function strcmp(a:String, b:String):Int {
        // Same as the `<` and `>` operators of JavaScript: UTF-16 code unit order
        var len1 = a.length;
        var len2 = b.length;
        var len = len1 < len2 ? len1 : len2;
        for (i in 0...len) {
            var c1 = StringTools.fastCodeAt(a, i);
            var c2 = StringTools.fastCodeAt(b, i);
            if (c1 != c2) {
                return c1 < c2 ? -1 : 1;
            }
        }
        if (len1 < len2) {
            return -1;
        }
        if (len1 > len2) {
            return 1;
        }
        return 0;
    }

    public static function strArrCmp(a:Null<Array<String>>, b:Null<Array<String>>):Int {
        if (a == null && b == null) {
            return 0;
        }
        if (a == null) {
            return -1;
        }
        if (b == null) {
            return 1;
        }
        var len1 = a.length;
        var len2 = b.length;
        if (len1 == len2) {
            for (i in 0...len1) {
                var res = strcmp(a[i], b[i]);
                if (res != 0) {
                    return res;
                }
            }
            return 0;
        }
        return len1 - len2;
    }

    static function isHexDigit(c:Int):Bool {
        return (c >= '0'.code && c <= '9'.code) || (c >= 'a'.code && c <= 'f'.code) || (c >= 'A'.code && c <= 'F'.code);
    }

    public static function isValidHexColor(hex:String):Bool {
        // /^#[0-9a-f]{6}$/i, /^#[0-9a-f]{8}$/i, /^#[0-9a-f]{3}$/i, /^#[0-9a-f]{4}$/i
        var len = hex.length;
        if (len != 7 && len != 9 && len != 4 && len != 5) {
            return false;
        }
        if (StringTools.fastCodeAt(hex, 0) != '#'.code) {
            return false;
        }
        for (i in 1...len) {
            if (!isHexDigit(StringTools.fastCodeAt(hex, i))) {
                return false;
            }
        }
        return true;
    }

    /**
     * The characters of `\s` in JavaScript regular expressions.
     */
    public static function isJsWhitespace(c:Int):Bool {
        return switch c {
            case 0x09 | 0x0A | 0x0B | 0x0C | 0x0D | 0x20 | 0xA0 | 0x1680 | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 | 0xFEFF: true;
            default: c >= 0x2000 && c <= 0x200A;
        }
    }

    /**
     * `String.prototype.trim` of JavaScript.
     */
    public static function jsTrim(s:String):String {
        var start = 0;
        var end = s.length;
        while (start < end && isJsWhitespace(StringTools.fastCodeAt(s, start))) {
            start++;
        }
        while (end > start && isJsWhitespace(StringTools.fastCodeAt(s, end - 1))) {
            end--;
        }
        if (start == 0 && end == s.length) {
            return s;
        }
        return s.substring(start, end);
    }

    /**
     * Escapes regular expression characters in a given string
     * (`value.replace(/[\-\\\{\}\*\+\?\|\^\$\.\,\[\]\(\)\#\s]/g, '\\$&')`).
     */
    public static function escapeRegExpCharacters(value:String):String {
        var buf:Null<StringBuf> = null;
        var last = 0;
        var len = value.length;
        for (i in 0...len) {
            var c = StringTools.fastCodeAt(value, i);
            var special = switch c {
                case '-'.code | '\\'.code | '{'.code | '}'.code | '*'.code | '+'.code | '?'.code | '|'.code | '^'.code | '$'.code | '.'.code | ','.code
                    | '['.code | ']'.code | '('.code | ')'.code | '#'.code: true;
                default: isJsWhitespace(c);
            }
            if (special) {
                if (buf == null) {
                    buf = new StringBuf();
                }
                if (i > last) {
                    buf.addSub(value, last, i - last);
                }
                buf.addChar('\\'.code);
                buf.addSub(value, i, 1);
                last = i + 1;
            }
        }
        if (buf == null) {
            return value;
        }
        if (last < len) {
            buf.addSub(value, last, len - last);
        }
        return buf.toString();
    }

    public static function performanceNow():Float {
        return haxe.Timer.stamp() * 1000.0;
    }
}

class RegexSource {
    // CAPTURING_REGEX_SOURCE = /\$(\d+)|\${(\d+):\/(downcase|upcase)}/g

    public static function hasCaptures(regexSource:Null<String>):Bool {
        if (regexSource == null) {
            return false;
        }
        var pos = 0;
        var len = regexSource.length;
        while (pos < len) {
            if (StringTools.fastCodeAt(regexSource, pos) == '$'.code && matchCaptureAt(regexSource, pos) != null) {
                return true;
            }
            pos++;
        }
        return false;
    }

    /**
     * Matches `\$(\d+)|\${(\d+):\/(downcase|upcase)}` at `pos` (which holds a `$`).
     * Returns null, or [matchEnd, captureIndex, command] with command 0 (none),
     * 1 (downcase) or 2 (upcase).
     */
    static function matchCaptureAt(s:String, pos:Int):Null<Array<Int>> {
        var len = s.length;
        var p = pos + 1;
        if (p < len && isDigit(StringTools.fastCodeAt(s, p))) {
            var start = p;
            while (p < len && isDigit(StringTools.fastCodeAt(s, p))) {
                p++;
            }
            return [p, parseIntValue(s, start, p), 0];
        }
        if (p < len && StringTools.fastCodeAt(s, p) == '{'.code) {
            p++;
            var start = p;
            while (p < len && isDigit(StringTools.fastCodeAt(s, p))) {
                p++;
            }
            if (p == start) {
                return null;
            }
            var index = parseIntValue(s, start, p);
            if (p + 2 > len || StringTools.fastCodeAt(s, p) != ':'.code || StringTools.fastCodeAt(s, p + 1) != '/'.code) {
                return null;
            }
            p += 2;
            var command = 0;
            if (s.substr(p, 8) == 'downcase') {
                command = 1;
                p += 8;
            } else if (s.substr(p, 6) == 'upcase') {
                command = 2;
                p += 6;
            } else {
                return null;
            }
            if (p >= len || StringTools.fastCodeAt(s, p) != '}'.code) {
                return null;
            }
            return [p + 1, index, command];
        }
        return null;
    }

    static inline function isDigit(c:Int):Bool {
        return c >= '0'.code && c <= '9'.code;
    }

    static function parseIntValue(s:String, start:Int, end:Int):Int {
        // Like `parseInt`: big values only need to stay out of range of the captures
        var value = 0.0;
        for (i in start...end) {
            value = value * 10 + (StringTools.fastCodeAt(s, i) - '0'.code);
        }
        return value > 2147483647.0 ? 2147483647 : Std.int(value);
    }

    public static function replaceCaptures(regexSource:String, captureSource:String, captureIndices:Array<IOnigCaptureIndex>):String {
        var buf = new StringBuf();
        var len = regexSource.length;
        var last = 0;
        var pos = 0;
        while (pos < len) {
            if (StringTools.fastCodeAt(regexSource, pos) == '$'.code) {
                var m = matchCaptureAt(regexSource, pos);
                if (m != null) {
                    if (pos > last) {
                        buf.addSub(regexSource, last, pos - last);
                    }
                    var capture = m[1] < captureIndices.length ? captureIndices[m[1]] : null;
                    if (capture != null) {
                        var result = captureSource.substring(capture.start, capture.end);
                        // Remove leading dots that would make the selector invalid
                        while (result.length > 0 && StringTools.fastCodeAt(result, 0) == '.'.code) {
                            result = result.substring(1);
                        }
                        switch m[2] {
                            case 1:
                                buf.add(result.toLowerCase());
                            case 2:
                                buf.add(result.toUpperCase());
                            default:
                                buf.add(result);
                        }
                    } else {
                        buf.addSub(regexSource, pos, m[0] - pos);
                    }
                    pos = m[0];
                    last = pos;
                    continue;
                }
            }
            pos++;
        }
        if (last == 0) {
            return regexSource;
        }
        if (last < len) {
            buf.addSub(regexSource, last, len - last);
        }
        return buf.toString();
    }
}

class CachedFn<TValue> {
    final cache = new StringMap<TValue>();
    final fn:(String) -> TValue;

    public function new(fn:(String) -> TValue) {
        this.fn = fn;
    }

    public function get(key:String):TValue {
        var value = cache.get(key);
        if (value != null || cache.exists(key)) {
            return value;
        }
        value = fn(key);
        cache.set(key, value);
        return value;
    }
}
