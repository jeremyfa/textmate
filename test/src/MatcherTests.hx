// Ported from vscode-textmate 9.2.0: src/tests/matcher.test.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import textmate.Matcher;

class MatcherTests {
    public static function run():Void {
        T.suite('matcher');
        var tests:Array<{expression:String, input:Array<String>, result:Bool}> = [
            {expression: "foo", input: ["foo"], result: true},
            {expression: "foo", input: ["bar"], result: false},
            {expression: "- foo", input: ["foo"], result: false},
            {expression: "- foo", input: ["bar"], result: true},
            {expression: "- - foo", input: ["bar"], result: false},
            {expression: "bar foo", input: ["foo"], result: false},
            {expression: "bar foo", input: ["bar"], result: false},
            {expression: "bar foo", input: ["bar", "foo"], result: true},
            {expression: "bar - foo", input: ["bar"], result: true},
            {expression: "bar - foo", input: ["foo", "bar"], result: false},
            {expression: "bar - foo", input: ["foo"], result: false},
            {expression: "bar, foo", input: ["foo"], result: true},
            {expression: "bar, foo", input: ["bar"], result: true},
            {expression: "bar, foo", input: ["bar", "foo"], result: true},
            {expression: "bar, -foo", input: ["bar", "foo"], result: true},
            {expression: "bar, -foo", input: ["yo"], result: true},
            {expression: "bar, -foo", input: ["foo"], result: false},
            {expression: "(foo)", input: ["foo"], result: true},
            {expression: "(foo - bar)", input: ["foo"], result: true},
            {expression: "(foo - bar)", input: ["foo", "bar"], result: false},
            {expression: "foo bar - (yo man)", input: ["foo", "bar"], result: true},
            {expression: "foo bar - (yo man)", input: ["foo", "bar", "yo"], result: true},
            {expression: "foo bar - (yo man)", input: ["foo", "bar", "yo", "man"], result: false},
            {expression: "foo bar - (yo | man)", input: ["foo", "bar", "yo", "man"], result: false},
            {expression: "foo bar - (yo | man)", input: ["foo", "bar", "yo"], result: false},
            {expression: "R:text.html - (comment.block, text.html source)", input: ["text.html", "bar", "source"], result: false},
            {
                expression: "text.html.php - (meta.embedded | meta.tag), L:text.html.php meta.tag, L:source.js.embedded.html",
                input: ["text.html.php", "bar", "source.js"],
                result: true
            }
        ];

        var nameMatcher = (identifers:Array<String>, stackElements:Array<String>) -> {
            var lastIndex = 0;
            for (identifier in identifers) {
                var found = false;
                for (i in lastIndex...stackElements.length) {
                    if (stackElements[i] == identifier) {
                        lastIndex = i + 1;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    return false;
                }
            }
            return true;
        };

        for (index in 0...tests.length) {
            var tst = tests[index];
            T.test('Matcher Test #' + index, () -> {
                var matchers = Matchers.createMatchers(tst.expression, nameMatcher);
                var result = false;
                for (m in matchers) {
                    if (m.matcher(tst.input)) {
                        result = true;
                        break;
                    }
                }
                T.equals(result, tst.result);
            });
        }
    }
}
