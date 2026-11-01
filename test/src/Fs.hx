// Test helper (file access on node and on native targets).

class Fs {
    #if js
    static var fs:Dynamic = js.Lib.require('fs');
    static var path:Dynamic = js.Lib.require('path');
    #end

    public static function readText(file:String):String {
        #if js
        return fs.readFileSync(file, 'utf8');
        #else
        return sys.io.File.getContent(file);
        #end
    }

    public static function writeText(file:String, content:String):Void {
        #if js
        fs.writeFileSync(file, content);
        #else
        sys.io.File.saveContent(file, content);
        #end
    }

    public static function exists(file:String):Bool {
        #if js
        return fs.existsSync(file);
        #else
        return sys.FileSystem.exists(file);
        #end
    }

    public static function readDir(dir:String):Array<String> {
        #if js
        var r:Array<String> = fs.readdirSync(dir);
        #else
        var r = sys.FileSystem.readDirectory(dir);
        #end
        r.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
        return r;
    }

    public static function dirname(file:String):String {
        var i = file.lastIndexOf('/');
        return i == -1 ? '.' : file.substring(0, i);
    }

    public static function join(a:String, b:String):String {
        if (StringTools.startsWith(b, './')) {
            b = b.substring(2);
        }
        return StringTools.endsWith(a, '/') ? a + b : a + '/' + b;
    }

    public static function extname(file:String):String {
        var slash = file.lastIndexOf('/');
        var base = slash == -1 ? file : file.substring(slash + 1);
        var dot = base.lastIndexOf('.');
        return dot <= 0 ? '' : base.substring(dot);
    }
}
