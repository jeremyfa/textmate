// Ported from vscode-textmate 9.2.0: src/registry.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import haxe.ds.StringMap;
import textmate.IGrammar;
import textmate.OnigLib.IOnigLib;
import textmate.RawGrammar.IRawGrammar;
import textmate.Theme;
import textmate.grammar.Grammar;

class SyncRegistry implements IGrammarRepositoryAndThemeProvider {
    final _grammars = new StringMap<Grammar>();
    final _rawGrammars = new StringMap<IRawGrammar>();
    final _injectionGrammars = new StringMap<Array<ScopeName>>();
    var _theme:Theme;
    final _onigLib:IOnigLib;

    public function new(theme:Theme, onigLib:IOnigLib) {
        _theme = theme;
        _onigLib = onigLib;
    }

    public function dispose():Void {
        for (grammar in _grammars) {
            grammar.dispose();
        }
    }

    public function setTheme(theme:Theme):Void {
        _theme = theme;
    }

    public function getColorMap():Array<String> {
        return _theme.getColorMap();
    }

    /**
     * Add `grammar` to registry and return a list of referenced scope names
     */
    public function addGrammar(grammar:IRawGrammar, ?injectionScopeNames:Array<ScopeName>):Void {
        _rawGrammars.set(grammar.scopeName, grammar);

        if (injectionScopeNames != null) {
            _injectionGrammars.set(grammar.scopeName, injectionScopeNames);
        }
    }

    /**
     * Lookup a raw grammar.
     */
    public function lookup(scopeName:ScopeName):Null<IRawGrammar> {
        return _rawGrammars.get(scopeName);
    }

    /**
     * Returns the injections for the given grammar
     */
    public function injections(targetScope:ScopeName):Null<Array<ScopeName>> {
        return _injectionGrammars.get(targetScope);
    }

    /**
     * Get the default theme settings
     */
    public function getDefaults():StyleAttributes {
        return _theme.getDefaults();
    }

    /**
     * Match a scope in the theme.
     */
    public function themeMatch(scopePath:ScopeStack):Null<StyleAttributes> {
        return _theme.match(scopePath);
    }

    /**
     * Lookup a grammar.
     */
    public function grammarForScopeName(scopeName:ScopeName, initialLanguage:Int, embeddedLanguages:Null<IEmbeddedLanguagesMap>,
            tokenTypes:Null<ITokenTypeMap>, balancedBracketSelectors:Null<BalancedBracketSelectors>):Null<IGrammar> {
        if (!_grammars.exists(scopeName)) {
            var rawGrammar = _rawGrammars.get(scopeName);
            if (rawGrammar == null) {
                return null;
            }
            _grammars.set(scopeName,
                GrammarTools.createGrammar(scopeName, rawGrammar, initialLanguage, embeddedLanguages, tokenTypes, balancedBracketSelectors, this, _onigLib));
        }
        return _grammars.get(scopeName);
    }
}
