// Ported from vscode-textmate 9.2.0: src/grammar/grammarDependencies.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate.grammar;

import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import textmate.RawGrammar;
import textmate.Theme.ScopeName;
import textmate.grammar.Grammar.IGrammarRepository;

/**
 * `TopLevelRuleReference` (ruleName null) or `TopLevelRepositoryRuleReference`.
 */
class AbsoluteRuleReference {
    public final scopeName:ScopeName;
    public final ruleName:Null<String>;

    public function new(scopeName:ScopeName, ruleName:Null<String>) {
        this.scopeName = scopeName;
        this.ruleName = ruleName;
    }

    /** True for a `TopLevelRuleReference`. */
    public inline function isTopLevel():Bool {
        return ruleName == null;
    }

    public function toKey():String {
        return ruleName == null ? scopeName : scopeName + '#' + ruleName;
    }
}

class ExternalReferenceCollector {
    final _references:Array<AbsoluteRuleReference> = [];
    final _seenReferenceKeys = new StringMap<Bool>();

    public var references(get, never):Array<AbsoluteRuleReference>;

    inline function get_references():Array<AbsoluteRuleReference> {
        return _references;
    }

    public final visitedRule = new ObjectMap<IRawRule, Bool>();

    public function new() {}

    public function add(reference:AbsoluteRuleReference):Void {
        var key = reference.toKey();
        if (_seenReferenceKeys.exists(key)) {
            return;
        }
        _seenReferenceKeys.set(key, true);
        _references.push(reference);
    }
}

class ScopeDependencyProcessor {
    public final seenFullScopeRequests = new StringMap<Bool>();
    public final seenPartialScopeRequests = new StringMap<Bool>();
    public var Q:Array<AbsoluteRuleReference>;

    public final repo:IGrammarRepository;
    public final initialScopeName:ScopeName;

    public function new(repo:IGrammarRepository, initialScopeName:ScopeName) {
        this.repo = repo;
        this.initialScopeName = initialScopeName;
        seenFullScopeRequests.set(initialScopeName, true);
        Q = [new AbsoluteRuleReference(initialScopeName, null)];
    }

    public function processQueue():Void {
        var q = Q;
        Q = [];

        var deps = new ExternalReferenceCollector();
        for (dep in q) {
            GrammarDependencies.collectReferencesOfReference(dep, initialScopeName, repo, deps);
        }

        for (dep in deps.references) {
            if (dep.isTopLevel()) {
                if (seenFullScopeRequests.exists(dep.scopeName)) {
                    // already processed
                    continue;
                }
                seenFullScopeRequests.set(dep.scopeName, true);
                Q.push(dep);
            } else {
                if (seenFullScopeRequests.exists(dep.scopeName)) {
                    // already processed in full
                    continue;
                }
                if (seenPartialScopeRequests.exists(dep.toKey())) {
                    // already processed
                    continue;
                }
                seenPartialScopeRequests.set(dep.toKey(), true);
                Q.push(dep);
            }
        }
    }
}

private class Context {
    public final baseGrammar:IRawGrammar;
    public final selfGrammar:IRawGrammar;
    public final repository:Null<IRawRepository>;

    public function new(baseGrammar:IRawGrammar, selfGrammar:IRawGrammar, repository:Null<IRawRepository>) {
        this.baseGrammar = baseGrammar;
        this.selfGrammar = selfGrammar;
        this.repository = repository;
    }
}

enum abstract IncludeReferenceKind(Int) to Int {
    var Base = 0;
    var Self = 1;
    var RelativeReference = 2;
    var TopLevelReference = 3;
    var TopLevelRepositoryReference = 4;
}

class IncludeReference {
    public final kind:IncludeReferenceKind;
    public final scopeName:Null<ScopeName>;
    public final ruleName:Null<String>;

    public function new(kind:IncludeReferenceKind, scopeName:Null<ScopeName>, ruleName:Null<String>) {
        this.kind = kind;
        this.scopeName = scopeName;
        this.ruleName = ruleName;
    }
}

class GrammarDependencies {
    static final BASE_REFERENCE = new IncludeReference(Base, null, null);
    static final SELF_REFERENCE = new IncludeReference(Self, null, null);

    public static function collectReferencesOfReference(reference:AbsoluteRuleReference, baseGrammarScopeName:ScopeName, repo:IGrammarRepository,
            result:ExternalReferenceCollector):Void {
        var selfGrammar = repo.lookup(reference.scopeName);
        if (selfGrammar == null) {
            if (reference.scopeName == baseGrammarScopeName) {
                throw 'No grammar provided for <$baseGrammarScopeName>';
            }
            return;
        }

        var baseGrammar = repo.lookup(baseGrammarScopeName);

        if (reference.isTopLevel()) {
            collectExternalReferencesInTopLevelRule(new Context(baseGrammar, selfGrammar, null), result);
        } else {
            collectExternalReferencesInTopLevelRepositoryRule(reference.ruleName, new Context(baseGrammar, selfGrammar, selfGrammar.repository), result);
        }

        var injections = repo.injections(reference.scopeName);
        if (injections != null) {
            for (injection in injections) {
                result.add(new AbsoluteRuleReference(injection, null));
            }
        }
    }

    static function collectExternalReferencesInTopLevelRepositoryRule(ruleName:String, context:Context, result:ExternalReferenceCollector):Void {
        if (context.repository != null) {
            var rule = context.repository.get(ruleName);
            if (rule != null) {
                collectExternalReferencesInRules([rule], context, result);
            }
        }
    }

    static function collectExternalReferencesInTopLevelRule(context:Context, result:ExternalReferenceCollector):Void {
        if (context.selfGrammar.patterns != null) {
            collectExternalReferencesInRules(context.selfGrammar.patterns, new Context(context.baseGrammar, context.selfGrammar, context.selfGrammar.repository),
                result);
        }
        if (context.selfGrammar.injections != null) {
            var values = [for (key in context.selfGrammar.injections.keys()) context.selfGrammar.injections.get(key)];
            collectExternalReferencesInRules(values, new Context(context.baseGrammar, context.selfGrammar, context.selfGrammar.repository), result);
        }
    }

    static function collectExternalReferencesInRules(rules:Array<IRawRule>, context:Context, result:ExternalReferenceCollector):Void {
        for (rule in rules) {
            if (rule == null) {
                continue;
            }
            if (result.visitedRule.exists(rule)) {
                continue;
            }
            result.visitedRule.set(rule, true);

            var patternRepository = rule.repository != null ? Utils.mergeObjects(new OrderedMap<IRawRule>(), [context.repository, rule.repository]) : context.repository;

            if (rule.patterns != null) {
                collectExternalReferencesInRules(rule.patterns, new Context(context.baseGrammar, context.selfGrammar, patternRepository), result);
            }

            var include = rule.include;

            if (include == null || include.length == 0) {
                continue;
            }

            var reference = parseInclude(include);

            switch reference.kind {
                case Base:
                    collectExternalReferencesInTopLevelRule(new Context(context.baseGrammar, context.baseGrammar, context.repository), result);
                case Self:
                    collectExternalReferencesInTopLevelRule(context, result);
                case RelativeReference:
                    collectExternalReferencesInTopLevelRepositoryRule(reference.ruleName,
                        new Context(context.baseGrammar, context.selfGrammar, patternRepository), result);
                case TopLevelReference | TopLevelRepositoryReference:
                    var selfGrammar = reference.scopeName == context.selfGrammar.scopeName ? context.selfGrammar : reference.scopeName == context.baseGrammar.scopeName ? context.baseGrammar : null;
                    if (selfGrammar != null) {
                        var newContext = new Context(context.baseGrammar, selfGrammar, patternRepository);
                        if (reference.kind == TopLevelRepositoryReference) {
                            collectExternalReferencesInTopLevelRepositoryRule(reference.ruleName, newContext, result);
                        } else {
                            collectExternalReferencesInTopLevelRule(newContext, result);
                        }
                    } else {
                        if (reference.kind == TopLevelRepositoryReference) {
                            result.add(new AbsoluteRuleReference(reference.scopeName, reference.ruleName));
                        } else {
                            result.add(new AbsoluteRuleReference(reference.scopeName, null));
                        }
                    }
            }
        }
    }

    public static function parseInclude(include:String):IncludeReference {
        if (include == "$base") {
            return BASE_REFERENCE;
        } else if (include == "$self") {
            return SELF_REFERENCE;
        }

        var indexOfSharp = include.indexOf('#');
        if (indexOfSharp == -1) {
            return new IncludeReference(TopLevelReference, include, null);
        } else if (indexOfSharp == 0) {
            return new IncludeReference(RelativeReference, null, include.substring(1));
        } else {
            var scopeName = include.substring(0, indexOfSharp);
            var ruleName = include.substring(indexOfSharp + 1);
            return new IncludeReference(TopLevelRepositoryReference, scopeName, ruleName);
        }
    }
}
