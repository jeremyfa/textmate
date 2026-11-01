// Ported from vscode-textmate 9.2.0: src/rawGrammar.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

/**
 * A grammar as read from a `.tmLanguage.json` or `.tmLanguage` (plist) file.
 *
 * vscode-textmate works on the plain objects of the parsed file. This port
 * uses typed objects: `IRawGrammar.fromDynamic` converts a parsed file
 * (anonymous structures, or the `OrderedMap` objects `Json.parseJSON` and
 * `Plist.parsePLIST` produce) into them.
 */
class IRawGrammar {
    public var repository:IRawRepository;
    public var scopeName:String;
    public var patterns:Null<Array<IRawRule>>;
    public var injections:Null<OrderedMap<IRawRule>>;
    public var injectionSelector:Null<String>;

    public var fileTypes:Null<Array<String>>;
    public var name:Null<String>;
    public var firstLineMatch:Null<String>;

    public var vscodeTextmateLocation:Null<ILocation>;

    public function new(scopeName:String) {
        this.scopeName = scopeName;
        this.repository = null;
        this.patterns = null;
        this.injections = null;
        this.injectionSelector = null;
        this.fileTypes = null;
        this.name = null;
        this.firstLineMatch = null;
        this.vscodeTextmateLocation = null;
    }

    /**
     * Deep copy (`clone` in utils.ts).
     */
    public function clone():IRawGrammar {
        var r = new IRawGrammar(scopeName);
        r.repository = IRawRule.cloneRepository(repository);
        r.patterns = IRawRule.cloneRules(patterns);
        if (injections != null) {
            var inj = new OrderedMap<IRawRule>();
            for (key in injections.keys()) {
                var rule = injections.get(key);
                inj.set(key, rule == null ? null : rule.clone());
            }
            r.injections = inj;
        }
        r.injectionSelector = injectionSelector;
        r.fileTypes = fileTypes == null ? null : fileTypes.copy();
        r.name = name;
        r.firstLineMatch = firstLineMatch;
        r.vscodeTextmateLocation = vscodeTextmateLocation;
        return r;
    }

    /**
     * Converts a parsed grammar file (anonymous structures or `OrderedMap`
     * objects, arrays, strings, numbers and booleans) into an `IRawGrammar`.
     */
    public static function fromDynamic(obj:Dynamic):IRawGrammar {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, IRawGrammar)) {
            return obj;
        }
        var r = new IRawGrammar(RawValue.string(RawValue.field(obj, 'scopeName')));
        r.repository = IRawRule.repositoryFromDynamic(RawValue.field(obj, 'repository'));
        r.patterns = IRawRule.rulesFromDynamic(RawValue.field(obj, 'patterns'));
        var injections = RawValue.field(obj, 'injections');
        if (injections != null && RawValue.isObject(injections)) {
            var inj = new OrderedMap<IRawRule>();
            for (key in RawValue.fields(injections)) {
                inj.set(key, IRawRule.fromDynamic(RawValue.field(injections, key)));
            }
            r.injections = inj;
        }
        r.injectionSelector = RawValue.string(RawValue.field(obj, 'injectionSelector'));
        var fileTypes = RawValue.field(obj, 'fileTypes');
        if (fileTypes != null && Std.isOfType(fileTypes, Array)) {
            r.fileTypes = [for (f in (fileTypes : Array<Dynamic>)) Std.string(f)];
        }
        r.name = RawValue.string(RawValue.field(obj, 'name'));
        r.firstLineMatch = RawValue.string(RawValue.field(obj, 'firstLineMatch'));
        r.vscodeTextmateLocation = ILocation.fromDynamic(RawValue.field(obj, "$vscodeTextmateLocation"));
        return r;
    }
}

/**
 * Allowed values:
 * * Scope Name, e.g. `source.ts`
 * * Top level scope reference, e.g. `source.ts#entity.name.class`
 * * Relative scope reference, e.g. `#entity.name.class`
 * * self, e.g. `$self`
 * * base, e.g. `$base`
 */
typedef IncludeString = String;

typedef RegExpString = String;

/**
 * A repository: rule names to rules, with the special `$self` and `$base`
 * entries the grammar adds when it is initialized.
 */
typedef IRawRepository = OrderedMap<IRawRule>;

/**
 * Captures: capture group numbers (as strings) to rules.
 */
typedef IRawCaptures = OrderedMap<IRawRule>;

class IRawRule {
    /** This is not part of the spec only used internally (0 means unset). */
    public var id:Int;

    public var include:Null<IncludeString>;

    public var name:Null<String>;
    public var contentName:Null<String>;

    public var match:Null<RegExpString>;
    public var captures:Null<IRawCaptures>;
    /** `begin` is `undefined` in vscode-textmate when this is false. */
    public var hasBegin:Bool;
    public var begin:Null<RegExpString>;
    public var beginCaptures:Null<IRawCaptures>;
    public var end:Null<RegExpString>;
    public var endCaptures:Null<IRawCaptures>;
    public var while_:Null<RegExpString>;
    public var whileCaptures:Null<IRawCaptures>;
    public var patterns:Null<Array<IRawRule>>;

    public var repository:Null<IRawRepository>;

    public var applyEndPatternLast:Bool;

    public var vscodeTextmateLocation:Null<ILocation>;

    public function new() {
        id = 0;
        include = null;
        name = null;
        contentName = null;
        match = null;
        captures = null;
        hasBegin = false;
        begin = null;
        beginCaptures = null;
        end = null;
        endCaptures = null;
        while_ = null;
        whileCaptures = null;
        patterns = null;
        repository = null;
        applyEndPatternLast = false;
        vscodeTextmateLocation = null;
    }

    public function clone():IRawRule {
        var r = new IRawRule();
        r.id = id;
        r.include = include;
        r.name = name;
        r.contentName = contentName;
        r.match = match;
        r.captures = cloneRepository(captures);
        r.hasBegin = hasBegin;
        r.begin = begin;
        r.beginCaptures = cloneRepository(beginCaptures);
        r.end = end;
        r.endCaptures = cloneRepository(endCaptures);
        r.while_ = while_;
        r.whileCaptures = cloneRepository(whileCaptures);
        r.patterns = cloneRules(patterns);
        r.repository = cloneRepository(repository);
        r.applyEndPatternLast = applyEndPatternLast;
        r.vscodeTextmateLocation = vscodeTextmateLocation;
        return r;
    }

    public static function cloneRules(rules:Null<Array<IRawRule>>):Null<Array<IRawRule>> {
        if (rules == null) {
            return null;
        }
        return [for (rule in rules) rule == null ? null : rule.clone()];
    }

    public static function cloneRepository(repository:Null<OrderedMap<IRawRule>>):Null<OrderedMap<IRawRule>> {
        if (repository == null) {
            return null;
        }
        var r = new OrderedMap<IRawRule>();
        for (key in repository.keys()) {
            var rule = repository.get(key);
            r.set(key, rule == null ? null : rule.clone());
        }
        return r;
    }

    public static function fromDynamic(obj:Dynamic):Null<IRawRule> {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, IRawRule)) {
            return obj;
        }
        if (!RawValue.isObject(obj)) {
            return null;
        }
        var r = new IRawRule();
        r.include = RawValue.string(RawValue.field(obj, 'include'));
        r.name = RawValue.string(RawValue.field(obj, 'name'));
        r.contentName = RawValue.string(RawValue.field(obj, 'contentName'));
        r.match = RawValue.string(RawValue.field(obj, 'match'));
        r.captures = repositoryFromDynamic(RawValue.field(obj, 'captures'));
        r.hasBegin = RawValue.hasField(obj, 'begin');
        r.begin = RawValue.string(RawValue.field(obj, 'begin'));
        r.beginCaptures = repositoryFromDynamic(RawValue.field(obj, 'beginCaptures'));
        r.end = RawValue.string(RawValue.field(obj, 'end'));
        r.endCaptures = repositoryFromDynamic(RawValue.field(obj, 'endCaptures'));
        r.while_ = RawValue.string(RawValue.field(obj, 'while'));
        r.whileCaptures = repositoryFromDynamic(RawValue.field(obj, 'whileCaptures'));
        r.patterns = rulesFromDynamic(RawValue.field(obj, 'patterns'));
        r.repository = repositoryFromDynamic(RawValue.field(obj, 'repository'));
        r.applyEndPatternLast = RawValue.truthy(RawValue.field(obj, 'applyEndPatternLast'));
        r.vscodeTextmateLocation = ILocation.fromDynamic(RawValue.field(obj, "$vscodeTextmateLocation"));
        return r;
    }

    public static function rulesFromDynamic(obj:Dynamic):Null<Array<IRawRule>> {
        if (obj == null || !Std.isOfType(obj, Array)) {
            return null;
        }
        return [for (item in (obj : Array<Dynamic>)) fromDynamic(item)];
    }

    public static function repositoryFromDynamic(obj:Dynamic):Null<OrderedMap<IRawRule>> {
        if (obj == null || !RawValue.isObject(obj)) {
            return null;
        }
        var r = new OrderedMap<IRawRule>();
        for (key in RawValue.fields(obj)) {
            if (key == "$vscodeTextmateLocation") {
                continue;
            }
            r.set(key, fromDynamic(RawValue.field(obj, key)));
        }
        return r;
    }
}

class ILocation {
    public var filename:Null<String>;
    public var line:Int;
    public var char:Int;

    public function new(filename:Null<String>, line:Int, char:Int) {
        this.filename = filename;
        this.line = line;
        this.char = char;
    }

    public static function fromDynamic(obj:Dynamic):Null<ILocation> {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, ILocation)) {
            return obj;
        }
        if (!RawValue.isObject(obj)) {
            return null;
        }
        var line:Dynamic = RawValue.field(obj, 'line');
        var char:Dynamic = RawValue.field(obj, 'char');
        return new ILocation(RawValue.string(RawValue.field(obj, 'filename')), line == null ? 0 : Std.int(line), char == null ? 0 : Std.int(char));
    }
}

/**
 * Helpers to read the parsed values of grammar and theme files.
 */
class RawValue {
    public static function isObject(obj:Dynamic):Bool {
        if (obj == null) {
            return false;
        }
        if (Std.isOfType(obj, OrderedMap)) {
            return true;
        }
        if (Std.isOfType(obj, String) || Std.isOfType(obj, Array) || Std.isOfType(obj, Float) || Std.isOfType(obj, Int) || Std.isOfType(obj, Bool)) {
            return false;
        }
        return Reflect.isObject(obj);
    }

    public static function field(obj:Dynamic, name:String):Dynamic {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, OrderedMap)) {
            return (obj : OrderedMap<Dynamic>).get(name);
        }
        if (!isObject(obj)) {
            return null;
        }
        return Reflect.field(obj, name);
    }

    public static function hasField(obj:Dynamic, name:String):Bool {
        if (obj == null) {
            return false;
        }
        if (Std.isOfType(obj, OrderedMap)) {
            return (obj : OrderedMap<Dynamic>).exists(name);
        }
        if (!isObject(obj)) {
            return false;
        }
        return Reflect.hasField(obj, name);
    }

    public static function fields(obj:Dynamic):Array<String> {
        if (obj == null) {
            return [];
        }
        if (Std.isOfType(obj, OrderedMap)) {
            return (obj : OrderedMap<Dynamic>).keys();
        }
        // Same order as a JavaScript object
        return OrderedMap.fromDynamic(obj).keys();
    }

    /**
     * A string value, or null when the value is missing or not a string.
     */
    public static function string(value:Dynamic):Null<String> {
        if (value == null) {
            return null;
        }
        if (Std.isOfType(value, String)) {
            return value;
        }
        return null;
    }

    /**
     * JavaScript truthiness.
     */
    public static function truthy(value:Dynamic):Bool {
        if (value == null) {
            return false;
        }
        if (Std.isOfType(value, Bool)) {
            return value;
        }
        if (Std.isOfType(value, String)) {
            return (value : String).length > 0;
        }
        if (Std.isOfType(value, Int)) {
            return (value : Int) != 0;
        }
        if (Std.isOfType(value, Float)) {
            var f:Float = value;
            return f != 0 && !Math.isNaN(f);
        }
        return true;
    }
}
