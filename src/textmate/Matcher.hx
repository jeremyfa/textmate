// Ported from vscode-textmate 9.2.0: src/matcher.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

typedef Matcher<T> = T->Bool;

class MatcherWithPriority<T> {
    public final matcher:Matcher<T>;
    /** -1, 0 or 1 */
    public final priority:Int;

    public function new(matcher:Matcher<T>, priority:Int) {
        this.matcher = matcher;
        this.priority = priority;
    }
}

class Matchers {
    public static function createMatchers<T>(selector:String, matchesName:(names:Array<String>, matcherInput:T) -> Bool):Array<MatcherWithPriority<T>> {
        return new MatcherParser<T>(selector, matchesName).parse();
    }

    public static function isIdentifier(token:Null<String>):Bool {
        // !!token && !!token.match(/[\w\.:]+/)
        if (token == null || token.length == 0) {
            return false;
        }
        for (i in 0...token.length) {
            if (isIdentifierChar(StringTools.fastCodeAt(token, i))) {
                return true;
            }
        }
        return false;
    }

    static inline function isWordChar(c:Int):Bool {
        return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || (c >= '0'.code && c <= '9'.code) || c == '_'.code;
    }

    public static inline function isIdentifierChar(c:Int):Bool {
        return isWordChar(c) || c == '.'.code || c == ':'.code;
    }
}

private class MatcherParser<T> {
    final matchesName:(names:Array<String>, matcherInput:T) -> Bool;
    final tokenizer:SelectorTokenizer;
    var token:Null<String>;
    final selector:String;

    public function new(selector:String, matchesName:(names:Array<String>, matcherInput:T) -> Bool) {
        this.selector = selector;
        this.matchesName = matchesName;
        this.tokenizer = new SelectorTokenizer(selector);
    }

    public function parse():Array<MatcherWithPriority<T>> {
        var results:Array<MatcherWithPriority<T>> = [];
        token = tokenizer.next();
        while (token != null) {
            var priority = 0;
            if (token.length == 2 && token.charAt(1) == ':') {
                switch token.charAt(0) {
                    case 'R':
                        priority = 1;
                    case 'L':
                        priority = -1;
                    default:
                        // Unknown priority in scope selector
                }
                token = tokenizer.next();
            }
            var matcher = parseConjunction();
            results.push(new MatcherWithPriority(matcher, priority));
            if (token != ',') {
                break;
            }
            token = tokenizer.next();
        }
        return results;
    }

    function parseOperand():Null<Matcher<T>> {
        if (token == '-') {
            token = tokenizer.next();
            var expressionToNegate = parseOperand();
            return matcherInput -> expressionToNegate != null && !expressionToNegate(matcherInput);
        }
        if (token == '(') {
            token = tokenizer.next();
            var expressionInParents = parseInnerExpression();
            if (token == ')') {
                token = tokenizer.next();
            }
            return expressionInParents;
        }
        if (Matchers.isIdentifier(token)) {
            var identifiers:Array<String> = [];
            do {
                identifiers.push(token);
                token = tokenizer.next();
            } while (Matchers.isIdentifier(token));
            var matchesName = this.matchesName;
            return matcherInput -> matchesName(identifiers, matcherInput);
        }
        return null;
    }

    function parseConjunction():Matcher<T> {
        var matchers:Array<Matcher<T>> = [];
        var matcher = parseOperand();
        while (matcher != null) {
            matchers.push(matcher);
            matcher = parseOperand();
        }
        // and
        return matcherInput -> {
            for (m in matchers) {
                if (!m(matcherInput)) {
                    return false;
                }
            }
            return true;
        };
    }

    function parseInnerExpression():Matcher<T> {
        var matchers:Array<Matcher<T>> = [];
        var matcher = parseConjunction();
        while (matcher != null) {
            matchers.push(matcher);
            if (token == '|' || token == ',') {
                do {
                    token = tokenizer.next();
                } while (token == '|' || token == ','); // ignore subsequent commas
            } else {
                break;
            }
            matcher = parseConjunction();
        }
        // or
        return matcherInput -> {
            for (m in matchers) {
                if (m(matcherInput)) {
                    return true;
                }
            }
            return false;
        };
    }
}

/**
 * The tokens of `/([LR]:|[\w\.:][\w\.:\-]*|[\,\|\-\(\)])/g`.
 */
private class SelectorTokenizer {
    final input:String;
    var pos:Int;

    public function new(input:String) {
        this.input = input;
        this.pos = 0;
    }

    public function next():Null<String> {
        var len = input.length;
        while (pos < len) {
            var c = StringTools.fastCodeAt(input, pos);
            if ((c == 'L'.code || c == 'R'.code) && pos + 1 < len && StringTools.fastCodeAt(input, pos + 1) == ':'.code) {
                pos += 2;
                return input.substr(pos - 2, 2);
            }
            if (Matchers.isIdentifierChar(c)) {
                var start = pos;
                pos++;
                while (pos < len) {
                    var d = StringTools.fastCodeAt(input, pos);
                    if (Matchers.isIdentifierChar(d) || d == '-'.code) {
                        pos++;
                    } else {
                        break;
                    }
                }
                return input.substring(start, pos);
            }
            if (c == ','.code || c == '|'.code || c == '-'.code || c == '('.code || c == ')'.code) {
                pos++;
                return input.substr(pos - 1, 1);
            }
            pos++;
        }
        return null;
    }
}
