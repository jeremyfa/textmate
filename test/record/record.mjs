#!/usr/bin/env node

// Records the truth of the test suites with the real vscode-textmate and
// vscode-oniguruma, in test/fixtures/truth. The Haxe test runner replays it.
//
// Usage:
//   VTM_NODE_MODULES=/path/to/node_modules node test/record/record.mjs
//
// The node_modules folder must hold vscode-textmate@9.2.0 and
// vscode-oniguruma@2.0.1 (npm install vscode-textmate@9.2.0 vscode-oniguruma@2.0.1
// in a scratch folder, never in this repository).

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const testDir = path.dirname(here);
const fixtures = path.join(testDir, 'fixtures');
const truthDir = path.join(fixtures, 'truth');

const nodeModules = process.env.VTM_NODE_MODULES;
if (!nodeModules) {
    console.error('Set VTM_NODE_MODULES to a node_modules folder with vscode-textmate and vscode-oniguruma');
    process.exit(1);
}
const require = createRequire(path.join(nodeModules, 'noop.js'));
const vsctm = require('vscode-textmate');
const oniguruma = require('vscode-oniguruma');
const vtmVersion = JSON.parse(fs.readFileSync(path.join(nodeModules, 'vscode-textmate/package.json'), 'utf8')).version;
const onigVersion = JSON.parse(fs.readFileSync(path.join(nodeModules, 'vscode-oniguruma/package.json'), 'utf8')).version;

const wasm = fs.readFileSync(path.join(nodeModules, 'vscode-oniguruma/release/onig.wasm')).buffer;
await oniguruma.loadWASM(wasm);
const onigLib = Promise.resolve({
    createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
    createOnigString: (s) => new oniguruma.OnigString(s)
});

fs.mkdirSync(truthDir, { recursive: true });

function writeJson(file, data) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(data));
}

// ---------------------------------------------------------------- tokenization suites
// Same logic as vscode-textmate's src/tests/tokenization.test.ts

async function recordTokenizationSuite(name, testLocation) {
    const tests = JSON.parse(fs.readFileSync(testLocation, 'utf8'));
    const out = [];
    let upstreamFailures = 0;
    for (const tst of tests) {
        let grammarScopeName = tst.grammarScopeName;
        const grammarByScope = {};
        for (const grammarPath of tst.grammars) {
            const content = fs.readFileSync(path.join(path.dirname(testLocation), grammarPath)).toString();
            const rawGrammar = vsctm.parseRawGrammar(content, grammarPath);
            grammarByScope[rawGrammar.scopeName] = rawGrammar;
            if (!grammarScopeName && grammarPath === tst.grammarPath) {
                grammarScopeName = rawGrammar.scopeName;
            }
        }
        const registry = new vsctm.Registry({
            onigLib,
            loadGrammar: (scopeName) => Promise.resolve(grammarByScope[scopeName]),
            getInjections: (scopeName) => {
                if (scopeName === grammarScopeName) {
                    return tst.grammarInjections;
                }
            }
        });
        const grammar = await registry.loadGrammar(grammarScopeName);
        const lines = [];
        let prevState = null;
        let matches = true;
        for (const testCase of tst.lines) {
            let actual = grammar.tokenizeLine(testCase.line, prevState);
            const actualTokens = actual.tokens.map((token) => ({
                value: testCase.line.substring(token.startIndex, token.endIndex),
                scopes: token.scopes
            }));
            let expected = testCase.tokens;
            if (testCase.line.length > 0) {
                expected = expected.filter((token) => token.value.length > 0);
            }
            expected = expected.map((token) => ({ value: token.value, scopes: token.scopes }));
            if (JSON.stringify(actualTokens) !== JSON.stringify(expected)) {
                matches = false;
            }
            lines.push({ line: testCase.line, tokens: actualTokens });
            if (prevState) {
                const diff = vsctm.diffStateStacksRefEq(prevState, actual.ruleStack);
                actual = { ...actual, ruleStack: vsctm.applyStateStackDiff(prevState, diff) };
            }
            prevState = actual.ruleStack;
        }
        if (!matches) {
            upstreamFailures++;
        }
        out.push({ desc: tst.desc, matchesUpstream: matches, lines });
        registry.dispose();
    }
    writeJson(path.join(truthDir, name + '.json'), out);
    console.log(`${name}: ${out.length} tests, ${upstreamFailures} differ from the upstream expectations`);
}

await recordTokenizationSuite('first-mate', path.join(fixtures, 'vscode-textmate/first-mate/tests.json'));
await recordTokenizationSuite('suite1', path.join(fixtures, 'vscode-textmate/suite1/tests.json'));
await recordTokenizationSuite('suite1-while', path.join(fixtures, 'vscode-textmate/suite1/whileTests.json'));

// ---------------------------------------------------------------- theme tests
// Same logic as vscode-textmate's src/tests/themes.test.ts, themeTest.ts and themedTokenizer.ts

const THEMES_TEST_PATH = path.join(fixtures, 'vscode-textmate/themes');

function loadThemeFile(filename) {
    const fileContents = fs.readFileSync(path.join(THEMES_TEST_PATH, filename)).toString();
    if (/\.json$/.test(filename)) {
        return JSON.parse(fileContents);
    }
    // vscode-textmate's own plist parser, through parseRawGrammar (a theme is not a grammar,
    // but the plist reader is the same and returns the plain object)
    return vsctm.parseRawGrammar(fileContents, filename);
}

const THEMES = [
    ['abyss', 'Abyss.tmTheme'],
    ['dark_vs', 'dark_vs.json'],
    ['light_vs', 'light_vs.json'],
    ['hc_black', 'hc_black.json'],
    ['dark_plus', 'dark_plus.json', 'dark_vs.json'],
    ['light_plus', 'light_plus.json', 'light_vs.json'],
    ['kimbie_dark', 'Kimbie_dark.tmTheme'],
    ['monokai', 'Monokai.tmTheme'],
    ['monokai_dimmed', 'dimmed-monokai.tmTheme'],
    ['quietlight', 'QuietLight.tmTheme'],
    ['red', 'red.tmTheme'],
    ['solarized_dark', 'Solarized-dark.tmTheme'],
    ['solarized_light', 'Solarized-light.tmTheme'],
    ['tomorrow_night_blue', 'Tomorrow-Night-Blue.tmTheme'],
];

function createTheme(filename, includeFilename) {
    const theme = loadThemeFile(filename);
    if (includeFilename) {
        const includeTheme = loadThemeFile(includeFilename);
        theme.settings = includeTheme.settings.concat(theme.settings);
    }
    return theme;
}

class Resolver {
    constructor(grammars, languages) {
        this._grammars = grammars;
        this._languages = languages;
        this.onigLib = onigLib;
        this.language2id = Object.create(null);
        this._lastLanguageId = 0;
        for (let i = 0; i < this._languages.length; i++) {
            const languageId = ++this._lastLanguageId;
            this.language2id[this._languages[i].id] = languageId;
        }
    }
    findLanguageByExtension(fileExtension) {
        for (const language of this._languages) {
            if (!language.extensions) continue;
            for (const extension of language.extensions) {
                if (extension === fileExtension) return language.id;
            }
        }
        return null;
    }
    findLanguageByFilename(filename) {
        for (const language of this._languages) {
            if (!language.filenames) continue;
            for (const lFilename of language.filenames) {
                if (filename === lFilename) return language.id;
            }
        }
        return null;
    }
    findGrammarByLanguage(language) {
        for (const grammar of this._grammars) {
            if (grammar.language === language) return grammar;
        }
        throw new Error('Could not findGrammarByLanguage for ' + language);
    }
    async loadGrammar(scopeName) {
        for (const grammar of this._grammars) {
            if (grammar.scopeName === scopeName) {
                if (!grammar.grammar) {
                    grammar.grammar = Promise.resolve(vsctm.parseRawGrammar(fs.readFileSync(grammar.path).toString(), grammar.path));
                }
                return grammar.grammar;
            }
        }
        return null;
    }
}

function tokenizeWithTheme(colorMap, fileContents, grammar) {
    const lines = fileContents.split(/\r\n|\r|\n/);
    let ruleStack = null;
    const actual = [];
    for (const line of lines) {
        const result = grammar.tokenizeLine2(line, ruleStack);
        const tokensLength = result.tokens.length / 2;
        for (let j = 0; j < tokensLength; j++) {
            const startIndex = result.tokens[2 * j];
            const nextStartIndex = j + 1 < tokensLength ? result.tokens[2 * j + 2] : line.length;
            const tokenText = line.substring(startIndex, nextStartIndex);
            if (tokenText === '') continue;
            const metadata = result.tokens[2 * j + 1];
            const foreground = (metadata & 0b00000000111111111000000000000000) >>> 15;
            actual.push({ content: tokenText, color: colorMap[foreground] });
        }
        if (ruleStack) {
            const diff = vsctm.diffStateStacksRefEq(ruleStack, result.ruleStack);
            ruleStack = vsctm.applyStateStackDiff(ruleStack, diff);
        } else {
            ruleStack = result.ruleStack;
        }
    }
    return actual;
}

async function recordThemes() {
    const grammars = JSON.parse(fs.readFileSync(path.join(THEMES_TEST_PATH, 'grammars.json'), 'utf8'));
    for (const grammar of grammars) {
        grammar.path = path.join(THEMES_TEST_PATH, grammar.path);
    }
    const languages = JSON.parse(fs.readFileSync(path.join(THEMES_TEST_PATH, 'languages.json'), 'utf8'));
    const resolver = new Resolver(grammars, languages);
    const themeData = THEMES.map(([themeName, filename, include]) => {
        const registry = new vsctm.Registry(resolver);
        registry.setTheme(createTheme(filename, include));
        return { themeName, registry };
    });

    let testFiles = fs.readdirSync(path.join(THEMES_TEST_PATH, 'tests'));
    testFiles = testFiles.filter(f => !/\.result$/.test(f) && !/\.result.patch$/.test(f) && !/\.actual$/.test(f) && !/\.diff.html$/.test(f));
    testFiles.sort();
    const out = {};
    let upstreamFailures = 0;
    for (const testFile of testFiles) {
        const contents = fs.readFileSync(path.join(THEMES_TEST_PATH, 'tests', testFile)).toString('utf8');
        const expected = fs.readFileSync(path.join(THEMES_TEST_PATH, 'tests', testFile + '.result')).toString('utf8').split(/\r\n|\n/).join('\n');
        const language = resolver.findLanguageByExtension(path.extname(testFile)) || resolver.findLanguageByFilename(testFile);
        const grammar = resolver.findGrammarByLanguage(language);
        const embeddedLanguages = Object.create(null);
        if (grammar.embeddedLanguages) {
            for (const scopeName in grammar.embeddedLanguages) {
                embeddedLanguages[scopeName] = resolver.language2id[grammar.embeddedLanguages[scopeName]];
            }
        }
        const actual = {};
        for (const td of themeData) {
            const g = await td.registry.loadGrammarWithEmbeddedLanguages(grammar.scopeName, resolver.language2id[language], embeddedLanguages);
            actual[td.themeName] = tokenizeWithTheme(td.registry.getColorMap(), contents, g);
        }
        const actualStr = JSON.stringify(actual, null, '\t').split(/\r\n|\n/).join('\n');
        const matches = actualStr === expected;
        if (!matches) upstreamFailures++;
        // The .result files are the truth when they match (the runner reads them):
        // the actual output is only kept for the files where they differ.
        out[testFile] = matches ? { matchesUpstream: true } : { matchesUpstream: false, actual };
    }
    writeJson(path.join(truthDir, 'themes.json'), out);
    console.log(`themes: ${testFiles.length} test files, ${upstreamFailures} differ from the upstream .result files`);
}

await recordThemes();

// ---------------------------------------------------------------- corpus of real grammars

const corpus = JSON.parse(fs.readFileSync(path.join(fixtures, 'corpus.json'), 'utf8'));

function readRawTheme(def) {
    const load = (file) => {
        const full = path.join(fixtures, file);
        const text = fs.readFileSync(full, 'utf8');
        if (/\.json$/.test(file)) {
            const obj = JSON.parse(text);
            if (obj.tokenColors) {
                // A VS Code / shiki theme: the editor colors become the default rule
                const colors = obj.colors || {};
                return {
                    name: obj.name,
                    settings: [{ settings: { foreground: colors['editor.foreground'], background: colors['editor.background'] } }].concat(obj.tokenColors)
                };
            }
            return obj;
        }
        return vsctm.parseRawGrammar(text, file);
    };
    const theme = load(def.path);
    if (def.include) {
        const inc = load(def.include);
        theme.settings = inc.settings.concat(theme.settings);
    }
    return theme;
}

const ASSERTION = /^\/\/\s*(\^|<-)/;

export function corpusLines(text, stripAssertions) {
    let lines = text.replace(/\r\n/g, '\n').split('\n');
    if (stripAssertions) {
        lines = lines.filter(l => !ASSERTION.test(l));
    }
    return lines;
}

function expandCases() {
    const cases = [];
    for (const c of corpus.cases) {
        if (c.dir) {
            const files = fs.readdirSync(path.join(fixtures, c.dir)).filter(f => f.endsWith(c.ext)).sort();
            for (const f of files) {
                cases.push({ ...c, name: c.name + '/' + f, file: c.dir + '/' + f });
            }
        } else {
            cases.push(c);
        }
    }
    return cases;
}

async function recordCorpus() {
    const rawGrammars = {};
    for (const scopeName in corpus.grammars) {
        const file = corpus.grammars[scopeName];
        rawGrammars[scopeName] = vsctm.parseRawGrammar(fs.readFileSync(path.join(fixtures, file), 'utf8'), file);
    }
    const index = [];
    let totalLines = 0;
    for (const c of expandCases()) {
        const text = fs.readFileSync(path.join(fixtures, c.file), 'utf8');
        const lines = corpusLines(text, !!c.stripAssertions);
        const result = { name: c.name, file: c.file, scopeName: c.scopeName, lineCount: lines.length, scopeTable: [], tokens: [], themes: {} };
        const scopeIndex = new Map();
        const config = c.config || {};
        for (const themeName of c.themes) {
            const registry = new vsctm.Registry({
                onigLib,
                theme: readRawTheme(corpus.themes[themeName]),
                loadGrammar: async (scopeName) => rawGrammars[scopeName] || null
            });
            const grammar = await registry.loadGrammarWithConfiguration(c.scopeName, config.initialLanguage || 0, {
                embeddedLanguages: config.embeddedLanguages,
                tokenTypes: config.tokenTypes,
                balancedBracketSelectors: config.balancedBracketSelectors,
                unbalancedBracketSelectors: config.unbalancedBracketSelectors
            });
            const binLines = [];
            let state = null;
            let state2 = null;
            for (const line of lines) {
                if (Object.keys(result.themes).length === 0) {
                    // Scopes do not depend on the theme: record them once
                    const r = grammar.tokenizeLine(line, state);
                    const flat = [];
                    for (const t of r.tokens) {
                        const key = t.scopes.join(' ');
                        let idx = scopeIndex.get(key);
                        if (idx === undefined) {
                            idx = result.scopeTable.length;
                            result.scopeTable.push(key);
                            scopeIndex.set(key, idx);
                        }
                        flat.push(t.startIndex, t.endIndex, idx);
                    }
                    if (r.stoppedEarly) throw new Error('stopped early');
                    result.tokens.push(flat);
                    state = r.ruleStack;
                }
                const r2 = grammar.tokenizeLine2(line, state2);
                binLines.push(Array.from(r2.tokens, (v) => v | 0));
                if (state2) {
                    const diff = vsctm.diffStateStacksRefEq(state2, r2.ruleStack);
                    state2 = vsctm.applyStateStackDiff(state2, diff);
                } else {
                    state2 = r2.ruleStack;
                }
            }
            result.themes[themeName] = { colorMap: registry.getColorMap(), lines: binLines };
            registry.dispose();
        }
        totalLines += lines.length;
        const out = path.join('corpus', c.name.replace(/[^A-Za-z0-9._-]+/g, '_') + '.json');
        writeJson(path.join(truthDir, out), result);
        index.push({ name: c.name, truth: out, lines: lines.length });
    }
    writeJson(path.join(truthDir, 'corpus-index.json'), index);
    console.log(`corpus: ${index.length} cases, ${totalLines} lines`);
}

await recordCorpus();

writeJson(path.join(truthDir, 'versions.json'), { 'vscode-textmate': vtmVersion, 'vscode-oniguruma': onigVersion, recorded: new Date().toISOString() });
console.log(`recorded with vscode-textmate ${vtmVersion} and vscode-oniguruma ${onigVersion}`);
