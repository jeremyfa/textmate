// Ported from vscode-textmate 9.2.0: src/main.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import haxe.ds.StringMap;
import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.RawGrammar.IRawGrammar;
import textmate.Theme;
import textmate.grammar.Grammar.BalancedBracketSelectors;
import textmate.grammar.GrammarDependencies.ScopeDependencyProcessor;

/**
 * A registry helper that can locate grammar file paths given scope names.
 *
 * Synchronous: `onigLib` is the engine itself (not a promise) and
 * `loadGrammar` returns the grammar (or null).
 */
typedef RegistryOptions = {
    var onigLib:IOnigLib;
    var ?theme:IRawTheme;
    var ?colorMap:Array<String>;
    var loadGrammar:(scopeName:ScopeName) -> Null<IRawGrammar>;
    var ?getInjections:(scopeName:ScopeName) -> Null<Array<ScopeName>>;
}

typedef IGrammarConfiguration = {
    var ?embeddedLanguages:IEmbeddedLanguagesMap;
    var ?tokenTypes:ITokenTypeMap;
    var ?balancedBracketSelectors:Array<String>;
    var ?unbalancedBracketSelectors:Array<String>;
}

/**
 * The registry that will hold all grammars.
 */
class Registry {
    final _options:RegistryOptions;
    final _syncRegistry:SyncRegistry;
    final _ensureGrammarCache:StringMap<Bool>;

    public function new(options:RegistryOptions) {
        _options = options;
        _syncRegistry = new SyncRegistry(Theme.createFromRawTheme(options.theme, options.colorMap), options.onigLib);
        _ensureGrammarCache = new StringMap<Bool>();
    }

    public function dispose():Void {
        _syncRegistry.dispose();
    }

    /**
     * Change the theme. Once called, no previous `ruleStack` should be used anymore.
     */
    public function setTheme(theme:IRawTheme, ?colorMap:Array<String>):Void {
        _syncRegistry.setTheme(Theme.createFromRawTheme(theme, colorMap));
    }

    /**
     * Returns a lookup array for color ids.
     */
    public function getColorMap():Array<String> {
        return _syncRegistry.getColorMap();
    }

    /**
     * Load the grammar for `scopeName` and all referenced included grammars.
     * Please do not use language id 0.
     */
    public function loadGrammarWithEmbeddedLanguages(initialScopeName:ScopeName, initialLanguage:Int, embeddedLanguages:IEmbeddedLanguagesMap):Null<IGrammar> {
        return loadGrammarWithConfiguration(initialScopeName, initialLanguage, {embeddedLanguages: embeddedLanguages});
    }

    /**
     * Load the grammar for `scopeName` and all referenced included grammars.
     * Please do not use language id 0.
     */
    public function loadGrammarWithConfiguration(initialScopeName:ScopeName, initialLanguage:Int, configuration:IGrammarConfiguration):Null<IGrammar> {
        return _loadGrammar(initialScopeName, initialLanguage, configuration.embeddedLanguages, configuration.tokenTypes,
            new BalancedBracketSelectors(configuration.balancedBracketSelectors != null ? configuration.balancedBracketSelectors : [],
                configuration.unbalancedBracketSelectors != null ? configuration.unbalancedBracketSelectors : []));
    }

    /**
     * Load the grammar for `scopeName` and all referenced included grammars.
     */
    public function loadGrammar(initialScopeName:ScopeName):Null<IGrammar> {
        return _loadGrammar(initialScopeName, 0, null, null, null);
    }

    function _loadGrammar(initialScopeName:ScopeName, initialLanguage:Int, embeddedLanguages:Null<IEmbeddedLanguagesMap>, tokenTypes:Null<ITokenTypeMap>,
            balancedBracketSelectors:Null<BalancedBracketSelectors>):Null<IGrammar> {
        var dependencyProcessor = new ScopeDependencyProcessor(_syncRegistry, initialScopeName);
        while (dependencyProcessor.Q.length > 0) {
            for (request in dependencyProcessor.Q) {
                _loadSingleGrammar(request.scopeName);
            }
            dependencyProcessor.processQueue();
        }

        return _grammarForScopeName(initialScopeName, initialLanguage, embeddedLanguages, tokenTypes, balancedBracketSelectors);
    }

    function _loadSingleGrammar(scopeName:ScopeName):Void {
        if (!_ensureGrammarCache.exists(scopeName)) {
            _ensureGrammarCache.set(scopeName, true);
            _doLoadSingleGrammar(scopeName);
        }
    }

    function _doLoadSingleGrammar(scopeName:ScopeName):Void {
        var grammar = _options.loadGrammar(scopeName);
        if (grammar != null) {
            var injections = _options.getInjections != null ? _options.getInjections(scopeName) : null;
            _syncRegistry.addGrammar(grammar, injections);
        }
    }

    /**
     * Adds a rawGrammar.
     */
    public function addGrammar(rawGrammar:IRawGrammar, ?injections:Array<String>, initialLanguage:Int = 0,
            ?embeddedLanguages:IEmbeddedLanguagesMap):IGrammar {
        _syncRegistry.addGrammar(rawGrammar, injections != null ? injections : []);
        return _grammarForScopeName(rawGrammar.scopeName, initialLanguage, embeddedLanguages);
    }

    /**
     * Get the grammar for `scopeName`. The grammar must first be created via `loadGrammar` or `addGrammar`.
     */
    function _grammarForScopeName(scopeName:String, initialLanguage:Int = 0, ?embeddedLanguages:IEmbeddedLanguagesMap, ?tokenTypes:ITokenTypeMap,
            ?balancedBracketSelectors:BalancedBracketSelectors):Null<IGrammar> {
        return _syncRegistry.grammarForScopeName(scopeName, initialLanguage, embeddedLanguages, tokenTypes, balancedBracketSelectors);
    }
}
