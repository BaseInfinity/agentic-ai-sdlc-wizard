#!/usr/bin/env node
'use strict';

const { version } = require('../../package.json');
const { init, check } = require('../init');
const { detectComplexity } = require('../lib/repo-complexity');

const args = process.argv.slice(2);

const flags = {
  force: args.includes('--force'),
  dryRun: args.includes('--dry-run'),
  json: args.includes('--json'),
  preserveCustomized: args.includes('--preserve-customized'),
};

const positional = args.filter((a) => !a.startsWith('--'));
const command = positional[0];

if (args.includes('--version') || args.includes('-v')) {
  console.log(version);
  process.exit(0);
}

if (args.includes('--help') || args.includes('-h') || !command) {
  console.log(`
  agentic-sdlc-wizard v${version}

  Usage:
    sdlc-wizard init [options]               Install SDLC wizard into current directory
    sdlc-wizard check [options]              Check installation health and updates
    sdlc-wizard complexity [path]            Print mixed-mode tier heuristic (roadmap #233)

  Options:
    --force                  Overwrite existing files (init only)
    --preserve-customized    With --force, skip files that have local edits (init only)
    --dry-run                Preview changes without writing (init only)
    --json                   Output as JSON (check / complexity)
    --version                Show version
    --help                   Show this help
  `.trim());
  process.exit(0);
}

if (command === 'init') {
  try {
    init(process.cwd(), flags);
    process.exit(0);
  } catch (err) {
    // Plugin-detect errors already streamed a colored guidance block to stderr
    // from init() — skip the redundant "Error:" prefix line.
    if (!err.pluginPaths) console.error(`Error: ${err.message}`);
    process.exit(1);
  }
} else if (command === 'check') {
  try {
    const { hasDrift } = check(process.cwd(), { json: flags.json });
    process.exit(hasDrift ? 1 : 0);
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
} else if (command === 'complexity') {
  try {
    const target = positional[1] || process.cwd();
    const result = detectComplexity(target);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    process.exit(0);
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(2);
  }
} else {
  console.error(`Unknown command: ${command}`);
  console.error('Run "sdlc-wizard --help" for usage.');
  process.exit(1);
}
