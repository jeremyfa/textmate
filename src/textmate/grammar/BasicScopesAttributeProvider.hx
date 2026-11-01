// Ported from vscode-textmate 9.2.0: src/grammar/basicScopesAttributeProvider.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate.grammar;

import haxe.ds.ArraySort;
import haxe.ds.StringMap;
import textmate.EncodedTokenAttributes.OptionalStandardTokenType;
import textmate.IGrammar.IEmbeddedLanguagesMap;
import textmate.Theme.ScopeName;
import textmate.Utils.CachedFn;

class BasicScopeAttributes {
    public final languageId:Int;
    public final tokenType:OptionalStandardTokenType;

    public function new(languageId:Int, tokenType:OptionalStandardTokenType) {
        this.languageId = languageId;
        this.tokenType = tokenType;
    }
}

class BasicScopeAttributesProvider {
    final _defaultAttributes:BasicScopeAttributes;
    final _embeddedLanguagesMatcher:ScopeMatcher;
    final _getBasicScopeAttributes:CachedFn<BasicScopeAttributes>;

    static final _NULL_SCOPE_METADATA = new BasicScopeAttributes(0, 0);

    public function new(initialLanguageId:Int, embeddedLanguages:Null<IEmbeddedLanguagesMap>) {
        _defaultAttributes = new BasicScopeAttributes(initialLanguageId, OptionalStandardTokenType.NotSet);
        var entries:Array<{scopeName:String, value:Int}> = [];
        if (embeddedLanguages != null) {
            for (key in embeddedLanguages.keys()) {
                entries.push({scopeName: key, value: embeddedLanguages.get(key)});
            }
        }
        _embeddedLanguagesMatcher = new ScopeMatcher(entries);
        _getBasicScopeAttributes = new CachedFn<BasicScopeAttributes>((scopeName) -> {
            var languageId = _scopeToLanguage(scopeName);
            var standardTokenType = _toStandardTokenType(scopeName);
            return new BasicScopeAttributes(languageId, standardTokenType);
        });
    }

    public function getDefaultAttributes():BasicScopeAttributes {
        return _defaultAttributes;
    }

    public function getBasicScopeAttributes(scopeName:Null<ScopeName>):BasicScopeAttributes {
        if (scopeName == null) {
            return _NULL_SCOPE_METADATA;
        }
        return _getBasicScopeAttributes.get(scopeName);
    }

    /**
     * Given a produced TM scope, return the language that token describes or null if unknown.
     * e.g. source.html => html, source.css.embedded.html => css, punctuation.definition.tag.html => null
     */
    function _scopeToLanguage(scope:ScopeName):Int {
        var r = _embeddedLanguagesMatcher.match(scope);
        return r == null || r == 0 ? 0 : r;
    }

    static inline function isWordChar(c:Int):Bool {
        return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || (c >= '0'.code && c <= '9'.code) || c == '_'.code;
    }

    static final STANDARD_TOKEN_TYPES = ['comment', 'string', 'regex', 'meta.embedded'];

    function _toStandardTokenType(scopeName:ScopeName):OptionalStandardTokenType {
        // scopeName.match(/\b(comment|string|regex|meta\.embedded)\b/)
        var len = scopeName.length;
        for (i in 0...len) {
            if (i > 0 && isWordChar(StringTools.fastCodeAt(scopeName, i - 1))) {
                continue;
            }
            for (k in 0...STANDARD_TOKEN_TYPES.length) {
                var candidate = STANDARD_TOKEN_TYPES[k];
                var end = i + candidate.length;
                if (end > len) {
                    continue;
                }
                if (scopeName.substr(i, candidate.length) != candidate) {
                    continue;
                }
                if (end < len && isWordChar(StringTools.fastCodeAt(scopeName, end))) {
                    continue;
                }
                switch k {
                    case 0:
                        return OptionalStandardTokenType.Comment;
                    case 1:
                        return OptionalStandardTokenType.String;
                    case 2:
                        return OptionalStandardTokenType.RegEx;
                    default:
                        return OptionalStandardTokenType.Other;
                }
            }
        }
        return OptionalStandardTokenType.NotSet;
    }
}

private class ScopeMatcher {
    final values:Null<StringMap<Int>>;
    /** The scopes of the regular expression, in the order it tries them. */
    final scopes:Null<Array<String>>;

    public function new(values:Array<{scopeName:String, value:Int}>) {
        if (values.length == 0) {
            this.values = null;
            this.scopes = null;
        } else {
            var map = new StringMap<Int>();
            for (entry in values) {
                map.set(entry.scopeName, entry.value);
            }
            this.values = map;

            // vscode-textmate builds `^((s1)|(s2)|...)($|\.)` from the escaped
            // scopes sorted in reverse order (longest scope first).
            var escapedScopes = [for (entry in values) {escaped: Utils.escapeRegExpCharacters(entry.scopeName), scopeName: entry.scopeName}];
            ArraySort.sort(escapedScopes, (a, b) -> Utils.strcmp(a.escaped, b.escaped));
            escapedScopes.reverse();
            this.scopes = [for (e in escapedScopes) e.scopeName];
        }
    }

    public function match(scope:ScopeName):Null<Int> {
        if (scopes == null) {
            return null;
        }
        for (candidate in scopes) {
            if (StringTools.startsWith(scope, candidate)
                && (scope.length == candidate.length || StringTools.fastCodeAt(scope, candidate.length) == '.'.code)) {
                return values.get(candidate);
            }
        }
        // no scopes matched
        return null;
    }
}
