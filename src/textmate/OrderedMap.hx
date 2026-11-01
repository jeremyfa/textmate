// Written for the Haxe port of vscode-textmate 9.2.0 (no upstream file).
// It stands for the plain JavaScript objects vscode-textmate uses as maps.
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate;

import haxe.ds.StringMap;

/**
 * A string keyed map that iterates its keys like a JavaScript object does:
 * the keys that are array indices (canonical integers below 2^32 - 1) first,
 * in ascending order, then the other keys in insertion order. Setting an
 * existing key keeps its position.
 *
 * vscode-textmate iterates plain objects (`for (key in obj)`, `Object.keys`)
 * in a few places where the order is visible in the result (injections, token
 * types), so this order is kept on every target.
 */
class OrderedMap<T> {
    final _map:StringMap<T>;
    final _keys:Array<String>;
    var _sortedKeys:Null<Array<String>>;

    public function new() {
        _map = new StringMap<T>();
        _keys = [];
        _sortedKeys = null;
    }

    public inline function get(key:String):Null<T> {
        return _map.get(key);
    }

    public inline function exists(key:String):Bool {
        return _map.exists(key);
    }

    public function set(key:String, value:T):Void {
        if (!_map.exists(key)) {
            _keys.push(key);
            _sortedKeys = null;
        }
        _map.set(key, value);
    }

    public function remove(key:String):Bool {
        if (!_map.exists(key)) {
            return false;
        }
        _map.remove(key);
        _keys.remove(key);
        _sortedKeys = null;
        return true;
    }

    public var length(get, never):Int;

    inline function get_length():Int {
        return _keys.length;
    }

    /**
     * The keys, in JavaScript object order. Do not modify the returned array.
     */
    public function keys():Array<String> {
        if (_sortedKeys == null) {
            var indices:Array<String> = [];
            var others:Array<String> = [];
            for (key in _keys) {
                if (isArrayIndex(key)) {
                    indices.push(key);
                } else {
                    others.push(key);
                }
            }
            if (indices.length > 1) {
                haxe.ds.ArraySort.sort(indices, (a, b) -> {
                    if (a.length != b.length) {
                        return a.length - b.length;
                    }
                    return a < b ? -1 : (a > b ? 1 : 0);
                });
            }
            _sortedKeys = indices.length == 0 ? others : indices.concat(others);
        }
        return _sortedKeys;
    }

    public inline function iterator():Iterator<T> {
        var k = keys();
        var i = 0;
        return {
            hasNext: () -> i < k.length,
            next: () -> _map.get(k[i++])
        };
    }

    /**
     * A shallow copy.
     */
    public function copy():OrderedMap<T> {
        var r = new OrderedMap<T>();
        for (key in _keys) {
            r.set(key, _map.get(key));
        }
        return r;
    }

    public static function fromMap<T>(map:Map<String, T>):OrderedMap<T> {
        var r = new OrderedMap<T>();
        for (key => value in map) {
            r.set(key, value);
        }
        return r;
    }

    /**
     * Builds a map from an anonymous structure (`Reflect.fields` order) or an
     * `OrderedMap`.
     */
    public static function fromDynamic<T>(obj:Dynamic):Null<OrderedMap<T>> {
        if (obj == null) {
            return null;
        }
        if (Std.isOfType(obj, OrderedMap)) {
            return (obj : OrderedMap<T>).copy();
        }
        var r = new OrderedMap<T>();
        for (key in Reflect.fields(obj)) {
            r.set(key, Reflect.field(obj, key));
        }
        return r;
    }

    static function isArrayIndex(key:String):Bool {
        var len = key.length;
        if (len == 0 || len > 10) {
            return false;
        }
        var c0 = StringTools.fastCodeAt(key, 0);
        if (c0 == '0'.code) {
            return len == 1;
        }
        var value = 0.0;
        for (i in 0...len) {
            var c = StringTools.fastCodeAt(key, i);
            if (c < '0'.code || c > '9'.code) {
                return false;
            }
            value = value * 10 + (c - '0'.code);
        }
        return value < 4294967295.0;
    }

    public function toString():String {
        var parts = [];
        for (key in keys()) {
            parts.push(key + ': ' + Std.string(_map.get(key)));
        }
        return '{' + parts.join(', ') + '}';
    }
}
