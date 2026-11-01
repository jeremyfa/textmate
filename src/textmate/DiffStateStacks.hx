// Ported from vscode-textmate 9.2.0: src/diffStateStacks.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.IGrammar.StateStack;
import textmate.grammar.Grammar.StateStackFrame;
import textmate.grammar.Grammar.StateStackImpl;

class DiffStateStacks {
    public static function diffStateStacksRefEq(first:StateStack, second:StateStack):StackDiff {
        var pops = 0;
        var newFrames:Array<StateStackFrame> = [];

        var curFirst:Null<StateStackImpl> = cast first;
        var curSecond:Null<StateStackImpl> = cast second;

        while (curFirst != curSecond) {
            if (curFirst != null && (curSecond == null || curFirst.depth >= curSecond.depth)) {
                // curFirst is certainly not contained in curSecond
                pops++;
                curFirst = curFirst.parent;
            } else {
                // curSecond is certainly not contained in curFirst.
                // Also, curSecond must be defined, as otherwise a previous case would match
                newFrames.push(curSecond.toStateStackFrame());
                curSecond = curSecond.parent;
            }
        }
        newFrames.reverse();
        return new StackDiff(pops, newFrames);
    }

    public static function applyStateStackDiff(stack:Null<StateStack>, diff:StackDiff):Null<StateStackImpl> {
        var curStack:Null<StateStackImpl> = cast stack;
        for (i in 0...diff.pops) {
            curStack = curStack.parent;
        }
        for (frame in diff.newFrames) {
            curStack = StateStackImpl.pushFrame(curStack, frame);
        }
        return curStack;
    }
}

class StackDiff {
    public final pops:Int;
    public final newFrames:Array<StateStackFrame>;

    public function new(pops:Int, newFrames:Array<StateStackFrame>) {
        this.pops = pops;
        this.newFrames = newFrames;
    }
}
