// Ported from vscode-textmate 9.2.0: src/tests/resolver.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

import haxe.ds.StringMap;
import textmate.RawGrammar.IRawGrammar;
import textmate.Textmate;

typedef ILanguageRegistration = {
    var id:String;
    var ?extensions:Array<String>;
    var ?filenames:Array<String>;
}

typedef IGrammarRegistration = {
    var ?language:String;
    var scopeName:String;
    var path:String;
    var ?embeddedLanguages:Dynamic;
}

class Resolver {
    public final language2id:StringMap<Int>;
    var _lastLanguageId:Int;
    final _grammars:Array<IGrammarRegistration>;
    final _languages:Array<ILanguageRegistration>;
    final _loaded = new StringMap<IRawGrammar>();

    public function new(grammars:Array<IGrammarRegistration>, languages:Array<ILanguageRegistration>) {
        _grammars = grammars;
        _languages = languages;
        language2id = new StringMap<Int>();
        _lastLanguageId = 0;
        for (i in 0..._languages.length) {
            var languageId = ++_lastLanguageId;
            language2id.set(_languages[i].id, languageId);
        }
    }

    public function findLanguageByExtension(fileExtension:String):Null<String> {
        for (language in _languages) {
            if (language.extensions == null) {
                continue;
            }
            for (extension in language.extensions) {
                if (extension == fileExtension) {
                    return language.id;
                }
            }
        }
        return null;
    }

    public function findLanguageByFilename(filename:String):Null<String> {
        for (language in _languages) {
            if (language.filenames == null) {
                continue;
            }
            for (lFilename in language.filenames) {
                if (filename == lFilename) {
                    return language.id;
                }
            }
        }
        return null;
    }

    public function findGrammarByLanguage(language:String):IGrammarRegistration {
        for (grammar in _grammars) {
            if (grammar.language == language) {
                return grammar;
            }
        }
        throw 'Could not findGrammarByLanguage for ' + language;
    }

    public function loadGrammar(scopeName:String):Null<IRawGrammar> {
        for (grammar in _grammars) {
            if (grammar.scopeName == scopeName) {
                var g = _loaded.get(scopeName);
                if (g == null) {
                    g = Textmate.parseRawGrammar(Fs.readText(grammar.path), grammar.path);
                    _loaded.set(scopeName, g);
                }
                return g;
            }
        }
        return null;
    }
}
