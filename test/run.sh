#!/bin/bash
# Build and run the tests with Node.js.
# Usage: ./run.sh [--onig=haxe|wasm|both] [--verbose] [filter]
# The wasm backend needs vscode-oniguruma 2.0.1: set VSCODE_ONIGURUMA to its package folder.
set -e
cd "$(dirname "$0")"
HAXE="${HAXE:-haxe}"
"$HAXE" build.hxml
node bin/test.js "$@"
