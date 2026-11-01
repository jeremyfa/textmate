#!/usr/bin/env node

// Times the real vscode-textmate + vscode-oniguruma (onig.wasm) on the large
// samples of the corpus, the same way the Haxe runner times the port
// (tokenizeLine over the file, a cold pass then a warm pass).
//
// Usage: VTM_NODE_MODULES=/path/to/node_modules node test/record/bench.mjs

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(path.dirname(here), 'fixtures');
const require = createRequire(path.join(process.env.VTM_NODE_MODULES, 'noop.js'));
const vsctm = require('vscode-textmate');
const oniguruma = require('vscode-oniguruma');
await oniguruma.loadWASM(fs.readFileSync(path.join(process.env.VTM_NODE_MODULES, 'vscode-oniguruma/release/onig.wasm')).buffer);
const onigLib = Promise.resolve({
    createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
    createOnigString: (s) => new oniguruma.OnigString(s)
});

const corpus = JSON.parse(fs.readFileSync(path.join(fixtures, 'corpus.json'), 'utf8'));
const raw = {};
for (const scopeName in corpus.grammars) {
    raw[scopeName] = vsctm.parseRawGrammar(fs.readFileSync(path.join(fixtures, corpus.grammars[scopeName]), 'utf8'), corpus.grammars[scopeName]);
}
const names = ['javascript/shiki-vscode-textmate.js', 'javascript/vscode-textmate-main.min.js', 'typescript/grammar.ts', 'haxe/Rule.hx', 'rust/rope.rs',
    'markdown/vscode-textmate-README.md', 'yaml/pnpm-lock.yaml', 'shell/perltest.sh'];
const registry = new vsctm.Registry({ onigLib, loadGrammar: async (s) => raw[s] || null });
for (const name of names) {
    const c = corpus.cases.find(c => c.name === name);
    const lines = fs.readFileSync(path.join(fixtures, c.file), 'utf8').replace(/\r\n/g, '\n').split('\n');
    const grammar = await registry.loadGrammar(c.scopeName);
    const times = [];
    for (let pass = 0; pass < 2; pass++) {
        let state = null;
        const start = performance.now();
        for (const line of lines) {
            state = grammar.tokenizeLine(line, state).ruleStack;
        }
        times.push(performance.now() - start);
    }
    console.log(`${name}: ${lines.length} lines, cold ${times[0].toFixed(0)} ms (${(times[0] / lines.length).toFixed(3)} ms/line), warm ${times[1].toFixed(0)} ms (${(times[1] / lines.length).toFixed(3)} ms/line)`);
}
