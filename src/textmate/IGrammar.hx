// Ported from vscode-textmate 9.2.0: src/main.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.EncodedTokenAttributes.StandardTokenType;

/**
 * A map from scope name to a language id. Please do not use language id 0.
 */
typedef IEmbeddedLanguagesMap = OrderedMap<Int>;

/**
 * A map from selectors to token types (applied in key order).
 */
typedef ITokenTypeMap = OrderedMap<StandardTokenType>;

/**
 * A grammar
 */
interface IGrammar {
    /**
     * Tokenize `lineText` using previous line state `prevState`.
     */
    function tokenizeLine(lineText:String, prevState:Null<StateStack>, timeLimit:Int = 0):ITokenizeLineResult;

    /**
     * Tokenize `lineText` using previous line state `prevState`.
     * The result contains the tokens in binary format, resolved with the following information:
     *  - language
     *  - token type (regex, string, comment, other)
     *  - font style
     *  - foreground color
     *  - background color
     * e.g. for getting the languageId: `EncodedTokenAttributes.getLanguageId(metadata)`
     */
    function tokenizeLine2(lineText:String, prevState:Null<StateStack>, timeLimit:Int = 0):ITokenizeLineResult2;
}

class ITokenizeLineResult {
    public final tokens:Array<IToken>;

    /**
     * The `prevState` to be passed on to the next line tokenization.
     */
    public final ruleStack:StateStack;

    /**
     * Did tokenization stop early due to reaching the time limit.
     */
    public final stoppedEarly:Bool;

    public function new(tokens:Array<IToken>, ruleStack:StateStack, stoppedEarly:Bool) {
        this.tokens = tokens;
        this.ruleStack = ruleStack;
        this.stoppedEarly = stoppedEarly;
    }
}

class ITokenizeLineResult2 {
    /**
     * The tokens in binary format. Each token occupies two array indices. For token i:
     *  - at offset 2*i => startIndex
     *  - at offset 2*i + 1 => metadata
     */
    public final tokens:haxe.io.UInt32Array;

    /**
     * The `prevState` to be passed on to the next line tokenization.
     */
    public final ruleStack:StateStack;

    /**
     * Did tokenization stop early due to reaching the time limit.
     */
    public final stoppedEarly:Bool;

    public function new(tokens:haxe.io.UInt32Array, ruleStack:StateStack, stoppedEarly:Bool) {
        this.tokens = tokens;
        this.ruleStack = ruleStack;
        this.stoppedEarly = stoppedEarly;
    }
}

class IToken {
    public var startIndex:Int;
    public final endIndex:Int;
    public final scopes:Array<String>;

    public inline function new(startIndex:Int, endIndex:Int, scopes:Array<String>) {
        this.startIndex = startIndex;
        this.endIndex = endIndex;
        this.scopes = scopes;
    }
}

/**
 * **IMPORTANT** - Immutable!
 */
interface StateStack {
    var depth(default, null):Int;

    function clone():StateStack;
    function equals(other:StateStack):Bool;
}
