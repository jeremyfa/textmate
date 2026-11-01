// Ported from vscode-textmate 9.2.0: src/parseRawGrammar.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import textmate.Debug.DebugFlags;
import textmate.RawGrammar.IRawGrammar;

class ParseRawGrammar {
    public static function parseRawGrammar(content:String, ?filePath:String):IRawGrammar {
        if (filePath != null && StringTools.endsWith(filePath, '.json')) {
            return parseJSONGrammar(content, filePath);
        }
        return parsePLISTGrammar(content, filePath);
    }

    static function parseJSONGrammar(contents:String, filename:Null<String>):IRawGrammar {
        return IRawGrammar.fromDynamic(Json.parseJSON(contents, filename, DebugFlags.InDebugMode));
    }

    static function parsePLISTGrammar(contents:String, filename:Null<String>):IRawGrammar {
        if (DebugFlags.InDebugMode) {
            return IRawGrammar.fromDynamic(Plist.parseWithLocation(contents, filename, "$vscodeTextmateLocation"));
        }
        return IRawGrammar.fromDynamic(Plist.parsePLIST(contents));
    }
}
