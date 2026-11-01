// Ported from vscode-textmate 9.2.0: src/theme.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import haxe.ds.ArraySort;
import haxe.ds.StringMap;
import textmate.RawGrammar.RawValue;
import textmate.Utils.CachedFn;

/**
 * Identifiers with a binary dot operator.
 * Examples: `baz` or `foo.bar`
 */
typedef ScopeName = String;

/**
 * An expression language of ScopeNames with a binary space (to indicate nesting) operator.
 * Examples: `foo.bar boo.baz`
 */
typedef ScopePath = String;

/**
 * An expression language of ScopePathStr with a binary comma (to indicate alternatives) operator.
 * Examples: `foo.bar boo.baz,quick quack`
 */
typedef ScopePattern = String;

class Theme {
    public static function createFromRawTheme(source:Null<IRawTheme>, ?colorMap:Array<String>):Theme {
        return createFromParsedTheme(parseTheme(source), colorMap);
    }

    public static function createFromParsedTheme(source:Array<ParsedThemeRule>, ?colorMap:Array<String>):Theme {
        return resolveParsedThemeRules(source, colorMap);
    }

    final _cachedMatchRoot:CachedFn<Array<ThemeTrieElementRule>>;

    final _colorMap:ColorMap;
    final _defaults:StyleAttributes;
    final _root:ThemeTrieElement;

    public function new(colorMap:ColorMap, defaults:StyleAttributes, root:ThemeTrieElement) {
        _colorMap = colorMap;
        _defaults = defaults;
        _root = root;
        _cachedMatchRoot = new CachedFn<Array<ThemeTrieElementRule>>((scopeName) -> _root.match(scopeName));
    }

    public function getColorMap():Array<String> {
        return _colorMap.getColorMap();
    }

    public function getDefaults():StyleAttributes {
        return _defaults;
    }

    public function match(scopePath:Null<ScopeStack>):Null<StyleAttributes> {
        if (scopePath == null) {
            return _defaults;
        }
        var scopeName = scopePath.scopeName;
        var matchingTrieElements = _cachedMatchRoot.get(scopeName);

        var effectiveRule:Null<ThemeTrieElementRule> = null;
        for (v in matchingTrieElements) {
            if (_scopePathMatchesParentScopes(scopePath.parent, v.parentScopes)) {
                effectiveRule = v;
                break;
            }
        }
        if (effectiveRule == null) {
            return null;
        }

        return new StyleAttributes(effectiveRule.fontStyle, effectiveRule.foreground, effectiveRule.background);
    }

    /** Internal state, used by the tests. */
    @:noCompletion public function _getColorMapObject():ColorMap {
        return _colorMap;
    }

    /** Internal state, used by the tests. */
    @:noCompletion public function _getRoot():ThemeTrieElement {
        return _root;
    }

    static function _scopePathMatchesParentScopes(scopePath:Null<ScopeStack>, parentScopes:Array<ScopeName>):Bool {
        if (parentScopes.length == 0) {
            return true;
        }

        // Starting with the deepest parent scope, look for a match in the scope path.
        var index = 0;
        while (index < parentScopes.length) {
            var scopePattern = parentScopes[index];
            var scopeMustMatch = false;

            // Check for a child combinator (a parent-child relationship)
            if (scopePattern == '>') {
                if (index == parentScopes.length - 1) {
                    // Invalid use of child combinator
                    return false;
                }
                scopePattern = parentScopes[++index];
                scopeMustMatch = true;
            }

            while (scopePath != null) {
                if (_matchesScope(scopePath.scopeName, scopePattern)) {
                    break;
                }
                if (scopeMustMatch) {
                    // If a child combinator was used, the parent scope must match.
                    return false;
                }
                scopePath = scopePath.parent;
            }

            if (scopePath == null) {
                // No more potential matches
                return false;
            }
            scopePath = scopePath.parent;
            index++;
        }

        // All parent scopes were matched.
        return true;
    }

    static function _matchesScope(scopeName:ScopeName, scopePattern:ScopeName):Bool {
        return scopePattern == scopeName
            || (StringTools.startsWith(scopeName, scopePattern) && scopeName.length > scopePattern.length && StringTools.fastCodeAt(scopeName, scopePattern.length) == '.'.code);
    }

    /**
     * Parse a raw theme into rules.
     */
    public static function parseTheme(source:Null<IRawTheme>):Array<ParsedThemeRule> {
        if (source == null) {
            return [];
        }
        if (source.settings == null) {
            return [];
        }
        var settings = source.settings;
        var result:Array<ParsedThemeRule> = [];
        for (i in 0...settings.length) {
            var entry = settings[i];

            if (entry == null || entry.settings == null) {
                continue;
            }

            var scopes:Array<String>;
            if (Std.isOfType(entry.scope, String)) {
                var _scope:String = entry.scope;

                // remove leading commas
                var start = 0;
                while (start < _scope.length && StringTools.fastCodeAt(_scope, start) == ','.code) {
                    start++;
                }
                _scope = _scope.substring(start);

                // remove trailing commans
                var end = _scope.length;
                while (end > 0 && StringTools.fastCodeAt(_scope, end - 1) == ','.code) {
                    end--;
                }
                _scope = _scope.substring(0, end);

                scopes = _scope.split(',');
            } else if (Std.isOfType(entry.scope, Array)) {
                scopes = [for (s in (entry.scope : Array<Dynamic>)) Std.string(s)];
            } else {
                scopes = [''];
            }

            var fontStyle:Int = FontStyle.NotSet;
            if (Std.isOfType(entry.settings.fontStyle, String)) {
                fontStyle = FontStyle.None;

                var segments = (entry.settings.fontStyle : String).split(' ');
                for (segment in segments) {
                    switch segment {
                        case 'italic':
                            fontStyle = fontStyle | FontStyle.Italic;
                        case 'bold':
                            fontStyle = fontStyle | FontStyle.Bold;
                        case 'underline':
                            fontStyle = fontStyle | FontStyle.Underline;
                        case 'strikethrough':
                            fontStyle = fontStyle | FontStyle.Strikethrough;
                        default:
                    }
                }
            }

            var foreground:Null<String> = null;
            if (Std.isOfType(entry.settings.foreground, String) && Utils.isValidHexColor(entry.settings.foreground)) {
                foreground = entry.settings.foreground;
            }

            var background:Null<String> = null;
            if (Std.isOfType(entry.settings.background, String) && Utils.isValidHexColor(entry.settings.background)) {
                background = entry.settings.background;
            }

            for (j in 0...scopes.length) {
                var _scope = Utils.jsTrim(scopes[j]);

                var segments = _scope.split(' ');

                var scope = segments[segments.length - 1];
                var parentScopes:Null<Array<String>> = null;
                if (segments.length > 1) {
                    parentScopes = segments.slice(0, segments.length - 1);
                    parentScopes.reverse();
                }

                result.push(new ParsedThemeRule(scope, parentScopes, i, fontStyle, foreground, background));
            }
        }

        return result;
    }

    public static function fontStyleToString(fontStyle:Int):String {
        if (fontStyle == FontStyle.NotSet) {
            return 'not set';
        }

        var style = '';
        if (fontStyle & FontStyle.Italic != 0) {
            style += 'italic ';
        }
        if (fontStyle & FontStyle.Bold != 0) {
            style += 'bold ';
        }
        if (fontStyle & FontStyle.Underline != 0) {
            style += 'underline ';
        }
        if (fontStyle & FontStyle.Strikethrough != 0) {
            style += 'strikethrough ';
        }
        if (style == '') {
            style = 'none';
        }
        return StringTools.trim(style);
    }

    /**
     * Resolve rules (i.e. inheritance).
     */
    static function resolveParsedThemeRules(parsedThemeRules:Array<ParsedThemeRule>, _colorMap:Null<Array<String>>):Theme {
        // Sort rules lexicographically, and then by index if necessary
        ArraySort.sort(parsedThemeRules, (a, b) -> {
            var r = Utils.strcmp(a.scope, b.scope);
            if (r != 0) {
                return r;
            }
            r = Utils.strArrCmp(a.parentScopes, b.parentScopes);
            if (r != 0) {
                return r;
            }
            return a.index - b.index;
        });

        // Determine defaults
        var defaultFontStyle:Int = FontStyle.None;
        var defaultForeground = '#000000';
        var defaultBackground = '#ffffff';
        while (parsedThemeRules.length >= 1 && parsedThemeRules[0].scope == '') {
            var incomingDefaults = parsedThemeRules.shift();
            if (incomingDefaults.fontStyle != FontStyle.NotSet) {
                defaultFontStyle = incomingDefaults.fontStyle;
            }
            if (incomingDefaults.foreground != null) {
                defaultForeground = incomingDefaults.foreground;
            }
            if (incomingDefaults.background != null) {
                defaultBackground = incomingDefaults.background;
            }
        }
        var colorMap = new ColorMap(_colorMap);
        var defaults = new StyleAttributes(defaultFontStyle, colorMap.getId(defaultForeground), colorMap.getId(defaultBackground));

        var root = new ThemeTrieElement(new ThemeTrieElementRule(0, null, FontStyle.NotSet, 0, 0), []);
        for (rule in parsedThemeRules) {
            root.insert(0, rule.scope, rule.parentScopes, rule.fontStyle, colorMap.getId(rule.foreground), colorMap.getId(rule.background));
        }

        return new Theme(colorMap, defaults, root);
    }
}

/**
 * A TextMate theme.
 */
class IRawTheme {
    public var name:Null<String>;
    public var settings:Array<IRawThemeSetting>;

    public function new(?name:String, ?settings:Array<IRawThemeSetting>) {
        this.name = name;
        this.settings = settings;
    }

    /**
     * Converts a parsed theme file (anonymous structures, or the `OrderedMap`
     * objects of `Json.parseJSON` and `Plist.parsePLIST`).
     */
    public static function fromDynamic(obj:Dynamic):Null<IRawTheme> {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, IRawTheme)) {
            return obj;
        }
        var r = new IRawTheme(RawValue.string(RawValue.field(obj, 'name')), null);
        var settings:Dynamic = RawValue.field(obj, 'settings');
        if (settings != null && Std.isOfType(settings, Array)) {
            r.settings = [for (s in (settings : Array<Dynamic>)) IRawThemeSetting.fromDynamic(s)];
        }
        return r;
    }
}

/**
 * A single theme setting.
 */
class IRawThemeSetting {
    public var name:Null<String>;
    /** A `ScopePattern` string, an array of them, or null. */
    public var scope:Dynamic;
    public var settings:Null<IRawThemeSettingStyle>;

    public function new(?name:String, ?scope:Dynamic, ?settings:IRawThemeSettingStyle) {
        this.name = name;
        this.scope = scope;
        this.settings = settings;
    }

    public static function fromDynamic(obj:Dynamic):Null<IRawThemeSetting> {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, IRawThemeSetting)) {
            return obj;
        }
        var scope:Dynamic = RawValue.field(obj, 'scope');
        if (scope != null && Std.isOfType(scope, Array)) {
            scope = [for (s in (scope : Array<Dynamic>)) s];
        } else if (!Std.isOfType(scope, String)) {
            scope = null;
        }
        var settings:Dynamic = RawValue.field(obj, 'settings');
        var style:Null<IRawThemeSettingStyle> = null;
        if (settings != null && RawValue.isObject(settings)) {
            style = new IRawThemeSettingStyle(RawValue.field(settings, 'fontStyle'), RawValue.field(settings, 'foreground'), RawValue.field(settings, 'background'));
        }
        return new IRawThemeSetting(RawValue.string(RawValue.field(obj, 'name')), scope, style);
    }
}

class IRawThemeSettingStyle {
    /** Read only when it is a string. */
    public var fontStyle:Dynamic;
    /** Read only when it is a string. */
    public var foreground:Dynamic;
    /** Read only when it is a string. */
    public var background:Dynamic;

    public function new(?fontStyle:Dynamic, ?foreground:Dynamic, ?background:Dynamic) {
        this.fontStyle = fontStyle;
        this.foreground = foreground;
        this.background = background;
    }
}

class ScopeStack {
    public static function pushAll(path:Null<ScopeStack>, scopeNames:Array<ScopeName>):Null<ScopeStack> {
        for (name in scopeNames) {
            path = new ScopeStack(path, name);
        }
        return path;
    }

    public static function from(segments:Array<ScopeName>):Null<ScopeStack> {
        var result:Null<ScopeStack> = null;
        for (i in 0...segments.length) {
            result = new ScopeStack(result, segments[i]);
        }
        return result;
    }

    public final parent:Null<ScopeStack>;
    public final scopeName:ScopeName;

    public inline function new(parent:Null<ScopeStack>, scopeName:ScopeName) {
        this.parent = parent;
        this.scopeName = scopeName;
    }

    public function push(scopeName:ScopeName):ScopeStack {
        return new ScopeStack(this, scopeName);
    }

    public function getSegments():Array<ScopeName> {
        var item:Null<ScopeStack> = this;
        var result:Array<ScopeName> = [];
        while (item != null) {
            result.push(item.scopeName);
            item = item.parent;
        }
        result.reverse();
        return result;
    }

    public function toString():String {
        return getSegments().join(' ');
    }

    public function extends_(other:ScopeStack):Bool {
        if (this == other) {
            return true;
        }
        if (parent == null) {
            return false;
        }
        return parent.extends_(other);
    }

    public function getExtensionIfDefined(base:Null<ScopeStack>):Null<Array<String>> {
        var result:Array<String> = [];
        var item:Null<ScopeStack> = this;
        while (item != null && item != base) {
            result.push(item.scopeName);
            item = item.parent;
        }
        if (item == base) {
            result.reverse();
            return result;
        }
        return null;
    }
}

class StyleAttributes {
    public final fontStyle:Int;
    public final foregroundId:Int;
    public final backgroundId:Int;

    public inline function new(fontStyle:Int, foregroundId:Int, backgroundId:Int) {
        this.fontStyle = fontStyle;
        this.foregroundId = foregroundId;
        this.backgroundId = backgroundId;
    }
}

class ParsedThemeRule {
    public final scope:ScopeName;
    public final parentScopes:Null<Array<ScopeName>>;
    public final index:Int;
    public final fontStyle:Int;
    public final foreground:Null<String>;
    public final background:Null<String>;

    public function new(scope:ScopeName, parentScopes:Null<Array<ScopeName>>, index:Int, fontStyle:Int, foreground:Null<String>, background:Null<String>) {
        this.scope = scope;
        this.parentScopes = parentScopes;
        this.index = index;
        this.fontStyle = fontStyle;
        this.foreground = foreground;
        this.background = background;
    }
}

enum abstract FontStyle(Int) from Int to Int {
    var NotSet = -1;
    var None = 0;
    var Italic = 1;
    var Bold = 2;
    var Underline = 4;
    var Strikethrough = 8;
}

class ColorMap {
    final _isFrozen:Bool;
    var _lastColorId:Int;
    var _id2color:Array<String>;
    var _color2id:StringMap<Int>;

    public function new(?_colorMap:Array<String>) {
        _lastColorId = 0;
        _id2color = [];
        _color2id = new StringMap<Int>();

        if (_colorMap != null) {
            _isFrozen = true;
            for (i in 0..._colorMap.length) {
                _color2id.set(_colorMap[i], i);
                _id2color[i] = _colorMap[i];
            }
        } else {
            _isFrozen = false;
        }
    }

    public function getId(color:Null<String>):Int {
        if (color == null) {
            return 0;
        }
        color = color.toUpperCase();
        var value = _color2id.get(color);
        if (value != null && value != 0) {
            return value;
        }
        if (_isFrozen) {
            throw 'Missing color in color map - ' + color;
        }
        value = ++_lastColorId;
        _color2id.set(color, value);
        _id2color[value] = color;
        return value;
    }

    public function getColorMap():Array<String> {
        return _id2color.copy();
    }
}

class ThemeTrieElementRule {
    static final emptyParentScopes:Array<ScopeName> = [];

    public var scopeDepth:Int;
    public var parentScopes:Array<ScopeName>;
    public var fontStyle:Int;
    public var foreground:Int;
    public var background:Int;

    public function new(scopeDepth:Int, parentScopes:Null<Array<ScopeName>>, fontStyle:Int, foreground:Int, background:Int) {
        this.scopeDepth = scopeDepth;
        this.parentScopes = parentScopes != null ? parentScopes : emptyParentScopes;
        this.fontStyle = fontStyle;
        this.foreground = foreground;
        this.background = background;
    }

    public function clone():ThemeTrieElementRule {
        return new ThemeTrieElementRule(scopeDepth, parentScopes, fontStyle, foreground, background);
    }

    public static function cloneArr(arr:Array<ThemeTrieElementRule>):Array<ThemeTrieElementRule> {
        return [for (r in arr) r.clone()];
    }

    public function acceptOverwrite(scopeDepth:Int, fontStyle:Int, foreground:Int, background:Int):Void {
        if (this.scopeDepth > scopeDepth) {
            // how did this happen?
        } else {
            this.scopeDepth = scopeDepth;
        }
        if (fontStyle != FontStyle.NotSet) {
            this.fontStyle = fontStyle;
        }
        if (foreground != 0) {
            this.foreground = foreground;
        }
        if (background != 0) {
            this.background = background;
        }
    }
}

class ThemeTrieElement {
    final _mainRule:ThemeTrieElementRule;
    final _rulesWithParentScopes:Array<ThemeTrieElementRule>;
    final _children:OrderedMap<ThemeTrieElement>;

    public function new(mainRule:ThemeTrieElementRule, ?rulesWithParentScopes:Array<ThemeTrieElementRule>, ?children:OrderedMap<ThemeTrieElement>) {
        _mainRule = mainRule;
        _rulesWithParentScopes = rulesWithParentScopes != null ? rulesWithParentScopes : [];
        _children = children != null ? children : new OrderedMap<ThemeTrieElement>();
    }

    /** Internal state, used by the tests. */
    @:noCompletion public function _getMainRule():ThemeTrieElementRule {
        return _mainRule;
    }

    /** Internal state, used by the tests. */
    @:noCompletion public function _getRulesWithParentScopes():Array<ThemeTrieElementRule> {
        return _rulesWithParentScopes;
    }

    /** Internal state, used by the tests. */
    @:noCompletion public function _getChildren():OrderedMap<ThemeTrieElement> {
        return _children;
    }

    static function _cmpBySpecificity(a:ThemeTrieElementRule, b:ThemeTrieElementRule):Int {
        // First, compare the scope depths of both rules. The "scope depth" of a rule is
        // the number of segments (delimited by dots) in the rule's deepest scope name
        // (i.e. the final scope name in the scope path delimited by spaces).
        if (a.scopeDepth != b.scopeDepth) {
            return b.scopeDepth - a.scopeDepth;
        }

        // Traverse the parent scopes depth-first, comparing the specificity of both
        // rules' parent scopes, which matches the behavior described by "Ranking Matches"
        // in TextMate 1.5's manual: https://macromates.com/manual/en/scope_selectors
        // Start at index 0 for both rules, since the parent scopes were reversed
        // beforehand (i.e. index 0 is the deepest parent scope).
        var aParentIndex = 0;
        var bParentIndex = 0;

        while (true) {
            // Child combinators don't affect specificity.
            if (aParentIndex < a.parentScopes.length && a.parentScopes[aParentIndex] == '>') {
                aParentIndex++;
            }
            if (bParentIndex < b.parentScopes.length && b.parentScopes[bParentIndex] == '>') {
                bParentIndex++;
            }

            // This is a scope-by-scope comparison, so we need to stop once a rule runs
            // out of parent scopes.
            if (aParentIndex >= a.parentScopes.length || bParentIndex >= b.parentScopes.length) {
                break;
            }

            // When sorting by scope name specificity, it's safe to treat a longer parent
            // scope as more specific. If both rules' parent scopes match a given scope
            // path, the longer parent scope will always be more specific.
            var parentScopeLengthDiff = b.parentScopes[bParentIndex].length - a.parentScopes[aParentIndex].length;

            if (parentScopeLengthDiff != 0) {
                return parentScopeLengthDiff;
            }

            aParentIndex++;
            bParentIndex++;
        }

        // If a depth-first, scope-by-scope comparison resulted in a tie, the rule with
        // more parent scopes is considered more specific.
        return b.parentScopes.length - a.parentScopes.length;
    }

    public function match(scope:ScopeName):Array<ThemeTrieElementRule> {
        if (scope != '') {
            var dotIndex = scope.indexOf('.');
            var head:String;
            var tail:String;
            if (dotIndex == -1) {
                head = scope;
                tail = '';
            } else {
                head = scope.substring(0, dotIndex);
                tail = scope.substring(dotIndex + 1);
            }

            var child = _children.get(head);
            if (child != null) {
                return child.match(tail);
            }
        }

        var rules = _rulesWithParentScopes.concat([_mainRule]);
        ArraySort.sort(rules, _cmpBySpecificity);
        return rules;
    }

    public function insert(scopeDepth:Int, scope:ScopeName, parentScopes:Null<Array<ScopeName>>, fontStyle:Int, foreground:Int, background:Int):Void {
        if (scope == '') {
            _doInsertHere(scopeDepth, parentScopes, fontStyle, foreground, background);
            return;
        }

        var dotIndex = scope.indexOf('.');
        var head:String;
        var tail:String;
        if (dotIndex == -1) {
            head = scope;
            tail = '';
        } else {
            head = scope.substring(0, dotIndex);
            tail = scope.substring(dotIndex + 1);
        }

        var child = _children.get(head);
        if (child == null) {
            child = new ThemeTrieElement(_mainRule.clone(), ThemeTrieElementRule.cloneArr(_rulesWithParentScopes));
            _children.set(head, child);
        }

        child.insert(scopeDepth + 1, tail, parentScopes, fontStyle, foreground, background);
    }

    function _doInsertHere(scopeDepth:Int, parentScopes:Null<Array<ScopeName>>, fontStyle:Int, foreground:Int, background:Int):Void {
        if (parentScopes == null) {
            // Merge into the main rule
            _mainRule.acceptOverwrite(scopeDepth, fontStyle, foreground, background);
            return;
        }

        // Try to merge into existing rule
        for (rule in _rulesWithParentScopes) {
            if (Utils.strArrCmp(rule.parentScopes, parentScopes) == 0) {
                // bingo! => we get to merge this into an existing one
                rule.acceptOverwrite(scopeDepth, fontStyle, foreground, background);
                return;
            }
        }

        // Must add a new rule

        // Inherit from main rule
        if (fontStyle == FontStyle.NotSet) {
            fontStyle = _mainRule.fontStyle;
        }
        if (foreground == 0) {
            foreground = _mainRule.foreground;
        }
        if (background == 0) {
            background = _mainRule.background;
        }

        _rulesWithParentScopes.push(new ThemeTrieElementRule(scopeDepth, parentScopes, fontStyle, foreground, background));
    }
}
