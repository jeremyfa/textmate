// Ported from vscode-textmate 9.2.0: src/debug.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

class DebugFlags {
    /**
     * When true, `parseRawGrammar` records the location of every rule
     * (`vscodeTextmateLocation`). vscode-textmate reads it from the
     * VSCODE_TEXTMATE_DEBUG environment variable. The debug logging of
     * vscode-textmate is not ported.
     */
    public static var InDebugMode:Bool = false;
}
