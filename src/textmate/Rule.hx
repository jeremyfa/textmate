// Ported from vscode-textmate 9.2.0: src/rule.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.OnigLib;
import textmate.RawGrammar;
import textmate.Utils.RegexSource;
import textmate.grammar.GrammarDependencies;

/**
 * Rule ids are positive integers. `endRuleId` (-1) and `whileRuleId` (-2)
 * are special values in compiled rules.
 */
typedef RuleId = Int;

interface IRuleRegistry {
    function getRule(ruleId:RuleId):Rule;
    function registerRule<T:Rule>(factory:(RuleId) -> T):T;
}

interface IGrammarRegistry {
    function getExternalGrammar(scopeName:String, ?repository:IRawRepository):Null<IRawGrammar>;
}

interface IRuleFactoryHelper extends IRuleRegistry extends IGrammarRegistry {}

/**
 * What `compile` and `compileAG` need: `IRuleRegistry & IOnigLib`.
 */
interface IRuleCompileHelper extends IRuleRegistry extends IOnigLib {}

class Rules {
    // This is a special constant to indicate that the end regexp matched.
    public static inline var endRuleId = -1;

    // This is a special constant to indicate that the while regexp matched.
    public static inline var whileRuleId = -2;

    public static inline function ruleIdFromNumber(id:Int):RuleId {
        return id;
    }

    public static inline function ruleIdToNumber(id:RuleId):Int {
        return id;
    }

    /** `/\\(\d+)/.test(source)` */
    public static function hasBackReferences(source:Null<String>):Bool {
        if (source == null) {
            return false;
        }
        var len = source.length;
        for (i in 0...len - 1) {
            if (StringTools.fastCodeAt(source, i) == '\\'.code) {
                var c = StringTools.fastCodeAt(source, i + 1);
                if (c >= '0'.code && c <= '9'.code) {
                    return true;
                }
            }
        }
        return false;
    }
}

abstract class Rule {
    public final location:Null<ILocation>;
    public final id:RuleId;

    final _nameIsCapturing:Bool;
    final _name:Null<String>;

    final _contentNameIsCapturing:Bool;
    final _contentName:Null<String>;

    public function new(location:Null<ILocation>, id:RuleId, name:Null<String>, contentName:Null<String>) {
        this.location = location;
        this.id = id;
        this._name = (name == null || name.length == 0) ? null : name;
        this._nameIsCapturing = RegexSource.hasCaptures(this._name);
        this._contentName = (contentName == null || contentName.length == 0) ? null : contentName;
        this._contentNameIsCapturing = RegexSource.hasCaptures(this._contentName);
    }

    public abstract function dispose():Void;

    public var debugName(get, never):String;

    function get_debugName():String {
        var location = this.location != null ? Utils.basename(this.location.filename != null ? this.location.filename : 'null') + ':' + this.location.line : 'unknown';
        var className = Type.getClassName(Type.getClass(this));
        var dot = className.lastIndexOf('.');
        if (dot != -1) {
            className = className.substring(dot + 1);
        }
        return '$className#$id @ $location';
    }

    public function getName(lineText:Null<String>, captureIndices:Null<Array<IOnigCaptureIndex>>):Null<String> {
        if (!_nameIsCapturing || _name == null || lineText == null || captureIndices == null) {
            return _name;
        }
        return RegexSource.replaceCaptures(_name, lineText, captureIndices);
    }

    public function getContentName(lineText:String, captureIndices:Array<IOnigCaptureIndex>):Null<String> {
        if (!_contentNameIsCapturing || _contentName == null) {
            return _contentName;
        }
        return RegexSource.replaceCaptures(_contentName, lineText, captureIndices);
    }

    public abstract function collectPatterns(grammar:IRuleRegistry, out:RegExpSourceList):Void;

    public abstract function compile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule;

    public abstract function compileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule;
}

class ICompilePatternsResult {
    public final patterns:Array<RuleId>;
    public final hasMissingPatterns:Bool;

    public function new(patterns:Array<RuleId>, hasMissingPatterns:Bool) {
        this.patterns = patterns;
        this.hasMissingPatterns = hasMissingPatterns;
    }
}

class CaptureRule extends Rule {
    /** A rule id, or 0. */
    public final retokenizeCapturedWithRuleId:RuleId;

    public function new(location:Null<ILocation>, id:RuleId, name:Null<String>, contentName:Null<String>, retokenizeCapturedWithRuleId:RuleId) {
        super(location, id, name, contentName);
        this.retokenizeCapturedWithRuleId = retokenizeCapturedWithRuleId;
    }

    public function dispose():Void {
        // nothing to dispose
    }

    public function collectPatterns(grammar:IRuleRegistry, out:RegExpSourceList):Void {
        throw 'Not supported!';
    }

    public function compile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule {
        throw 'Not supported!';
    }

    public function compileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        throw 'Not supported!';
    }
}

class MatchRule extends Rule {
    final _match:RegExpSource;

    public final captures:Array<Null<CaptureRule>>;

    var _cachedCompiledPatterns:Null<RegExpSourceList>;

    public function new(location:Null<ILocation>, id:RuleId, name:Null<String>, match:String, captures:Array<Null<CaptureRule>>) {
        super(location, id, name, null);
        this._match = new RegExpSource(match, this.id);
        this.captures = captures;
        this._cachedCompiledPatterns = null;
    }

    public function dispose():Void {
        if (_cachedCompiledPatterns != null) {
            _cachedCompiledPatterns.dispose();
            _cachedCompiledPatterns = null;
        }
    }

    public var debugMatchRegExp(get, never):String;

    function get_debugMatchRegExp():String {
        return '${_match.source}';
    }

    public function collectPatterns(grammar:IRuleRegistry, out:RegExpSourceList):Void {
        out.push(_match);
    }

    public function compile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule {
        return _getCachedCompiledPatterns(grammar).compile(grammar);
    }

    public function compileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return _getCachedCompiledPatterns(grammar).compileAG(grammar, allowA, allowG);
    }

    function _getCachedCompiledPatterns(grammar:IRuleCompileHelper):RegExpSourceList {
        if (_cachedCompiledPatterns == null) {
            _cachedCompiledPatterns = new RegExpSourceList();
            collectPatterns(grammar, _cachedCompiledPatterns);
        }
        return _cachedCompiledPatterns;
    }
}

class IncludeOnlyRule extends Rule {
    public final hasMissingPatterns:Bool;
    public final patterns:Array<RuleId>;

    var _cachedCompiledPatterns:Null<RegExpSourceList>;

    public function new(location:Null<ILocation>, id:RuleId, name:Null<String>, contentName:Null<String>, patterns:ICompilePatternsResult) {
        super(location, id, name, contentName);
        this.patterns = patterns.patterns;
        this.hasMissingPatterns = patterns.hasMissingPatterns;
        this._cachedCompiledPatterns = null;
    }

    public function dispose():Void {
        if (_cachedCompiledPatterns != null) {
            _cachedCompiledPatterns.dispose();
            _cachedCompiledPatterns = null;
        }
    }

    public function collectPatterns(grammar:IRuleRegistry, out:RegExpSourceList):Void {
        for (pattern in patterns) {
            var rule = grammar.getRule(pattern);
            rule.collectPatterns(grammar, out);
        }
    }

    public function compile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule {
        return _getCachedCompiledPatterns(grammar).compile(grammar);
    }

    public function compileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return _getCachedCompiledPatterns(grammar).compileAG(grammar, allowA, allowG);
    }

    function _getCachedCompiledPatterns(grammar:IRuleCompileHelper):RegExpSourceList {
        if (_cachedCompiledPatterns == null) {
            _cachedCompiledPatterns = new RegExpSourceList();
            collectPatterns(grammar, _cachedCompiledPatterns);
        }
        return _cachedCompiledPatterns;
    }
}

class BeginEndRule extends Rule {
    final _begin:RegExpSource;

    public final beginCaptures:Array<Null<CaptureRule>>;

    final _end:RegExpSource;

    public final endHasBackReferences:Bool;
    public final endCaptures:Array<Null<CaptureRule>>;
    public final applyEndPatternLast:Bool;
    public final hasMissingPatterns:Bool;
    public final patterns:Array<RuleId>;

    var _cachedCompiledPatterns:Null<RegExpSourceList>;

    public function new(location:Null<ILocation>, id:RuleId, name:Null<String>, contentName:Null<String>, begin:String, beginCaptures:Array<Null<CaptureRule>>,
            end:Null<String>, endCaptures:Array<Null<CaptureRule>>, applyEndPatternLast:Bool, patterns:ICompilePatternsResult) {
        super(location, id, name, contentName);
        this._begin = new RegExpSource(begin, this.id);
        this.beginCaptures = beginCaptures;
        this._end = new RegExpSource((end != null && end.length > 0) ? end : '\u{FFFF}', -1);
        this.endHasBackReferences = this._end.hasBackReferences;
        this.endCaptures = endCaptures;
        this.applyEndPatternLast = applyEndPatternLast;
        this.patterns = patterns.patterns;
        this.hasMissingPatterns = patterns.hasMissingPatterns;
        this._cachedCompiledPatterns = null;
    }

    public function dispose():Void {
        if (_cachedCompiledPatterns != null) {
            _cachedCompiledPatterns.dispose();
            _cachedCompiledPatterns = null;
        }
    }

    public var debugBeginRegExp(get, never):String;

    function get_debugBeginRegExp():String {
        return '${_begin.source}';
    }

    public var debugEndRegExp(get, never):String;

    function get_debugEndRegExp():String {
        return '${_end.source}';
    }

    public function getEndWithResolvedBackReferences(lineText:String, captureIndices:Array<IOnigCaptureIndex>):String {
        return _end.resolveBackReferences(lineText, captureIndices);
    }

    public function collectPatterns(grammar:IRuleRegistry, out:RegExpSourceList):Void {
        out.push(_begin);
    }

    public function compile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule {
        return _getCachedCompiledPatterns(grammar, endRegexSource).compile(grammar);
    }

    public function compileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return _getCachedCompiledPatterns(grammar, endRegexSource).compileAG(grammar, allowA, allowG);
    }

    function _getCachedCompiledPatterns(grammar:IRuleCompileHelper, endRegexSource:Null<String>):RegExpSourceList {
        if (_cachedCompiledPatterns == null) {
            _cachedCompiledPatterns = new RegExpSourceList();

            for (pattern in patterns) {
                var rule = grammar.getRule(pattern);
                rule.collectPatterns(grammar, _cachedCompiledPatterns);
            }

            if (applyEndPatternLast) {
                _cachedCompiledPatterns.push(_end.hasBackReferences ? _end.clone() : _end);
            } else {
                _cachedCompiledPatterns.unshift(_end.hasBackReferences ? _end.clone() : _end);
            }
        }
        if (_end.hasBackReferences) {
            if (applyEndPatternLast) {
                _cachedCompiledPatterns.setSource(_cachedCompiledPatterns.length() - 1, endRegexSource);
            } else {
                _cachedCompiledPatterns.setSource(0, endRegexSource);
            }
        }
        return _cachedCompiledPatterns;
    }
}

class BeginWhileRule extends Rule {
    final _begin:RegExpSource;

    public final beginCaptures:Array<Null<CaptureRule>>;
    public final whileCaptures:Array<Null<CaptureRule>>;

    final _while:RegExpSource;

    public final whileHasBackReferences:Bool;
    public final hasMissingPatterns:Bool;
    public final patterns:Array<RuleId>;

    var _cachedCompiledPatterns:Null<RegExpSourceList>;
    var _cachedCompiledWhilePatterns:Null<RegExpSourceList>;

    public function new(location:Null<ILocation>, id:RuleId, name:Null<String>, contentName:Null<String>, begin:String, beginCaptures:Array<Null<CaptureRule>>,
            _while:String, whileCaptures:Array<Null<CaptureRule>>, patterns:ICompilePatternsResult) {
        super(location, id, name, contentName);
        this._begin = new RegExpSource(begin, this.id);
        this.beginCaptures = beginCaptures;
        this.whileCaptures = whileCaptures;
        this._while = new RegExpSource(_while, Rules.whileRuleId);
        this.whileHasBackReferences = this._while.hasBackReferences;
        this.patterns = patterns.patterns;
        this.hasMissingPatterns = patterns.hasMissingPatterns;
        this._cachedCompiledPatterns = null;
        this._cachedCompiledWhilePatterns = null;
    }

    public function dispose():Void {
        if (_cachedCompiledPatterns != null) {
            _cachedCompiledPatterns.dispose();
            _cachedCompiledPatterns = null;
        }
        if (_cachedCompiledWhilePatterns != null) {
            _cachedCompiledWhilePatterns.dispose();
            _cachedCompiledWhilePatterns = null;
        }
    }

    public var debugBeginRegExp(get, never):String;

    function get_debugBeginRegExp():String {
        return '${_begin.source}';
    }

    public var debugWhileRegExp(get, never):String;

    function get_debugWhileRegExp():String {
        return '${_while.source}';
    }

    public function getWhileWithResolvedBackReferences(lineText:String, captureIndices:Array<IOnigCaptureIndex>):String {
        return _while.resolveBackReferences(lineText, captureIndices);
    }

    public function collectPatterns(grammar:IRuleRegistry, out:RegExpSourceList):Void {
        out.push(_begin);
    }

    public function compile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule {
        return _getCachedCompiledPatterns(grammar).compile(grammar);
    }

    public function compileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return _getCachedCompiledPatterns(grammar).compileAG(grammar, allowA, allowG);
    }

    function _getCachedCompiledPatterns(grammar:IRuleCompileHelper):RegExpSourceList {
        if (_cachedCompiledPatterns == null) {
            _cachedCompiledPatterns = new RegExpSourceList();

            for (pattern in patterns) {
                var rule = grammar.getRule(pattern);
                rule.collectPatterns(grammar, _cachedCompiledPatterns);
            }
        }
        return _cachedCompiledPatterns;
    }

    public function compileWhile(grammar:IRuleCompileHelper, endRegexSource:Null<String>):CompiledRule {
        return _getCachedCompiledWhilePatterns(grammar, endRegexSource).compile(grammar);
    }

    public function compileWhileAG(grammar:IRuleCompileHelper, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return _getCachedCompiledWhilePatterns(grammar, endRegexSource).compileAG(grammar, allowA, allowG);
    }

    function _getCachedCompiledWhilePatterns(grammar:IRuleCompileHelper, endRegexSource:Null<String>):RegExpSourceList {
        if (_cachedCompiledWhilePatterns == null) {
            _cachedCompiledWhilePatterns = new RegExpSourceList();
            _cachedCompiledWhilePatterns.push(_while.hasBackReferences ? _while.clone() : _while);
        }
        if (_while.hasBackReferences) {
            _cachedCompiledWhilePatterns.setSource(0, (endRegexSource != null && endRegexSource.length > 0) ? endRegexSource : '\u{FFFF}');
        }
        return _cachedCompiledWhilePatterns;
    }
}

class RuleFactory {
    public static function createCaptureRule(helper:IRuleFactoryHelper, location:Null<ILocation>, name:Null<String>, contentName:Null<String>,
            retokenizeCapturedWithRuleId:RuleId):CaptureRule {
        return helper.registerRule((id) -> new CaptureRule(location, id, name, contentName, retokenizeCapturedWithRuleId));
    }

    public static function getCompiledRuleId(desc:IRawRule, helper:IRuleFactoryHelper, repository:IRawRepository):RuleId {
        if (desc.id == 0) {
            helper.registerRule((id) -> {
                desc.id = id;

                if (desc.match != null && desc.match.length > 0) {
                    return (new MatchRule(desc.vscodeTextmateLocation, desc.id, desc.name, desc.match,
                        RuleFactory._compileCaptures(desc.captures, helper, repository)) : Rule);
                }

                if (!desc.hasBegin) {
                    if (desc.repository != null) {
                        repository = Utils.mergeObjects(new OrderedMap<IRawRule>(), [repository, desc.repository]);
                    }
                    var patterns = desc.patterns;
                    if (patterns == null && desc.include != null && desc.include.length > 0) {
                        var include = new IRawRule();
                        include.include = desc.include;
                        patterns = [include];
                    }
                    return (new IncludeOnlyRule(desc.vscodeTextmateLocation, desc.id, desc.name, desc.contentName,
                        RuleFactory._compilePatterns(patterns, helper, repository)) : Rule);
                }

                if (desc.while_ != null && desc.while_.length > 0) {
                    return (new BeginWhileRule(desc.vscodeTextmateLocation, desc.id, desc.name, desc.contentName, desc.begin,
                        RuleFactory._compileCaptures(desc.beginCaptures != null ? desc.beginCaptures : desc.captures, helper, repository), desc.while_,
                        RuleFactory._compileCaptures(desc.whileCaptures != null ? desc.whileCaptures : desc.captures, helper, repository),
                        RuleFactory._compilePatterns(desc.patterns, helper, repository)) : Rule);
                }

                return (new BeginEndRule(desc.vscodeTextmateLocation, desc.id, desc.name, desc.contentName, desc.begin,
                    RuleFactory._compileCaptures(desc.beginCaptures != null ? desc.beginCaptures : desc.captures, helper, repository), desc.end,
                    RuleFactory._compileCaptures(desc.endCaptures != null ? desc.endCaptures : desc.captures, helper, repository), desc.applyEndPatternLast,
                    RuleFactory._compilePatterns(desc.patterns, helper, repository)) : Rule);
            });
        }

        return desc.id;
    }

    static function parseIntLikeJs(s:String):Int {
        // parseInt(s, 10): leading whitespace, optional sign, then digits. NaN is reported as -1.
        var i = 0;
        var len = s.length;
        while (i < len && Utils.isJsWhitespace(StringTools.fastCodeAt(s, i))) {
            i++;
        }
        var negative = false;
        if (i < len && (StringTools.fastCodeAt(s, i) == '+'.code || StringTools.fastCodeAt(s, i) == '-'.code)) {
            negative = StringTools.fastCodeAt(s, i) == '-'.code;
            i++;
        }
        var start = i;
        var value = 0.0;
        while (i < len) {
            var c = StringTools.fastCodeAt(s, i);
            if (c < '0'.code || c > '9'.code) {
                break;
            }
            value = value * 10 + (c - '0'.code);
            i++;
        }
        if (i == start) {
            return -1;
        }
        if (negative) {
            return value == 0 ? 0 : -1;
        }
        return value > 100000.0 ? 100000 : Std.int(value);
    }

    static function _compileCaptures(captures:Null<IRawCaptures>, helper:IRuleFactoryHelper, repository:IRawRepository):Array<Null<CaptureRule>> {
        var r:Array<Null<CaptureRule>> = [];

        if (captures != null) {
            // Find the maximum capture id
            var maximumCaptureId = 0;
            for (captureId in captures.keys()) {
                var numericCaptureId = parseIntLikeJs(captureId);
                if (numericCaptureId > maximumCaptureId) {
                    maximumCaptureId = numericCaptureId;
                }
            }

            // Initialize result
            for (i in 0...maximumCaptureId + 1) {
                r[i] = null;
            }

            // Fill out result
            for (captureId in captures.keys()) {
                var numericCaptureId = parseIntLikeJs(captureId);
                var capture = captures.get(captureId);
                var retokenizeCapturedWithRuleId:RuleId = 0;
                if (capture != null && capture.patterns != null) {
                    retokenizeCapturedWithRuleId = RuleFactory.getCompiledRuleId(capture, helper, repository);
                }
                var rule = RuleFactory.createCaptureRule(helper, capture != null ? capture.vscodeTextmateLocation : null, capture != null ? capture.name : null,
                    capture != null ? capture.contentName : null, retokenizeCapturedWithRuleId);
                if (numericCaptureId >= 0) {
                    r[numericCaptureId] = rule;
                }
            }
        }

        return r;
    }

    static function _compilePatterns(patterns:Null<Array<IRawRule>>, helper:IRuleFactoryHelper, repository:IRawRepository):ICompilePatternsResult {
        var r:Array<RuleId> = [];

        if (patterns != null) {
            for (i in 0...patterns.length) {
                var pattern = patterns[i];
                if (pattern == null) {
                    continue;
                }
                var ruleId:RuleId = -1;

                if (pattern.include != null && pattern.include.length > 0) {
                    var reference = GrammarDependencies.parseInclude(pattern.include);

                    switch reference.kind {
                        case Base | Self:
                            var target = repository.get(pattern.include);
                            if (target != null) {
                                ruleId = RuleFactory.getCompiledRuleId(target, helper, repository);
                            }

                        case RelativeReference:
                            // Local include found in `repository`
                            var localIncludedRule = repository.get(reference.ruleName);
                            if (localIncludedRule != null) {
                                ruleId = RuleFactory.getCompiledRuleId(localIncludedRule, helper, repository);
                            } else {
                                // console.warn('CANNOT find rule for scopeName: ' + pattern.include + ', I am: ', repository["$base"].name);
                            }

                        case TopLevelReference | TopLevelRepositoryReference:
                            var externalGrammarName = reference.scopeName;
                            var externalGrammarInclude = reference.kind == TopLevelRepositoryReference ? reference.ruleName : null;

                            // External include
                            var externalGrammar = helper.getExternalGrammar(externalGrammarName, repository);

                            if (externalGrammar != null) {
                                if (externalGrammarInclude != null && externalGrammarInclude.length > 0) {
                                    var externalIncludedRule = externalGrammar.repository.get(externalGrammarInclude);
                                    if (externalIncludedRule != null) {
                                        ruleId = RuleFactory.getCompiledRuleId(externalIncludedRule, helper, externalGrammar.repository);
                                    } else {
                                        // console.warn('CANNOT find rule for scopeName: ' + pattern.include + ', I am: ', repository["$base"].name);
                                    }
                                } else {
                                    ruleId = RuleFactory.getCompiledRuleId(externalGrammar.repository.get("$self"), helper, externalGrammar.repository);
                                }
                            } else {
                                // console.warn('CANNOT find grammar for scopeName: ' + pattern.include + ', I am: ', repository["$base"].name);
                            }
                    }
                } else {
                    ruleId = RuleFactory.getCompiledRuleId(pattern, helper, repository);
                }

                if (ruleId != -1) {
                    var rule = helper.getRule(ruleId);

                    var skipRule = false;

                    if (Std.isOfType(rule, IncludeOnlyRule)) {
                        var rule:IncludeOnlyRule = cast rule;
                        if (rule.hasMissingPatterns && rule.patterns.length == 0) {
                            skipRule = true;
                        }
                    } else if (Std.isOfType(rule, BeginEndRule)) {
                        var rule:BeginEndRule = cast rule;
                        if (rule.hasMissingPatterns && rule.patterns.length == 0) {
                            skipRule = true;
                        }
                    } else if (Std.isOfType(rule, BeginWhileRule)) {
                        var rule:BeginWhileRule = cast rule;
                        if (rule.hasMissingPatterns && rule.patterns.length == 0) {
                            skipRule = true;
                        }
                    }

                    if (skipRule) {
                        // console.log('REMOVING RULE ENTIRELY DUE TO EMPTY PATTERNS THAT ARE MISSING');
                        continue;
                    }

                    r.push(ruleId);
                }
            }
        }

        return new ICompilePatternsResult(r, (patterns != null ? patterns.length : 0) != r.length);
    }
}

class RegExpSource {
    public var source:String;
    public final ruleId:RuleId;
    public var hasAnchor:Bool;
    public final hasBackReferences:Bool;

    var _anchorCache:Null<IRegExpSourceAnchorCache>;

    public function new(regExpSource:String, ruleId:RuleId) {
        if (regExpSource != null && regExpSource.length > 0) {
            var len = regExpSource.length;
            var lastPushedPos = 0;
            var output:Null<StringBuf> = null;

            var hasAnchor = false;
            var pos = 0;
            while (pos < len) {
                var ch = StringTools.fastCodeAt(regExpSource, pos);

                if (ch == '\\'.code) {
                    if (pos + 1 < len) {
                        var nextCh = StringTools.fastCodeAt(regExpSource, pos + 1);
                        if (nextCh == 'z'.code) {
                            if (output == null) {
                                output = new StringBuf();
                            }
                            output.addSub(regExpSource, lastPushedPos, pos - lastPushedPos);
                            output.add("$(?!\\n)(?<!\\n)");
                            lastPushedPos = pos + 2;
                        } else if (nextCh == 'A'.code || nextCh == 'G'.code) {
                            hasAnchor = true;
                        }
                        pos++;
                    }
                }
                pos++;
            }

            this.hasAnchor = hasAnchor;
            if (lastPushedPos == 0) {
                // No \z hit
                this.source = regExpSource;
            } else {
                output.addSub(regExpSource, lastPushedPos, len - lastPushedPos);
                this.source = output.toString();
            }
        } else {
            this.hasAnchor = false;
            this.source = regExpSource;
        }

        if (this.hasAnchor) {
            this._anchorCache = this._buildAnchorCache();
        } else {
            this._anchorCache = null;
        }

        this.ruleId = ruleId;
        this.hasBackReferences = Rules.hasBackReferences(this.source);
    }

    public function clone():RegExpSource {
        return new RegExpSource(source, ruleId);
    }

    public function setSource(newSource:String):Void {
        if (source == newSource) {
            return;
        }
        source = newSource;

        if (hasAnchor) {
            _anchorCache = _buildAnchorCache();
        }
    }

    public function resolveBackReferences(lineText:String, captureIndices:Array<IOnigCaptureIndex>):String {
        var capturedValues = [for (capture in captureIndices) lineText.substring(capture.start, capture.end)];
        // this.source.replace(/\\(\d+)/g, (match, g1) => escapeRegExpCharacters(capturedValues[parseInt(g1, 10)] || ''))
        var source = this.source;
        var len = source.length;
        var buf = new StringBuf();
        var last = 0;
        var pos = 0;
        while (pos < len - 1) {
            if (StringTools.fastCodeAt(source, pos) == '\\'.code) {
                var c = StringTools.fastCodeAt(source, pos + 1);
                if (c >= '0'.code && c <= '9'.code) {
                    var start = pos + 1;
                    var end = start;
                    var value = 0.0;
                    while (end < len) {
                        var d = StringTools.fastCodeAt(source, end);
                        if (d < '0'.code || d > '9'.code) {
                            break;
                        }
                        value = value * 10 + (d - '0'.code);
                        end++;
                    }
                    if (pos > last) {
                        buf.addSub(source, last, pos - last);
                    }
                    var index = value >= capturedValues.length ? -1 : Std.int(value);
                    var captured = index >= 0 ? capturedValues[index] : null;
                    buf.add(Utils.escapeRegExpCharacters(captured != null ? captured : ''));
                    pos = end;
                    last = end;
                    continue;
                }
            }
            pos++;
        }
        if (last < len) {
            buf.addSub(source, last, len - last);
        }
        return buf.toString();
    }

    function _buildAnchorCache():IRegExpSourceAnchorCache {
        var A0_G0_result = new StringBuf();
        var A0_G1_result = new StringBuf();
        var A1_G0_result = new StringBuf();
        var A1_G1_result = new StringBuf();

        // Same result as the character by character copy of vscode-textmate,
        // built from slices so that surrogate pairs stay intact on every target.
        var len = source.length;
        var last = 0;
        var pos = 0;
        while (pos < len) {
            var ch = StringTools.fastCodeAt(source, pos);
            if (ch == '\\'.code) {
                if (pos + 1 < len) {
                    var nextCh = StringTools.fastCodeAt(source, pos + 1);
                    if (nextCh == 'A'.code || nextCh == 'G'.code) {
                        var chunk = source.substring(last, pos + 1);
                        A0_G0_result.add(chunk);
                        A0_G1_result.add(chunk);
                        A1_G0_result.add(chunk);
                        A1_G1_result.add(chunk);
                        if (nextCh == 'A'.code) {
                            A0_G0_result.add('\u{FFFF}');
                            A0_G1_result.add('\u{FFFF}');
                            A1_G0_result.add('A');
                            A1_G1_result.add('A');
                        } else {
                            A0_G0_result.add('\u{FFFF}');
                            A0_G1_result.add('G');
                            A1_G0_result.add('\u{FFFF}');
                            A1_G1_result.add('G');
                        }
                        last = pos + 2;
                    }
                    pos++;
                }
            }
            pos++;
        }
        if (last < len) {
            var chunk = source.substring(last, len);
            A0_G0_result.add(chunk);
            A0_G1_result.add(chunk);
            A1_G0_result.add(chunk);
            A1_G1_result.add(chunk);
        }

        return new IRegExpSourceAnchorCache(A0_G0_result.toString(), A0_G1_result.toString(), A1_G0_result.toString(), A1_G1_result.toString());
    }

    public function resolveAnchors(allowA:Bool, allowG:Bool):String {
        if (!hasAnchor || _anchorCache == null) {
            return source;
        }

        if (allowA) {
            if (allowG) {
                return _anchorCache.A1_G1;
            } else {
                return _anchorCache.A1_G0;
            }
        } else {
            if (allowG) {
                return _anchorCache.A0_G1;
            } else {
                return _anchorCache.A0_G0;
            }
        }
    }
}

private class IRegExpSourceAnchorCache {
    public final A0_G0:String;
    public final A0_G1:String;
    public final A1_G0:String;
    public final A1_G1:String;

    public function new(A0_G0:String, A0_G1:String, A1_G0:String, A1_G1:String) {
        this.A0_G0 = A0_G0;
        this.A0_G1 = A0_G1;
        this.A1_G0 = A1_G0;
        this.A1_G1 = A1_G1;
    }
}

class RegExpSourceList {
    final _items:Array<RegExpSource>;
    var _hasAnchors:Bool;
    var _cached:Null<CompiledRule>;
    var _anchorCache_A0_G0:Null<CompiledRule>;
    var _anchorCache_A0_G1:Null<CompiledRule>;
    var _anchorCache_A1_G0:Null<CompiledRule>;
    var _anchorCache_A1_G1:Null<CompiledRule>;

    public function new() {
        _items = [];
        _hasAnchors = false;
        _cached = null;
        _anchorCache_A0_G0 = null;
        _anchorCache_A0_G1 = null;
        _anchorCache_A1_G0 = null;
        _anchorCache_A1_G1 = null;
    }

    public function dispose():Void {
        _disposeCaches();
    }

    function _disposeCaches():Void {
        if (_cached != null) {
            _cached.dispose();
            _cached = null;
        }
        if (_anchorCache_A0_G0 != null) {
            _anchorCache_A0_G0.dispose();
            _anchorCache_A0_G0 = null;
        }
        if (_anchorCache_A0_G1 != null) {
            _anchorCache_A0_G1.dispose();
            _anchorCache_A0_G1 = null;
        }
        if (_anchorCache_A1_G0 != null) {
            _anchorCache_A1_G0.dispose();
            _anchorCache_A1_G0 = null;
        }
        if (_anchorCache_A1_G1 != null) {
            _anchorCache_A1_G1.dispose();
            _anchorCache_A1_G1 = null;
        }
    }

    public function push(item:RegExpSource):Void {
        _items.push(item);
        _hasAnchors = _hasAnchors || item.hasAnchor;
    }

    public function unshift(item:RegExpSource):Void {
        _items.unshift(item);
        _hasAnchors = _hasAnchors || item.hasAnchor;
    }

    public function length():Int {
        return _items.length;
    }

    public function setSource(index:Int, newSource:String):Void {
        if (_items[index].source != newSource) {
            // bust the cache
            _disposeCaches();
            _items[index].setSource(newSource);
        }
    }

    public function compile(onigLib:IOnigLib):CompiledRule {
        if (_cached == null) {
            var regExps = [for (e in _items) e.source];
            _cached = new CompiledRule(onigLib, regExps, [for (e in _items) e.ruleId]);
        }
        return _cached;
    }

    public function compileAG(onigLib:IOnigLib, allowA:Bool, allowG:Bool):CompiledRule {
        if (!_hasAnchors) {
            return compile(onigLib);
        } else {
            if (allowA) {
                if (allowG) {
                    if (_anchorCache_A1_G1 == null) {
                        _anchorCache_A1_G1 = _resolveAnchors(onigLib, allowA, allowG);
                    }
                    return _anchorCache_A1_G1;
                } else {
                    if (_anchorCache_A1_G0 == null) {
                        _anchorCache_A1_G0 = _resolveAnchors(onigLib, allowA, allowG);
                    }
                    return _anchorCache_A1_G0;
                }
            } else {
                if (allowG) {
                    if (_anchorCache_A0_G1 == null) {
                        _anchorCache_A0_G1 = _resolveAnchors(onigLib, allowA, allowG);
                    }
                    return _anchorCache_A0_G1;
                } else {
                    if (_anchorCache_A0_G0 == null) {
                        _anchorCache_A0_G0 = _resolveAnchors(onigLib, allowA, allowG);
                    }
                    return _anchorCache_A0_G0;
                }
            }
        }
    }

    function _resolveAnchors(onigLib:IOnigLib, allowA:Bool, allowG:Bool):CompiledRule {
        var regExps = [for (e in _items) e.resolveAnchors(allowA, allowG)];
        return new CompiledRule(onigLib, regExps, [for (e in _items) e.ruleId]);
    }
}

class CompiledRule {
    final scanner:OnigScanner;
    final regExps:Array<String>;
    final rules:Array<RuleId>;

    public function new(onigLib:IOnigLib, regExps:Array<String>, rules:Array<RuleId>) {
        this.regExps = regExps;
        this.rules = rules;
        this.scanner = onigLib.createOnigScanner(regExps);
    }

    public function dispose():Void {
        scanner.dispose();
    }

    public function toString():String {
        var r:Array<String> = [];
        for (i in 0...rules.length) {
            r.push('   - ' + rules[i] + ': ' + regExps[i]);
        }
        return r.join('\n');
    }

    public function findNextMatchSync(string:OnigString, startPosition:Int, options:Int):Null<IFindNextMatchResult> {
        var result = scanner.findNextMatchSync(string, startPosition, options);
        if (result == null) {
            return null;
        }

        return new IFindNextMatchResult(rules[result.index], result.captureIndices);
    }
}

class IFindNextMatchResult {
    public final ruleId:RuleId;
    public final captureIndices:Array<IOnigCaptureIndex>;

    public inline function new(ruleId:RuleId, captureIndices:Array<IOnigCaptureIndex>) {
        this.ruleId = ruleId;
        this.captureIndices = captureIndices;
    }
}
