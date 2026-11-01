// Ported from vscode-textmate 9.2.0: src/plist.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.RawGrammar.ILocation;

/**
 * A very fast plist parser. Dictionaries are returned as
 * `OrderedMap<Dynamic>`, arrays as `Array<Dynamic>`, `<real>` and `<integer>`
 * as `Float`, `<date>` as `Date`.
 */
class Plist {
    public static function parseWithLocation(content:String, filename:Null<String>, locationKeyName:Null<String>):Dynamic {
        return _parse(content, filename, locationKeyName);
    }

    public static function parsePLIST(content:String):Dynamic {
        return _parse(content, null, null);
    }

    static function _parse(content:String, filename:Null<String>, locationKeyName:Null<String>):Dynamic {
        var len = content.length;

        var pos = 0;
        var line = 1;
        var char = 0;

        // Skip UTF8 BOM
        if (len > 0 && StringTools.fastCodeAt(content, 0) == ChCode.BOM) {
            pos = 1;
        }

        function advancePosBy(by:Int):Void {
            if (locationKeyName == null) {
                pos = pos + by;
            } else {
                while (by > 0) {
                    var chCode = pos < len ? StringTools.fastCodeAt(content, pos) : -1;
                    if (chCode == ChCode.LINE_FEED) {
                        pos++;
                        line++;
                        char = 0;
                    } else {
                        pos++;
                        char++;
                    }
                    by--;
                }
            }
        }
        function advancePosTo(to:Int):Void {
            if (locationKeyName == null) {
                pos = to;
            } else {
                advancePosBy(to - pos);
            }
        }

        function skipWhitespace():Void {
            while (pos < len) {
                var chCode = StringTools.fastCodeAt(content, pos);
                if (chCode != ChCode.SPACE && chCode != ChCode.TAB && chCode != ChCode.CARRIAGE_RETURN && chCode != ChCode.LINE_FEED) {
                    break;
                }
                advancePosBy(1);
            }
        }

        function advanceIfStartsWith(str:String):Bool {
            if (content.substr(pos, str.length) == str) {
                advancePosBy(str.length);
                return true;
            }
            return false;
        }

        function advanceUntil(str:String):Void {
            var nextOccurence = content.indexOf(str, pos);
            if (nextOccurence != -1) {
                advancePosTo(nextOccurence + str.length);
            } else {
                // EOF
                advancePosTo(len);
            }
        }

        function captureUntil(str:String):String {
            var nextOccurence = content.indexOf(str, pos);
            if (nextOccurence != -1) {
                var r = content.substring(pos, nextOccurence);
                advancePosTo(nextOccurence + str.length);
                return r;
            } else {
                // EOF
                var r = content.substr(pos);
                advancePosTo(len);
                return r;
            }
        }

        var state = State.ROOT_STATE;

        var cur:Dynamic = null;
        var stateStack:Array<State> = [];
        var objStack:Array<Dynamic> = [];
        var curKey:Null<String> = null;

        function fail(msg:String):Void {
            throw 'Near offset ' + pos + ': ' + msg + ' ~~~' + content.substr(pos, 50) + '~~~';
        }

        function pushState(newState:State, newCur:Dynamic):Void {
            stateStack.push(state);
            objStack.push(cur);
            state = newState;
            cur = newCur;
        }

        function popState():Void {
            if (stateStack.length == 0) {
                return fail('illegal state stack');
            }
            state = stateStack.pop();
            cur = objStack.pop();
        }

        function newDictWithLocation():OrderedMap<Dynamic> {
            var newDict = new OrderedMap<Dynamic>();
            if (locationKeyName != null) {
                newDict.set(locationKeyName, new ILocation(filename, line, char));
            }
            return newDict;
        }

        function enterDict():Void {
            if (state == State.DICT_STATE) {
                if (curKey == null) {
                    return fail('missing <key>');
                }
                var newDict = newDictWithLocation();
                (cur : OrderedMap<Dynamic>).set(curKey, newDict);
                curKey = null;
                pushState(State.DICT_STATE, newDict);
            } else if (state == State.ARR_STATE) {
                var newDict = newDictWithLocation();
                (cur : Array<Dynamic>).push(newDict);
                pushState(State.DICT_STATE, newDict);
            } else { // ROOT_STATE
                cur = newDictWithLocation();
                pushState(State.DICT_STATE, cur);
            }
        }
        function leaveDict():Void {
            if (state == State.DICT_STATE) {
                popState();
            } else if (state == State.ARR_STATE) {
                return fail('unexpected </dict>');
            } else { // ROOT_STATE
                return fail('unexpected </dict>');
            }
        }
        function enterArray():Void {
            if (state == State.DICT_STATE) {
                if (curKey == null) {
                    return fail('missing <key>');
                }
                var newArr = new Array<Dynamic>();
                (cur : OrderedMap<Dynamic>).set(curKey, newArr);
                curKey = null;
                pushState(State.ARR_STATE, newArr);
            } else if (state == State.ARR_STATE) {
                var newArr = new Array<Dynamic>();
                (cur : Array<Dynamic>).push(newArr);
                pushState(State.ARR_STATE, newArr);
            } else { // ROOT_STATE
                cur = new Array<Dynamic>();
                pushState(State.ARR_STATE, cur);
            }
        }
        function leaveArray():Void {
            if (state == State.DICT_STATE) {
                return fail('unexpected </array>');
            } else if (state == State.ARR_STATE) {
                popState();
            } else { // ROOT_STATE
                return fail('unexpected </array>');
            }
        }
        function acceptKey(val:String):Void {
            if (state == State.DICT_STATE) {
                if (curKey != null) {
                    return fail('too many <key>');
                }
                curKey = val;
            } else if (state == State.ARR_STATE) {
                return fail('unexpected <key>');
            } else { // ROOT_STATE
                return fail('unexpected <key>');
            }
        }
        function acceptValue(val:Dynamic):Void {
            if (state == State.DICT_STATE) {
                if (curKey == null) {
                    return fail('missing <key>');
                }
                (cur : OrderedMap<Dynamic>).set(curKey, val);
                curKey = null;
            } else if (state == State.ARR_STATE) {
                (cur : Array<Dynamic>).push(val);
            } else { // ROOT_STATE
                cur = val;
            }
        }
        function acceptReal(val:Float):Void {
            if (Math.isNaN(val)) {
                return fail('cannot parse float');
            }
            acceptValue(val);
        }
        function acceptInteger(val:Float):Void {
            if (Math.isNaN(val)) {
                return fail('cannot parse integer');
            }
            acceptValue(val);
        }

        function parseOpenTag():ParsedTag {
            var r = captureUntil('>');
            var isClosed = false;
            if (r.length > 0 && StringTools.fastCodeAt(r, r.length - 1) == ChCode.SLASH) {
                isClosed = true;
                r = r.substring(0, r.length - 1);
            }

            return new ParsedTag(Utils.jsTrim(r), isClosed);
        }

        function parseTagValue(tag:ParsedTag):String {
            if (tag.isClosed) {
                return '';
            }
            var val = captureUntil('</');
            advanceUntil('>');
            return escapeVal(val);
        }

        while (pos < len) {
            skipWhitespace();
            if (pos >= len) {
                break;
            }

            var chCode = StringTools.fastCodeAt(content, pos);
            advancePosBy(1);
            if (chCode != ChCode.LESS_THAN) {
                fail('expected <');
                return null;
            }

            if (pos >= len) {
                fail('unexpected end of input');
                return null;
            }

            var peekChCode = StringTools.fastCodeAt(content, pos);

            if (peekChCode == ChCode.QUESTION_MARK) {
                advancePosBy(1);
                advanceUntil('?>');
                continue;
            }

            if (peekChCode == ChCode.EXCLAMATION_MARK) {
                advancePosBy(1);

                if (advanceIfStartsWith('--')) {
                    advanceUntil('-->');
                    continue;
                }

                advanceUntil('>');
                continue;
            }

            if (peekChCode == ChCode.SLASH) {
                advancePosBy(1);
                skipWhitespace();

                if (advanceIfStartsWith('plist')) {
                    advanceUntil('>');
                    continue;
                }

                if (advanceIfStartsWith('dict')) {
                    advanceUntil('>');
                    leaveDict();
                    continue;
                }

                if (advanceIfStartsWith('array')) {
                    advanceUntil('>');
                    leaveArray();
                    continue;
                }

                fail('unexpected closed tag');
                return null;
            }

            var tag = parseOpenTag();

            switch tag.name {
                case 'dict':
                    enterDict();
                    if (tag.isClosed) {
                        leaveDict();
                    }
                    continue;

                case 'array':
                    enterArray();
                    if (tag.isClosed) {
                        leaveArray();
                    }
                    continue;

                case 'key':
                    acceptKey(parseTagValue(tag));
                    continue;

                case 'string':
                    acceptValue(parseTagValue(tag));
                    continue;

                case 'real':
                    acceptReal(parseFloatLikeJs(parseTagValue(tag)));
                    continue;

                case 'integer':
                    acceptInteger(parseIntLikeJs(parseTagValue(tag)));
                    continue;

                case 'date':
                    acceptValue(parseDate(parseTagValue(tag)));
                    continue;

                case 'data':
                    acceptValue(parseTagValue(tag));
                    continue;

                case 'true':
                    parseTagValue(tag);
                    acceptValue(true);
                    continue;

                case 'false':
                    parseTagValue(tag);
                    acceptValue(false);
                    continue;

                default:
            }

            if (StringTools.startsWith(tag.name, 'plist')) {
                continue;
            }

            fail('unexpected opened tag ' + tag.name);
            return null;
        }

        return cur;
    }

    static function parseDate(value:String):Dynamic {
        try {
            var s = value;
            if (StringTools.endsWith(s, 'Z')) {
                s = s.substring(0, s.length - 1);
            }
            s = StringTools.replace(s, 'T', ' ');
            return Date.fromString(s);
        } catch (e:Dynamic) {
            return value;
        }
    }

    static function parseIntLikeJs(value:String):Float {
        // parseInt(value, 10)
        var s = Utils.jsTrim(value);
        var i = 0;
        var negative = false;
        if (i < s.length && (StringTools.fastCodeAt(s, i) == '+'.code || StringTools.fastCodeAt(s, i) == '-'.code)) {
            negative = StringTools.fastCodeAt(s, i) == '-'.code;
            i++;
        }
        var start = i;
        var r = 0.0;
        while (i < s.length) {
            var c = StringTools.fastCodeAt(s, i);
            if (c < '0'.code || c > '9'.code) {
                break;
            }
            r = r * 10 + (c - '0'.code);
            i++;
        }
        if (i == start) {
            return Math.NaN;
        }
        return negative ? -r : r;
    }

    static function parseFloatLikeJs(value:String):Float {
        // parseFloat(value): the longest valid prefix
        var s = Utils.jsTrim(value);
        var i = 0;
        var len = s.length;
        if (i < len && (StringTools.fastCodeAt(s, i) == '+'.code || StringTools.fastCodeAt(s, i) == '-'.code)) {
            i++;
        }
        if (s.substr(i, 8) == 'Infinity') {
            return StringTools.fastCodeAt(s, 0) == '-'.code ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
        }
        var digits = 0;
        while (i < len && StringTools.fastCodeAt(s, i) >= '0'.code && StringTools.fastCodeAt(s, i) <= '9'.code) {
            i++;
            digits++;
        }
        if (i < len && StringTools.fastCodeAt(s, i) == '.'.code) {
            i++;
            while (i < len && StringTools.fastCodeAt(s, i) >= '0'.code && StringTools.fastCodeAt(s, i) <= '9'.code) {
                i++;
                digits++;
            }
        }
        if (digits == 0) {
            return Math.NaN;
        }
        if (i < len && (StringTools.fastCodeAt(s, i) == 'e'.code || StringTools.fastCodeAt(s, i) == 'E'.code)) {
            var j = i + 1;
            if (j < len && (StringTools.fastCodeAt(s, j) == '+'.code || StringTools.fastCodeAt(s, j) == '-'.code)) {
                j++;
            }
            var expStart = j;
            while (j < len && StringTools.fastCodeAt(s, j) >= '0'.code && StringTools.fastCodeAt(s, j) <= '9'.code) {
                j++;
            }
            if (j > expStart) {
                i = j;
            }
        }
        return Std.parseFloat(s.substring(0, i));
    }

    static function escapeVal(str:String):String {
        if (str.indexOf('&') == -1) {
            return str;
        }
        // The three replacements of vscode-textmate, applied one after the other:
        // &#([0-9]+); then &#x([0-9a-f]+); then the named entities.
        str = replaceNumericEntities(str, false);
        str = replaceNumericEntities(str, true);
        var buf = new StringBuf();
        var last = 0;
        var pos = str.indexOf('&');
        while (pos != -1) {
            var replacement:Null<String> = null;
            var length = 0;
            if (str.substr(pos, 5) == '&amp;') {
                replacement = '&';
                length = 5;
            } else if (str.substr(pos, 4) == '&lt;') {
                replacement = '<';
                length = 4;
            } else if (str.substr(pos, 4) == '&gt;') {
                replacement = '>';
                length = 4;
            } else if (str.substr(pos, 6) == '&quot;') {
                replacement = '"';
                length = 6;
            } else if (str.substr(pos, 6) == '&apos;') {
                replacement = '\'';
                length = 6;
            }
            if (replacement != null) {
                buf.addSub(str, last, pos - last);
                buf.add(replacement);
                last = pos + length;
                pos = str.indexOf('&', last);
            } else {
                pos = str.indexOf('&', pos + 1);
            }
        }
        if (last == 0) {
            return str;
        }
        buf.addSub(str, last, str.length - last);
        return buf.toString();
    }

    static function replaceNumericEntities(str:String, hex:Bool):String {
        var prefix = hex ? '&#x' : '&#';
        var pos = str.indexOf(prefix);
        if (pos == -1) {
            return str;
        }
        var buf = new StringBuf();
        var last = 0;
        while (pos != -1) {
            var start = pos + prefix.length;
            var end = start;
            var value = 0.0;
            while (end < str.length) {
                var c = StringTools.fastCodeAt(str, end);
                var digit = -1;
                if (c >= '0'.code && c <= '9'.code) {
                    digit = c - '0'.code;
                } else if (hex && c >= 'a'.code && c <= 'f'.code) {
                    digit = c - 'a'.code + 10;
                }
                if (digit == -1) {
                    break;
                }
                value = value * (hex ? 16 : 10) + digit;
                end++;
            }
            if (end > start && end < str.length && StringTools.fastCodeAt(str, end) == ';'.code) {
                buf.addSub(str, last, pos - last);
                buf.add(codePointToString(value));
                last = end + 1;
                pos = str.indexOf(prefix, last);
            } else {
                pos = str.indexOf(prefix, pos + 1);
            }
        }
        if (last < str.length) {
            buf.addSub(str, last, str.length - last);
        }
        return buf.toString();
    }

    static function codePointToString(value:Float):String {
        if (value > 0x10FFFF) {
            // String.fromCodePoint throws a RangeError
            throw 'Invalid code point ' + value;
        }
        var buf = new StringBuf();
        buf.addChar(Std.int(value));
        return buf.toString();
    }
}

private class ParsedTag {
    public final name:String;
    public final isClosed:Bool;

    public function new(name:String, isClosed:Bool) {
        this.name = name;
        this.isClosed = isClosed;
    }
}

private class ChCode {
    public static inline var BOM = 65279;

    public static inline var SPACE = 32;
    public static inline var TAB = 9;
    public static inline var CARRIAGE_RETURN = 13;
    public static inline var LINE_FEED = 10;

    public static inline var SLASH = 47;

    public static inline var LESS_THAN = 60;
    public static inline var QUESTION_MARK = 63;
    public static inline var EXCLAMATION_MARK = 33;
}

private enum abstract State(Int) {
    var ROOT_STATE = 0;
    var DICT_STATE = 1;
    var ARR_STATE = 2;
}
