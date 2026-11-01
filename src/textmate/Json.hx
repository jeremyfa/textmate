// Ported from vscode-textmate 9.2.0: src/json.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.RawGrammar.ILocation;

/**
 * A JSON parser that can record the location of every object
 * (`$vscodeTextmateLocation`). Objects are returned as `OrderedMap<Dynamic>`
 * (JavaScript key order), arrays as `Array<Dynamic>`, numbers as `Float`.
 */
class Json {
    static function doFail(streamState:JSONStreamState, msg:String):Void {
        throw 'Near offset ' + streamState.pos + ': ' + msg + ' ~~~' + streamState.source.substr(streamState.pos, 50) + '~~~';
    }

    public static function parseJSON(source:String, filename:Null<String>, withMetadata:Bool):Dynamic {
        var streamState = new JSONStreamState(source);
        var token = new JSONToken();
        var state = JSONState.ROOT_STATE;
        var cur:Dynamic = null;
        var stateStack:Array<JSONState> = [];
        var objStack:Array<Dynamic> = [];

        function pushState():Void {
            stateStack.push(state);
            objStack.push(cur);
        }

        function popState():Void {
            state = stateStack.pop();
            cur = objStack.pop();
        }

        function fail(msg:String):Void {
            doFail(streamState, msg);
        }

        while (nextJSONToken(streamState, token)) {
            if (state == JSONState.ROOT_STATE) {
                if (cur != null) {
                    fail('too many constructs in root');
                }

                if (token.type == JSONTokenType.LEFT_CURLY_BRACKET) {
                    var dict = new OrderedMap<Dynamic>();
                    if (withMetadata) {
                        dict.set("$vscodeTextmateLocation", token.toLocation(filename));
                    }
                    cur = dict;
                    pushState();
                    state = JSONState.DICT_STATE;
                    continue;
                }

                if (token.type == JSONTokenType.LEFT_SQUARE_BRACKET) {
                    cur = new Array<Dynamic>();
                    pushState();
                    state = JSONState.ARR_STATE;
                    continue;
                }

                fail('unexpected token in root');
            }

            if (state == JSONState.DICT_STATE_COMMA) {
                if (token.type == JSONTokenType.RIGHT_CURLY_BRACKET) {
                    popState();
                    continue;
                }

                if (token.type == JSONTokenType.COMMA) {
                    state = JSONState.DICT_STATE_NO_CLOSE;
                    continue;
                }

                fail('expected , or }');
            }

            if (state == JSONState.DICT_STATE || state == JSONState.DICT_STATE_NO_CLOSE) {
                if (state == JSONState.DICT_STATE && token.type == JSONTokenType.RIGHT_CURLY_BRACKET) {
                    popState();
                    continue;
                }

                if (token.type == JSONTokenType.STRING) {
                    var keyValue = token.value;
                    var dict:OrderedMap<Dynamic> = cur;

                    if (!nextJSONToken(streamState, token) || token.type != JSONTokenType.COLON) {
                        fail('expected colon');
                    }
                    if (!nextJSONToken(streamState, token)) {
                        fail('expected value');
                    }

                    state = JSONState.DICT_STATE_COMMA;

                    if (token.type == JSONTokenType.STRING) {
                        dict.set(keyValue, token.value);
                        continue;
                    }
                    if (token.type == JSONTokenType.NULL) {
                        dict.set(keyValue, null);
                        continue;
                    }
                    if (token.type == JSONTokenType.TRUE) {
                        dict.set(keyValue, true);
                        continue;
                    }
                    if (token.type == JSONTokenType.FALSE) {
                        dict.set(keyValue, false);
                        continue;
                    }
                    if (token.type == JSONTokenType.NUMBER) {
                        dict.set(keyValue, Std.parseFloat(token.value));
                        continue;
                    }
                    if (token.type == JSONTokenType.LEFT_SQUARE_BRACKET) {
                        var newArr = new Array<Dynamic>();
                        dict.set(keyValue, newArr);
                        pushState();
                        state = JSONState.ARR_STATE;
                        cur = newArr;
                        continue;
                    }
                    if (token.type == JSONTokenType.LEFT_CURLY_BRACKET) {
                        var newDict = new OrderedMap<Dynamic>();
                        if (withMetadata) {
                            newDict.set("$vscodeTextmateLocation", token.toLocation(filename));
                        }
                        dict.set(keyValue, newDict);
                        pushState();
                        state = JSONState.DICT_STATE;
                        cur = newDict;
                        continue;
                    }
                }

                fail('unexpected token in dict');
            }

            if (state == JSONState.ARR_STATE_COMMA) {
                if (token.type == JSONTokenType.RIGHT_SQUARE_BRACKET) {
                    popState();
                    continue;
                }

                if (token.type == JSONTokenType.COMMA) {
                    state = JSONState.ARR_STATE_NO_CLOSE;
                    continue;
                }

                fail('expected , or ]');
            }

            if (state == JSONState.ARR_STATE || state == JSONState.ARR_STATE_NO_CLOSE) {
                if (state == JSONState.ARR_STATE && token.type == JSONTokenType.RIGHT_SQUARE_BRACKET) {
                    popState();
                    continue;
                }

                state = JSONState.ARR_STATE_COMMA;
                var arr:Array<Dynamic> = cur;

                if (token.type == JSONTokenType.STRING) {
                    arr.push(token.value);
                    continue;
                }
                if (token.type == JSONTokenType.NULL) {
                    arr.push(null);
                    continue;
                }
                if (token.type == JSONTokenType.TRUE) {
                    arr.push(true);
                    continue;
                }
                if (token.type == JSONTokenType.FALSE) {
                    arr.push(false);
                    continue;
                }
                if (token.type == JSONTokenType.NUMBER) {
                    arr.push(Std.parseFloat(token.value));
                    continue;
                }

                if (token.type == JSONTokenType.LEFT_SQUARE_BRACKET) {
                    var newArr = new Array<Dynamic>();
                    arr.push(newArr);
                    pushState();
                    state = JSONState.ARR_STATE;
                    cur = newArr;
                    continue;
                }
                if (token.type == JSONTokenType.LEFT_CURLY_BRACKET) {
                    var newDict = new OrderedMap<Dynamic>();
                    if (withMetadata) {
                        newDict.set("$vscodeTextmateLocation", token.toLocation(filename));
                    }
                    arr.push(newDict);
                    pushState();
                    state = JSONState.DICT_STATE;
                    cur = newDict;
                    continue;
                }

                fail('unexpected token in array');
            }

            fail('unknown state');
        }

        if (objStack.length != 0) {
            fail('unclosed constructs');
        }

        return cur;
    }

    static inline function isHex(c:Int):Bool {
        return (c >= '0'.code && c <= '9'.code) || (c >= 'a'.code && c <= 'f'.code) || (c >= 'A'.code && c <= 'F'.code);
    }

    static function hexValue(s:String, pos:Int):Int {
        var v = 0;
        for (i in pos...pos + 4) {
            var c = StringTools.fastCodeAt(s, i);
            v = v * 16 + (c <= '9'.code ? c - '0'.code : (c <= 'F'.code ? c - 'A'.code + 10 : c - 'a'.code + 10));
        }
        return v;
    }

    /**
     * Decodes the escapes of a JSON string body.
     *
     * vscode-textmate replaces the `\uXXXX` escapes first and the other escapes
     * after, which fails on an escaped backslash followed by `u` (`"\\u0041"`).
     * It only uses this parser in debug mode: `JSON.parse` reads the grammars
     * otherwise. The escapes are decoded here in one pass, like `JSON.parse`.
     */
    static function unescape(state:JSONStreamState, source:String, start:Int, end:Int):String {
        var hasEscape = false;
        for (i in start...end) {
            if (StringTools.fastCodeAt(source, i) == '\\'.code) {
                hasEscape = true;
                break;
            }
        }
        if (!hasEscape) {
            return source.substring(start, end);
        }
        var buf = new StringBuf();
        var last = start;
        var pos = start;
        while (pos < end) {
            var c = StringTools.fastCodeAt(source, pos);
            if (c != '\\'.code) {
                pos++;
                continue;
            }
            if (pos > last) {
                buf.addSub(source, last, pos - last);
            }
            if (pos + 1 >= end) {
                doFail(state, 'invalid escape sequence');
            }
            var e = StringTools.fastCodeAt(source, pos + 1);
            switch e {
                case '"'.code:
                    buf.addChar('"'.code);
                    pos += 2;
                case '\\'.code:
                    buf.addChar('\\'.code);
                    pos += 2;
                case '/'.code:
                    buf.addChar('/'.code);
                    pos += 2;
                case 'b'.code:
                    buf.addChar(8);
                    pos += 2;
                case 'f'.code:
                    buf.addChar(12);
                    pos += 2;
                case 'n'.code:
                    buf.addChar('\n'.code);
                    pos += 2;
                case 'r'.code:
                    buf.addChar('\r'.code);
                    pos += 2;
                case 't'.code:
                    buf.addChar('\t'.code);
                    pos += 2;
                case 'u'.code:
                    if (pos + 6 > end || !isHex(StringTools.fastCodeAt(source, pos + 2)) || !isHex(StringTools.fastCodeAt(source, pos + 3))
                        || !isHex(StringTools.fastCodeAt(source, pos + 4)) || !isHex(StringTools.fastCodeAt(source, pos + 5))) {
                        doFail(state, 'invalid escape sequence');
                    }
                    var code = hexValue(source, pos + 2);
                    pos += 6;
                    if (code >= 0xD800 && code <= 0xDBFF && pos + 6 <= end && StringTools.fastCodeAt(source, pos) == '\\'.code
                        && StringTools.fastCodeAt(source, pos + 1) == 'u'.code && isHex(StringTools.fastCodeAt(source, pos + 2))
                        && isHex(StringTools.fastCodeAt(source, pos + 3)) && isHex(StringTools.fastCodeAt(source, pos + 4))
                        && isHex(StringTools.fastCodeAt(source, pos + 5))) {
                        var low = hexValue(source, pos + 2);
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                            pos += 6;
                        }
                    }
                    buf.addChar(code);
                default:
                    doFail(state, 'invalid escape sequence');
            }
            last = pos;
        }
        if (last < end) {
            buf.addSub(source, last, end - last);
        }
        return buf.toString();
    }

    /**
     * precondition: the string is known to be valid JSON (https://www.ietf.org/rfc/rfc4627.txt)
     */
    static function nextJSONToken(_state:JSONStreamState, _out:JSONToken):Bool {
        _out.value = null;
        _out.type = JSONTokenType.UNKNOWN;
        _out.offset = -1;
        _out.len = -1;
        _out.line = -1;
        _out.char = -1;

        var source = _state.source;
        var pos = _state.pos;
        var len = _state.len;
        var line = _state.line;
        var char = _state.char;

        //------------------------ skip whitespace
        var chCode:Int;
        do {
            if (pos >= len) {
                return false; /*EOS*/
            }

            chCode = StringTools.fastCodeAt(source, pos);
            if (chCode == ChCode.SPACE || chCode == ChCode.HORIZONTAL_TAB || chCode == ChCode.CARRIAGE_RETURN) {
                // regular whitespace
                pos++;
                char++;
                continue;
            }

            if (chCode == ChCode.LINE_FEED) {
                // newline
                pos++;
                line++;
                char = 0;
                continue;
            }

            // not whitespace
            break;
        } while (true);

        _out.offset = pos;
        _out.line = line;
        _out.char = char;

        inline function codeAt(p:Int):Int {
            return p < len ? StringTools.fastCodeAt(source, p) : -1;
        }

        if (chCode == ChCode.QUOTATION_MARK) {
            //------------------------ strings
            _out.type = JSONTokenType.STRING;

            pos++;
            char++;

            do {
                if (pos >= len) {
                    return false; /*EOS*/
                }

                chCode = StringTools.fastCodeAt(source, pos);
                pos++;
                char++;

                if (chCode == ChCode.BACKSLASH) {
                    // skip next char
                    pos++;
                    char++;
                    continue;
                }

                if (chCode == ChCode.QUOTATION_MARK) {
                    // end of the string
                    break;
                }
            } while (true);

            _out.value = unescape(_state, source, _out.offset + 1, pos - 1);
        } else if (chCode == ChCode.LEFT_SQUARE_BRACKET) {
            _out.type = JSONTokenType.LEFT_SQUARE_BRACKET;
            pos++;
            char++;
        } else if (chCode == ChCode.LEFT_CURLY_BRACKET) {
            _out.type = JSONTokenType.LEFT_CURLY_BRACKET;
            pos++;
            char++;
        } else if (chCode == ChCode.RIGHT_SQUARE_BRACKET) {
            _out.type = JSONTokenType.RIGHT_SQUARE_BRACKET;
            pos++;
            char++;
        } else if (chCode == ChCode.RIGHT_CURLY_BRACKET) {
            _out.type = JSONTokenType.RIGHT_CURLY_BRACKET;
            pos++;
            char++;
        } else if (chCode == ChCode.COLON) {
            _out.type = JSONTokenType.COLON;
            pos++;
            char++;
        } else if (chCode == ChCode.COMMA) {
            _out.type = JSONTokenType.COMMA;
            pos++;
            char++;
        } else if (chCode == ChCode.n) {
            //------------------------ null

            _out.type = JSONTokenType.NULL;
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.u) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.l) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.l) {
                return false; /* INVALID */
            }
            pos++;
            char++;
        } else if (chCode == ChCode.t) {
            //------------------------ true

            _out.type = JSONTokenType.TRUE;
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.r) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.u) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.e) {
                return false; /* INVALID */
            }
            pos++;
            char++;
        } else if (chCode == ChCode.f) {
            //------------------------ false

            _out.type = JSONTokenType.FALSE;
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.a) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.l) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.s) {
                return false; /* INVALID */
            }
            pos++;
            char++;
            chCode = codeAt(pos);
            if (chCode != ChCode.e) {
                return false; /* INVALID */
            }
            pos++;
            char++;
        } else {
            //------------------------ numbers

            _out.type = JSONTokenType.NUMBER;
            do {
                if (pos >= len) {
                    return false; /*EOS*/
                }

                chCode = StringTools.fastCodeAt(source, pos);
                if (chCode == ChCode.DOT
                    || (chCode >= ChCode.D0 && chCode <= ChCode.D9)
                    || (chCode == ChCode.e || chCode == ChCode.E)
                    || (chCode == ChCode.MINUS || chCode == ChCode.PLUS)) {
                    // looks like a piece of a number
                    pos++;
                    char++;
                    continue;
                }

                // pos--; char--;
                break;
            } while (true);
        }

        _out.len = pos - _out.offset;
        if (_out.value == null) {
            _out.value = source.substr(_out.offset, _out.len);
        }

        _state.pos = pos;
        _state.line = line;
        _state.char = char;

        return true;
    }
}

private class JSONStreamState {
    public var source:String;

    public var pos:Int;
    public var len:Int;

    public var line:Int;
    public var char:Int;

    public function new(source:String) {
        this.source = source;
        this.pos = 0;
        this.len = source.length;
        this.line = 1;
        this.char = 0;
    }
}

private enum abstract JSONTokenType(Int) {
    var UNKNOWN = 0;
    var STRING = 1;
    var LEFT_SQUARE_BRACKET = 2; // [
    var LEFT_CURLY_BRACKET = 3; // {
    var RIGHT_SQUARE_BRACKET = 4; // ]
    var RIGHT_CURLY_BRACKET = 5; // }
    var COLON = 6; // :
    var COMMA = 7; // ,
    var NULL = 8;
    var TRUE = 9;
    var FALSE = 10;
    var NUMBER = 11;
}

private enum abstract JSONState(Int) {
    var ROOT_STATE = 0;
    var DICT_STATE = 1;
    var DICT_STATE_COMMA = 2;
    var DICT_STATE_NO_CLOSE = 3;
    var ARR_STATE = 4;
    var ARR_STATE_COMMA = 5;
    var ARR_STATE_NO_CLOSE = 6;
}

private class ChCode {
    public static inline var SPACE = 0x20;
    public static inline var HORIZONTAL_TAB = 0x09;
    public static inline var CARRIAGE_RETURN = 0x0D;
    public static inline var LINE_FEED = 0x0A;
    public static inline var QUOTATION_MARK = 0x22;
    public static inline var BACKSLASH = 0x5C;

    public static inline var LEFT_SQUARE_BRACKET = 0x5B;
    public static inline var LEFT_CURLY_BRACKET = 0x7B;
    public static inline var RIGHT_SQUARE_BRACKET = 0x5D;
    public static inline var RIGHT_CURLY_BRACKET = 0x7D;
    public static inline var COLON = 0x3A;
    public static inline var COMMA = 0x2C;
    public static inline var DOT = 0x2E;

    public static inline var D0 = 0x30;
    public static inline var D9 = 0x39;

    public static inline var MINUS = 0x2D;
    public static inline var PLUS = 0x2B;

    public static inline var E = 0x45;

    public static inline var a = 0x61;
    public static inline var e = 0x65;
    public static inline var f = 0x66;
    public static inline var l = 0x6C;
    public static inline var n = 0x6E;
    public static inline var r = 0x72;
    public static inline var s = 0x73;
    public static inline var t = 0x74;
    public static inline var u = 0x75;
}

private class JSONToken {
    public var value:Null<String>;
    public var type:JSONTokenType;

    public var offset:Int;
    public var len:Int;

    /* 1 based line number */
    public var line:Int;
    public var char:Int;

    public function new() {
        this.value = null;
        this.type = JSONTokenType.UNKNOWN;
        this.offset = -1;
        this.len = -1;
        this.line = -1;
        this.char = -1;
    }

    public function toLocation(filename:Null<String>):ILocation {
        return new ILocation(filename, line, char);
    }
}
