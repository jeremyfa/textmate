// Ported from vscode-textmate 9.2.0: src/grammar/grammar.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate.grammar;

import haxe.ds.ArraySort;
import haxe.ds.StringMap;
import textmate.EncodedTokenAttributes;
import textmate.IGrammar;
import textmate.Matcher;
import textmate.OnigLib;
import textmate.RawGrammar;
import textmate.Rule;
import textmate.Theme;
import textmate.grammar.BasicScopesAttributeProvider;

interface IThemeProvider {
    function themeMatch(scopePath:ScopeStack):Null<StyleAttributes>;
    function getDefaults():StyleAttributes;
}

interface IGrammarRepository {
    function lookup(scopeName:ScopeName):Null<IRawGrammar>;
    function injections(scopeName:ScopeName):Null<Array<ScopeName>>;
}

/**
 * `IGrammarRepository & IThemeProvider`
 */
interface IGrammarRepositoryAndThemeProvider extends IGrammarRepository extends IThemeProvider {}

class Injection {
    public final debugSelector:String;
    public final matcher:Matcher<Array<String>>;
    /** 0 is the default. -1 for 'L' and 1 for 'R' */
    public final priority:Int;
    public final ruleId:RuleId;
    public final grammar:IRawGrammar;

    public function new(debugSelector:String, matcher:Matcher<Array<String>>, priority:Int, ruleId:RuleId, grammar:IRawGrammar) {
        this.debugSelector = debugSelector;
        this.matcher = matcher;
        this.priority = priority;
        this.ruleId = ruleId;
        this.grammar = grammar;
    }
}

private class TokenTypeMatcher {
    public final matcher:Matcher<Array<String>>;
    public final type:StandardTokenType;

    public function new(matcher:Matcher<Array<String>>, type:StandardTokenType) {
        this.matcher = matcher;
        this.type = type;
    }
}

class GrammarTools {
    public static function createGrammar(scopeName:ScopeName, grammar:IRawGrammar, initialLanguage:Int, embeddedLanguages:Null<IEmbeddedLanguagesMap>,
            tokenTypes:Null<ITokenTypeMap>, balancedBracketSelectors:Null<BalancedBracketSelectors>, grammarRepository:IGrammarRepositoryAndThemeProvider,
            onigLib:IOnigLib):Grammar {
        return new Grammar(scopeName, grammar, initialLanguage, embeddedLanguages, tokenTypes, balancedBracketSelectors, grammarRepository, onigLib);
    }

    public static function collectInjections(result:Array<Injection>, selector:String, rule:IRawRule, ruleFactoryHelper:IRuleFactoryHelper,
            grammar:IRawGrammar):Void {
        var matchers = Matchers.createMatchers(selector, nameMatcher);
        var ruleId = RuleFactory.getCompiledRuleId(rule, ruleFactoryHelper, grammar.repository);
        for (matcher in matchers) {
            result.push(new Injection(selector, matcher.matcher, matcher.priority, ruleId, grammar));
        }
    }

    public static function nameMatcher(identifers:Array<ScopeName>, scopes:Array<ScopeName>):Bool {
        if (scopes.length < identifers.length) {
            return false;
        }
        var lastIndex = 0;
        for (identifier in identifers) {
            var found = false;
            for (i in lastIndex...scopes.length) {
                if (scopesAreMatching(scopes[i], identifier)) {
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
    }

    static function scopesAreMatching(thisScopeName:String, scopeName:String):Bool {
        if (thisScopeName == null || thisScopeName.length == 0) {
            return false;
        }
        if (thisScopeName == scopeName) {
            return true;
        }
        var len = scopeName.length;
        return thisScopeName.length > len && StringTools.startsWith(thisScopeName, scopeName) && StringTools.fastCodeAt(thisScopeName, len) == '.'.code;
    }

    public static function initGrammar(grammar:IRawGrammar, base:Null<IRawRule>):IRawGrammar {
        grammar = grammar.clone();

        if (grammar.repository == null) {
            grammar.repository = new OrderedMap<IRawRule>();
        }
        var self = new IRawRule();
        self.vscodeTextmateLocation = grammar.vscodeTextmateLocation;
        self.patterns = grammar.patterns;
        self.name = grammar.scopeName;
        grammar.repository.set("$self", self);
        grammar.repository.set("$base", base != null ? base : self);
        return grammar;
    }
}

class Grammar implements IGrammar implements IRuleFactoryHelper implements IRuleCompileHelper {
    var _rootId:RuleId;
    var _lastRuleId:Int;
    final _ruleId2desc:Array<Rule>;
    final _includedGrammars:StringMap<IRawGrammar>;
    final _grammarRepository:IGrammarRepositoryAndThemeProvider;
    final _grammar:IRawGrammar;
    var _injections:Null<Array<Injection>>;
    final _basicScopeAttributesProvider:BasicScopeAttributesProvider;
    final _tokenTypeMatchers:Array<TokenTypeMatcher>;

    final _rootScopeName:ScopeName;
    final balancedBracketSelectors:Null<BalancedBracketSelectors>;
    final _onigLib:IOnigLib;

    public var themeProvider(get, never):IThemeProvider;

    inline function get_themeProvider():IThemeProvider {
        return _grammarRepository;
    }

    public function new(_rootScopeName:ScopeName, grammar:IRawGrammar, initialLanguage:Int, embeddedLanguages:Null<IEmbeddedLanguagesMap>,
            tokenTypes:Null<ITokenTypeMap>, balancedBracketSelectors:Null<BalancedBracketSelectors>, grammarRepository:IGrammarRepositoryAndThemeProvider,
            _onigLib:IOnigLib) {
        this._rootScopeName = _rootScopeName;
        this.balancedBracketSelectors = balancedBracketSelectors;
        this._onigLib = _onigLib;

        this._basicScopeAttributesProvider = new BasicScopeAttributesProvider(initialLanguage, embeddedLanguages);

        this._rootId = -1;
        this._lastRuleId = 0;
        this._ruleId2desc = [null];
        this._includedGrammars = new StringMap<IRawGrammar>();
        this._grammarRepository = grammarRepository;
        this._grammar = GrammarTools.initGrammar(grammar, null);
        this._injections = null;

        this._tokenTypeMatchers = [];
        if (tokenTypes != null) {
            for (selector in tokenTypes.keys()) {
                var matchers = Matchers.createMatchers(selector, GrammarTools.nameMatcher);
                for (matcher in matchers) {
                    this._tokenTypeMatchers.push(new TokenTypeMatcher(matcher.matcher, tokenTypes.get(selector)));
                }
            }
        }
    }

    public function dispose():Void {
        for (rule in _ruleId2desc) {
            if (rule != null) {
                rule.dispose();
            }
        }
    }

    public function createOnigScanner(sources:Array<String>):OnigScanner {
        return _onigLib.createOnigScanner(sources);
    }

    public function createOnigString(sources:String):OnigString {
        return _onigLib.createOnigString(sources);
    }

    public function getMetadataForScope(scope:String):BasicScopeAttributes {
        return _basicScopeAttributesProvider.getBasicScopeAttributes(scope);
    }

    function _collectInjections():Array<Injection> {
        var grammarRepository = new InjectionGrammarRepository(this);

        var result:Array<Injection> = [];

        var scopeName = _rootScopeName;

        var grammar = grammarRepository.lookup(scopeName);
        if (grammar != null) {
            // add injections from the current grammar
            var rawInjections = grammar.injections;
            if (rawInjections != null) {
                for (expression in rawInjections.keys()) {
                    var rule = rawInjections.get(expression);
                    if (rule != null) {
                        GrammarTools.collectInjections(result, expression, rule, this, grammar);
                    }
                }
            }

            // add injection grammars contributed for the current scope

            var injectionScopeNames = _grammarRepository.injections(scopeName);
            if (injectionScopeNames != null) {
                for (injectionScopeName in injectionScopeNames) {
                    var injectionGrammar = getExternalGrammar(injectionScopeName);
                    if (injectionGrammar != null) {
                        var selector = injectionGrammar.injectionSelector;
                        if (selector != null && selector.length > 0) {
                            GrammarTools.collectInjections(result, selector, _grammarAsRule(injectionGrammar), this, injectionGrammar);
                        }
                    }
                }
            }
        }

        ArraySort.sort(result, (i1, i2) -> i1.priority - i2.priority); // sort by priority

        return result;
    }

    /**
     * vscode-textmate passes the injection grammar object itself as the rule:
     * its `patterns` and `repository` make an include only rule.
     */
    final _grammarRules = new haxe.ds.ObjectMap<IRawGrammar, IRawRule>();

    function _grammarAsRule(grammar:IRawGrammar):IRawRule {
        var rule = _grammarRules.get(grammar);
        if (rule == null) {
            rule = new IRawRule();
            rule.patterns = grammar.patterns;
            rule.repository = grammar.repository;
            rule.name = grammar.name;
            rule.vscodeTextmateLocation = grammar.vscodeTextmateLocation;
            _grammarRules.set(grammar, rule);
        }
        return rule;
    }

    public function getInjections():Array<Injection> {
        if (_injections == null) {
            _injections = _collectInjections();
        }
        return _injections;
    }

    public function registerRule<T:Rule>(factory:(RuleId) -> T):T {
        var id = ++_lastRuleId;
        var result = factory(Rules.ruleIdFromNumber(id));
        _ruleId2desc[id] = result;
        return result;
    }

    public inline function getRule(ruleId:RuleId):Rule {
        return _ruleId2desc[Rules.ruleIdToNumber(ruleId)];
    }

    public function getExternalGrammar(scopeName:String, ?repository:IRawRepository):Null<IRawGrammar> {
        var included = _includedGrammars.get(scopeName);
        if (included != null) {
            return included;
        } else if (_grammarRepository != null) {
            var rawIncludedGrammar = _grammarRepository.lookup(scopeName);
            if (rawIncludedGrammar != null) {
                included = GrammarTools.initGrammar(rawIncludedGrammar, repository != null ? repository.get("$base") : null);
                _includedGrammars.set(scopeName, included);
                return included;
            }
        }
        return null;
    }

    /** The raw grammar this grammar tokenizes with (after initialization). */
    @:noCompletion public inline function _getGrammar():IRawGrammar {
        return _grammar;
    }

    /** The scope name this grammar was created for. */
    @:noCompletion public inline function _getRootScopeName():ScopeName {
        return _rootScopeName;
    }

    public function tokenizeLine(lineText:String, prevState:Null<StateStack>, timeLimit:Int = 0):ITokenizeLineResult {
        var r = _tokenize(lineText, cast prevState, false, timeLimit);
        return new ITokenizeLineResult(r.lineTokens.getResult(r.ruleStack, r.lineLength), r.ruleStack, r.stoppedEarly);
    }

    public function tokenizeLine2(lineText:String, prevState:Null<StateStack>, timeLimit:Int = 0):ITokenizeLineResult2 {
        var r = _tokenize(lineText, cast prevState, true, timeLimit);
        return new ITokenizeLineResult2(r.lineTokens.getBinaryResult(r.ruleStack, r.lineLength), r.ruleStack, r.stoppedEarly);
    }

    function _tokenize(lineText:String, prevState:Null<StateStackImpl>, emitBinaryTokens:Bool, timeLimit:Int):TokenizeResult {
        if (_rootId == -1) {
            _rootId = RuleFactory.getCompiledRuleId(_grammar.repository.get("$self"), this, _grammar.repository);
            // This ensures ids are deterministic, and thus equal in renderer and webworker.
            getInjections();
        }

        var isFirstLine:Bool;
        if (prevState == null || prevState == StateStackImpl.NULL) {
            isFirstLine = true;
            var rawDefaultMetadata = _basicScopeAttributesProvider.getDefaultAttributes();
            var defaultStyle = themeProvider.getDefaults();
            var defaultMetadata = EncodedTokenAttributes.set(0, rawDefaultMetadata.languageId, rawDefaultMetadata.tokenType, -1, defaultStyle.fontStyle,
                defaultStyle.foregroundId, defaultStyle.backgroundId);

            var rootScopeName = getRule(_rootId).getName(null, null);

            var scopeList:AttributedScopeStack;
            if (rootScopeName != null) {
                scopeList = AttributedScopeStack.createRootAndLookUpScopeName(rootScopeName, defaultMetadata, this);
            } else {
                scopeList = AttributedScopeStack.createRoot('unknown', defaultMetadata);
            }

            prevState = new StateStackImpl(null, _rootId, -1, -1, false, null, scopeList, scopeList);
        } else {
            isFirstLine = false;
            prevState.reset();
        }

        lineText = lineText + '\n';
        var onigLineText = createOnigString(lineText);
        var lineLength = onigLineText.content.length;
        var lineTokens = new LineTokens(emitBinaryTokens, lineText, _tokenTypeMatchers, balancedBracketSelectors);
        var r = TokenizeString._tokenizeString(this, onigLineText, isFirstLine, 0, prevState, lineTokens, true, timeLimit);

        OnigLib.disposeOnigString(onigLineText);

        return new TokenizeResult(lineLength, lineTokens, r.stack, r.stoppedEarly);
    }
}

private class InjectionGrammarRepository implements IGrammarRepository {
    final grammar:Grammar;

    public function new(grammar:Grammar) {
        this.grammar = grammar;
    }

    public function lookup(scopeName:String):Null<IRawGrammar> {
        if (scopeName == grammar._getRootScopeName()) {
            return grammar._getGrammar();
        }
        return grammar.getExternalGrammar(scopeName);
    }

    public function injections(scopeName:String):Null<Array<String>> {
        return null;
    }
}

private class TokenizeResult {
    public final lineLength:Int;
    public final lineTokens:LineTokens;
    public final ruleStack:StateStackImpl;
    public final stoppedEarly:Bool;

    public function new(lineLength:Int, lineTokens:LineTokens, ruleStack:StateStackImpl, stoppedEarly:Bool) {
        this.lineLength = lineLength;
        this.lineTokens = lineTokens;
        this.ruleStack = ruleStack;
        this.stoppedEarly = stoppedEarly;
    }
}

class AttributedScopeStack {
    public static function fromExtension(namesScopeList:Null<AttributedScopeStack>, contentNameScopesList:Array<AttributedScopeStackFrame>):Null<AttributedScopeStack> {
        var current = namesScopeList;
        var scopeNames = namesScopeList != null ? namesScopeList.scopePath : null;
        for (frame in contentNameScopesList) {
            scopeNames = ScopeStack.pushAll(scopeNames, frame.scopeNames);
            current = new AttributedScopeStack(current, scopeNames, frame.encodedTokenAttributes);
        }
        return current;
    }

    public static function createRoot(scopeName:ScopeName, tokenAttributes:Int):AttributedScopeStack {
        return new AttributedScopeStack(null, new ScopeStack(null, scopeName), tokenAttributes);
    }

    public static function createRootAndLookUpScopeName(scopeName:ScopeName, tokenAttributes:Int, grammar:Grammar):AttributedScopeStack {
        var rawRootMetadata = grammar.getMetadataForScope(scopeName);
        var scopePath = new ScopeStack(null, scopeName);
        var rootStyle = grammar.themeProvider.themeMatch(scopePath);

        var resolvedTokenAttributes = AttributedScopeStack.mergeAttributes(tokenAttributes, rawRootMetadata, rootStyle);

        return new AttributedScopeStack(null, scopePath, resolvedTokenAttributes);
    }

    public var scopeName(get, never):ScopeName;

    inline function get_scopeName():ScopeName {
        return scopePath.scopeName;
    }

    public final parent:Null<AttributedScopeStack>;
    public final scopePath:ScopeStack;
    public final tokenAttributes:Int;

    /**
     * Invariant:
     * ```
     * if (parent && !scopePath.extends(parent.scopePath)) {
     * 	throw new Error();
     * }
     * ```
     */
    function new(parent:Null<AttributedScopeStack>, scopePath:ScopeStack, tokenAttributes:Int) {
        this.parent = parent;
        this.scopePath = scopePath;
        this.tokenAttributes = tokenAttributes;
    }

    public function toString():String {
        return getScopeNames().join(' ');
    }

    public function equals(other:AttributedScopeStack):Bool {
        return AttributedScopeStack.equalsStacks(this, other);
    }

    public static function equalsStacks(a:Null<AttributedScopeStack>, b:Null<AttributedScopeStack>):Bool {
        do {
            if (a == b) {
                return true;
            }

            if (a == null && b == null) {
                // End of list reached for both
                return true;
            }

            if (a == null || b == null) {
                // End of list reached only for one
                return false;
            }

            if (a.scopeName != b.scopeName || a.tokenAttributes != b.tokenAttributes) {
                return false;
            }

            // Go to previous pair
            a = a.parent;
            b = b.parent;
        } while (true);
    }

    static function mergeAttributes(existingTokenAttributes:Int, basicScopeAttributes:BasicScopeAttributes, styleAttributes:Null<StyleAttributes>):Int {
        var fontStyle:Int = FontStyle.NotSet;
        var foreground = 0;
        var background = 0;

        if (styleAttributes != null) {
            fontStyle = styleAttributes.fontStyle;
            foreground = styleAttributes.foregroundId;
            background = styleAttributes.backgroundId;
        }

        return EncodedTokenAttributes.set(existingTokenAttributes, basicScopeAttributes.languageId, basicScopeAttributes.tokenType, -1, fontStyle,
            foreground, background);
    }

    public function pushAttributed(scopePath:Null<ScopePath>, grammar:Grammar):AttributedScopeStack {
        if (scopePath == null) {
            return this;
        }

        if (scopePath.indexOf(' ') == -1) {
            // This is the common case and much faster

            return AttributedScopeStack._pushAttributed(this, scopePath, grammar);
        }

        var scopes = scopePath.split(' ');
        var result:AttributedScopeStack = this;
        for (scope in scopes) {
            result = AttributedScopeStack._pushAttributed(result, scope, grammar);
        }
        return result;
    }

    static function _pushAttributed(target:AttributedScopeStack, scopeName:ScopeName, grammar:Grammar):AttributedScopeStack {
        var rawMetadata = grammar.getMetadataForScope(scopeName);

        var newPath = target.scopePath.push(scopeName);
        var scopeThemeMatchResult = grammar.themeProvider.themeMatch(newPath);
        var metadata = AttributedScopeStack.mergeAttributes(target.tokenAttributes, rawMetadata, scopeThemeMatchResult);
        return new AttributedScopeStack(target, newPath, metadata);
    }

    public function getScopeNames():Array<String> {
        return scopePath.getSegments();
    }

    public function getExtensionIfDefined(base:Null<AttributedScopeStack>):Null<Array<AttributedScopeStackFrame>> {
        var result:Array<AttributedScopeStackFrame> = [];
        var self:Null<AttributedScopeStack> = this;

        while (self != null && self != base) {
            var ext = self.scopePath.getExtensionIfDefined(self.parent != null ? self.parent.scopePath : null);
            result.push(new AttributedScopeStackFrame(self.tokenAttributes, ext));
            self = self.parent;
        }
        if (self == base) {
            result.reverse();
            return result;
        }
        return null;
    }
}

class AttributedScopeStackFrame {
    public final encodedTokenAttributes:Int;
    public final scopeNames:Array<String>;

    public function new(encodedTokenAttributes:Int, scopeNames:Array<String>) {
        this.encodedTokenAttributes = encodedTokenAttributes;
        this.scopeNames = scopeNames;
    }
}

/**
 * Represents a "pushed" state on the stack (as a linked list element).
 */
class StateStackImpl implements StateStack {
    // TODO remove me
    public static final NULL = new StateStackImpl(null, 0, 0, 0, false, null, null, null);

    /**
     * The position on the current line where this state was pushed.
     * This is relevant only while tokenizing a line, to detect endless loops.
     * Its value is meaningless across lines.
     */
    var _enterPos:Int;

    /**
     * The captured anchor position when this stack element was pushed.
     * This is relevant only while tokenizing a line, to restore the anchor position when popping.
     * Its value is meaningless across lines.
     */
    var _anchorPos:Int;

    /**
     * The depth of the stack.
     */
    public var depth(default, null):Int;

    /**
     * The previous state on the stack (or null for the root state).
     */
    public final parent:Null<StateStackImpl>;

    /**
     * The state (rule) that this element represents.
     */
    final ruleId:RuleId;

    /**
     * The state has entered and captured \n. This means that the next line should have an anchorPosition of 0.
     */
    public final beginRuleCapturedEOL:Bool;

    /**
     * The "pop" (end) condition for this state in case that it was dynamically generated through captured text.
     */
    public final endRule:Null<String>;

    /**
     * The list of scopes containing the "name" for this state.
     */
    public final nameScopesList:Null<AttributedScopeStack>;

    /**
     * The list of scopes containing the "contentName" (besides "name") for this state.
     * This list **must** contain as an element `scopeName`.
     */
    public final contentNameScopesList:Null<AttributedScopeStack>;

    /**
     * Invariant:
     * ```
     * if (contentNameScopesList !== nameScopesList && contentNameScopesList?.parent !== nameScopesList) {
     * 	throw new Error();
     * }
     * if (this.parent && !nameScopesList.extends(this.parent.contentNameScopesList)) {
     * 	throw new Error();
     * }
     * ```
     */
    public function new(parent:Null<StateStackImpl>, ruleId:RuleId, enterPos:Int, anchorPos:Int, beginRuleCapturedEOL:Bool, endRule:Null<String>,
            nameScopesList:Null<AttributedScopeStack>, contentNameScopesList:Null<AttributedScopeStack>) {
        this.parent = parent;
        this.ruleId = ruleId;
        this.beginRuleCapturedEOL = beginRuleCapturedEOL;
        this.endRule = endRule;
        this.nameScopesList = nameScopesList;
        this.contentNameScopesList = contentNameScopesList;
        this.depth = parent != null ? parent.depth + 1 : 1;
        this._enterPos = enterPos;
        this._anchorPos = anchorPos;
    }

    public function equals(other:StateStack):Bool {
        if (other == null) {
            return false;
        }
        return StateStackImpl._equals(this, cast other);
    }

    static function _equals(a:StateStackImpl, b:StateStackImpl):Bool {
        if (a == b) {
            return true;
        }
        if (!_structuralEquals(a, b)) {
            return false;
        }
        return AttributedScopeStack.equalsStacks(a.contentNameScopesList, b.contentNameScopesList);
    }

    /**
     * A structural equals check. Does not take into account `scopes`.
     */
    static function _structuralEquals(a:Null<StateStackImpl>, b:Null<StateStackImpl>):Bool {
        do {
            if (a == b) {
                return true;
            }

            if (a == null && b == null) {
                // End of list reached for both
                return true;
            }

            if (a == null || b == null) {
                // End of list reached only for one
                return false;
            }

            if (a.depth != b.depth || a.ruleId != b.ruleId || a.endRule != b.endRule) {
                return false;
            }

            // Go to previous pair
            a = a.parent;
            b = b.parent;
        } while (true);
    }

    public function clone():StateStack {
        return this;
    }

    static function _reset(el:Null<StateStackImpl>):Void {
        while (el != null) {
            el._enterPos = -1;
            el._anchorPos = -1;
            el = el.parent;
        }
    }

    public function reset():Void {
        StateStackImpl._reset(this);
    }

    public inline function pop():Null<StateStackImpl> {
        return parent;
    }

    public function safePop():StateStackImpl {
        if (parent != null) {
            return parent;
        }
        return this;
    }

    public function push(ruleId:RuleId, enterPos:Int, anchorPos:Int, beginRuleCapturedEOL:Bool, endRule:Null<String>, nameScopesList:Null<AttributedScopeStack>,
            contentNameScopesList:Null<AttributedScopeStack>):StateStackImpl {
        return new StateStackImpl(this, ruleId, enterPos, anchorPos, beginRuleCapturedEOL, endRule, nameScopesList, contentNameScopesList);
    }

    public inline function getEnterPos():Int {
        return _enterPos;
    }

    public inline function getAnchorPos():Int {
        return _anchorPos;
    }

    public inline function getRule(grammar:IRuleRegistry):Rule {
        return grammar.getRule(ruleId);
    }

    /** The rule id of this state. */
    public inline function getRuleId():RuleId {
        return ruleId;
    }

    public function toString():String {
        var r:Array<String> = [];
        _writeString(r, 0);
        return '[' + r.join(',') + ']';
    }

    function _writeString(res:Array<String>, outIndex:Int):Int {
        if (parent != null) {
            outIndex = parent._writeString(res, outIndex);
        }

        res[outIndex++] = '(' + ruleId + ', ' + (nameScopesList != null ? nameScopesList.toString() : 'undefined') + ', '
            + (contentNameScopesList != null ? contentNameScopesList.toString() : 'undefined') + ')';

        return outIndex;
    }

    public function withContentNameScopesList(contentNameScopeStack:AttributedScopeStack):StateStackImpl {
        if (contentNameScopesList == contentNameScopeStack) {
            return this;
        }
        return parent.push(ruleId, _enterPos, _anchorPos, beginRuleCapturedEOL, endRule, nameScopesList, contentNameScopeStack);
    }

    public function withEndRule(endRule:String):StateStackImpl {
        if (this.endRule == endRule) {
            return this;
        }
        return new StateStackImpl(parent, ruleId, _enterPos, _anchorPos, beginRuleCapturedEOL, endRule, nameScopesList, contentNameScopesList);
    }

    // Used to warn of endless loops
    public function hasSameRuleAs(other:StateStackImpl):Bool {
        var el:Null<StateStackImpl> = this;
        while (el != null && el._enterPos == other._enterPos) {
            if (el.ruleId == other.ruleId) {
                return true;
            }
            el = el.parent;
        }
        return false;
    }

    public function toStateStackFrame():StateStackFrame {
        var names = nameScopesList != null ? nameScopesList.getExtensionIfDefined(parent != null ? parent.nameScopesList : null) : null;
        var contentNames = contentNameScopesList != null ? contentNameScopesList.getExtensionIfDefined(nameScopesList) : null;
        return new StateStackFrame(Rules.ruleIdToNumber(ruleId), null, null, beginRuleCapturedEOL, endRule, names != null ? names : [],
            contentNames != null ? contentNames : []);
    }

    public static function pushFrame(self:Null<StateStackImpl>, frame:StateStackFrame):StateStackImpl {
        var namesScopeList = AttributedScopeStack.fromExtension(self != null ? self.nameScopesList : null, frame.nameScopesList);
        return new StateStackImpl(self, Rules.ruleIdFromNumber(frame.ruleId), frame.enterPos != null ? frame.enterPos : -1,
            frame.anchorPos != null ? frame.anchorPos : -1, frame.beginRuleCapturedEOL, frame.endRule, namesScopeList,
            AttributedScopeStack.fromExtension(namesScopeList, frame.contentNameScopesList));
    }
}

class StateStackFrame {
    public final ruleId:Int;
    public final enterPos:Null<Int>;
    public final anchorPos:Null<Int>;
    public final beginRuleCapturedEOL:Bool;
    public final endRule:Null<String>;
    public final nameScopesList:Array<AttributedScopeStackFrame>;

    /**
     * on top of nameScopesList
     */
    public final contentNameScopesList:Array<AttributedScopeStackFrame>;

    public function new(ruleId:Int, enterPos:Null<Int>, anchorPos:Null<Int>, beginRuleCapturedEOL:Bool, endRule:Null<String>,
            nameScopesList:Array<AttributedScopeStackFrame>, contentNameScopesList:Array<AttributedScopeStackFrame>) {
        this.ruleId = ruleId;
        this.enterPos = enterPos;
        this.anchorPos = anchorPos;
        this.beginRuleCapturedEOL = beginRuleCapturedEOL;
        this.endRule = endRule;
        this.nameScopesList = nameScopesList;
        this.contentNameScopesList = contentNameScopesList;
    }
}

class BalancedBracketSelectors {
    final balancedBracketScopes:Array<Matcher<Array<String>>>;
    final unbalancedBracketScopes:Array<Matcher<Array<String>>>;

    var allowAny = false;

    public function new(balancedBracketScopes:Array<String>, unbalancedBracketScopes:Array<String>) {
        this.balancedBracketScopes = [];
        for (selector in balancedBracketScopes) {
            if (selector == '*') {
                this.allowAny = true;
                continue;
            }
            for (m in Matchers.createMatchers(selector, GrammarTools.nameMatcher)) {
                this.balancedBracketScopes.push(m.matcher);
            }
        }
        this.unbalancedBracketScopes = [];
        for (selector in unbalancedBracketScopes) {
            for (m in Matchers.createMatchers(selector, GrammarTools.nameMatcher)) {
                this.unbalancedBracketScopes.push(m.matcher);
            }
        }
    }

    public var matchesAlways(get, never):Bool;

    inline function get_matchesAlways():Bool {
        return allowAny && unbalancedBracketScopes.length == 0;
    }

    public var matchesNever(get, never):Bool;

    inline function get_matchesNever():Bool {
        return balancedBracketScopes.length == 0 && !allowAny;
    }

    public function match(scopes:Array<String>):Bool {
        for (excluder in unbalancedBracketScopes) {
            if (excluder(scopes)) {
                return false;
            }
        }

        for (includer in balancedBracketScopes) {
            if (includer(scopes)) {
                return true;
            }
        }
        return allowAny;
    }
}

class LineTokens {
    final _emitBinaryTokens:Bool;

    /**
     * used only if `_emitBinaryTokens` is false.
     */
    final _tokens:Array<IToken>;

    /**
     * used only if `_emitBinaryTokens` is true.
     */
    final _binaryTokens:Array<Int>;

    var _lastTokenEndIndex:Int;

    final _tokenTypeOverrides:Array<TokenTypeMatcher>;

    final balancedBracketSelectors:Null<BalancedBracketSelectors>;

    public function new(emitBinaryTokens:Bool, lineText:String, tokenTypeOverrides:Array<TokenTypeMatcher>,
            balancedBracketSelectors:Null<BalancedBracketSelectors>) {
        this._emitBinaryTokens = emitBinaryTokens;
        this._tokenTypeOverrides = tokenTypeOverrides;
        this.balancedBracketSelectors = balancedBracketSelectors;
        this._tokens = [];
        this._binaryTokens = [];
        this._lastTokenEndIndex = 0;
    }

    public inline function produce(stack:StateStackImpl, endIndex:Int):Void {
        produceFromScopes(stack.contentNameScopesList, endIndex);
    }

    public function produceFromScopes(scopesList:Null<AttributedScopeStack>, endIndex:Int):Void {
        if (_lastTokenEndIndex >= endIndex) {
            return;
        }

        if (_emitBinaryTokens) {
            var metadata = scopesList != null ? scopesList.tokenAttributes : 0;
            var containsBalancedBrackets = false;
            if (balancedBracketSelectors != null && balancedBracketSelectors.matchesAlways) {
                containsBalancedBrackets = true;
            }

            if (_tokenTypeOverrides.length > 0
                || (balancedBracketSelectors != null && !balancedBracketSelectors.matchesAlways && !balancedBracketSelectors.matchesNever)) {
                // Only generate scope array when required to improve performance
                var scopes = scopesList != null ? scopesList.getScopeNames() : [];
                for (tokenType in _tokenTypeOverrides) {
                    if (tokenType.matcher(scopes)) {
                        metadata = EncodedTokenAttributes.set(metadata, 0, EncodedTokenAttributes.toOptionalTokenType(tokenType.type), -1, FontStyle.NotSet, 0, 0);
                    }
                }
                if (balancedBracketSelectors != null) {
                    containsBalancedBrackets = balancedBracketSelectors.match(scopes);
                }
            }

            if (containsBalancedBrackets) {
                metadata = EncodedTokenAttributes.set(metadata, 0, OptionalStandardTokenType.NotSet, 1, FontStyle.NotSet, 0, 0);
            }

            if (_binaryTokens.length > 0 && _binaryTokens[_binaryTokens.length - 1] == metadata) {
                // no need to push a token with the same metadata
                _lastTokenEndIndex = endIndex;
                return;
            }

            _binaryTokens.push(_lastTokenEndIndex);
            _binaryTokens.push(metadata);

            _lastTokenEndIndex = endIndex;
            return;
        }

        var scopes = scopesList != null ? scopesList.getScopeNames() : [];

        _tokens.push(new IToken(_lastTokenEndIndex, endIndex, scopes));

        _lastTokenEndIndex = endIndex;
    }

    public function getResult(stack:StateStackImpl, lineLength:Int):Array<IToken> {
        if (_tokens.length > 0 && _tokens[_tokens.length - 1].startIndex == lineLength - 1) {
            // pop produced token for newline
            _tokens.pop();
        }

        if (_tokens.length == 0) {
            _lastTokenEndIndex = -1;
            produce(stack, lineLength);
            _tokens[_tokens.length - 1].startIndex = 0;
        }

        return _tokens;
    }

    public function getBinaryResult(stack:StateStackImpl, lineLength:Int):haxe.io.UInt32Array {
        if (_binaryTokens.length > 0 && _binaryTokens[_binaryTokens.length - 2] == lineLength - 1) {
            // pop produced token for newline
            _binaryTokens.pop();
            _binaryTokens.pop();
        }

        if (_binaryTokens.length == 0) {
            _lastTokenEndIndex = -1;
            produce(stack, lineLength);
            _binaryTokens[_binaryTokens.length - 2] = 0;
        }

        var result = new haxe.io.UInt32Array(_binaryTokens.length);
        for (i in 0..._binaryTokens.length) {
            result[i] = _binaryTokens[i];
        }

        return result;
    }
}
