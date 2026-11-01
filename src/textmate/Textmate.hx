// Ported from vscode-textmate 9.2.0: src/main.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.DiffStateStacks.StackDiff;
import textmate.IGrammar.StateStack;
import textmate.RawGrammar.IRawGrammar;
import textmate.grammar.Grammar.StateStackImpl;

/**
 * The free functions and constants of vscode-textmate's main module.
 */
class Textmate {
    public static final INITIAL:StateStack = StateStackImpl.NULL;

    public static function parseRawGrammar(content:String, ?filePath:String):IRawGrammar {
        return ParseRawGrammar.parseRawGrammar(content, filePath);
    }

    public static function diffStateStacksRefEq(first:StateStack, second:StateStack):StackDiff {
        return DiffStateStacks.diffStateStacksRefEq(first, second);
    }

    public static function applyStateStackDiff(stack:Null<StateStack>, diff:StackDiff):Null<StateStack> {
        return DiffStateStacks.applyStateStackDiff(stack, diff);
    }
}
