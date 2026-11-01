// Ported from vscode-textmate 9.2.0: src/tests/json.test.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import textmate.Json;

class JsonTests {
    static function isValid(json:String):Void {
        // haxe.Json.parse plays the role of JSON.parse
        var expected = haxe.Json.parse(json);
        var actual = Json.parseJSON(json, null, false);
        T.same(actual, expected, json);
    }

    static function isInvalid(json:String):Void {
        var hadErr = false;
        try {
            Json.parseJSON(json, null, false);
        } catch (err:Dynamic) {
            hadErr = true;
        }
        T.equals(hadErr, true, 'expected invalid: ' + json);
    }

    public static function run():Void {
        T.suite('json');

        T.test('JSON Invalid body', () -> {
            isInvalid('{}[]');
            isInvalid('*');
        });

        T.test('JSON Trailing Whitespace', () -> {
            isValid('{}\n\n');
        });

        T.test('JSON Objects', () -> {
            isValid('{}');
            isValid('{"key": "value"}');
            isValid('{"key1": true, "key2": 3, "key3": [null], "key4": { "nested": {}}}');
            isValid('{"constructor": true }');

            isInvalid('{');
            isInvalid('{3:3}');
            isInvalid('{\'key\': 3}');
            isInvalid('{"key" 3}');
            isInvalid('{"key":3 "key2": 4}');
            isInvalid('{"key":42, }');
            isInvalid('{"key:42');
        });

        T.test('JSON Arrays', () -> {
            isValid('[]');
            isValid('[1, 2]');
            isValid('[1, "string", false, {}, [null]]');

            isInvalid('[');
            isInvalid('[,]');
            isInvalid('[1 2]');
            isInvalid('[true false]');
            isInvalid('[1, ]');
            isInvalid('[[]');
            isInvalid('["something"');
            isInvalid('[magic]');
        });

        T.test('JSON Strings', () -> {
            isValid('["string"]');
            isValid('["\\"\\\\\\/\\b\\f\\n\\r\\t\\u1234\\u12AB"]');
            isValid('["\\\\"]');

            isInvalid('["');
            isInvalid('["]');
            isInvalid('["\\z"]');
            isInvalid('["\\u"]');
            isInvalid('["\\u123"]');
            isInvalid('["\\u123Z"]');
            isInvalid('[\'string\']');
        });

        T.test('Numbers', () -> {
            isValid('[0, -1, 186.1, 0.123, -1.583e+4, 1.583E-4, 5e8]');
        });

        T.test('JSON misc', () -> {
            isValid('{}');
            isValid('[null]');
            isValid('{"a":true}');
            isValid('{\n\t"key" : {\n\t"key2": 42\n\t}\n}');
            isValid('{"key":[{"key2":42}]}');
            isValid('{\n\t\n}');
            isValid('{\n"first":true\n\n}');
            isValid('{\n"key":32,\n\n"key2":45}');
            isValid('{"a": 1,\n\n"d": 2}');
            isValid('{"a": 1, "a": 2}');
            isValid('{"a": { "a": 2, "a": 3}}');
            isValid('[{ "a": 2, "a": 3}]');
            isValid('{"key1":"first string", "key2":["second string"]}');

            isInvalid('{\n"key":32,\nerror\n}');
        });

        // Not in upstream: the cases where this port reads escapes like JSON.parse
        T.test('JSON escapes like JSON.parse (port)', () -> {
            isValid('["\\\\u0041"]');
            isValid('["\\ud83d\\ude00 \\u00e9"]');
        });

        T.test('JSON key order like JavaScript objects (port)', () -> {
            var v:textmate.OrderedMap<Dynamic> = Json.parseJSON('{"b": 1, "2": 2, "a": 3, "1": 4, "01": 5}', null, false);
            T.same(v.keys(), ['1', '2', 'b', 'a', '01']);
        });

        T.test('JSON locations (port)', () -> {
            var v:textmate.OrderedMap<Dynamic> = Json.parseJSON('{\n  "a": {"b": 1}\n}', 'x.json', true);
            var loc:textmate.RawGrammar.ILocation = v.get("$vscodeTextmateLocation");
            T.equals(loc.line, 1);
            T.equals(loc.char, 0);
            var inner:textmate.OrderedMap<Dynamic> = v.get('a');
            var loc2:textmate.RawGrammar.ILocation = inner.get("$vscodeTextmateLocation");
            T.equals(loc2.line, 2);
            T.equals(loc2.char, 7);
            T.equals(loc2.filename, 'x.json');
        });
    }
}
