// Roadmap #233: repo complexity heuristic for setup-lane suggestion.
//
// Output: { tier: 'simple' | 'complex', score: <number>, signals: [...] }
//   - 'simple' → setup wizard suggests Setup B (Sonnet 5 + Fable) or no pin
//   - 'complex' → setup wizard suggests Setup A (Opus 5) or escalating to Opus 4.8
// Cross-model review (Codex xhigh) always runs regardless of driver
// selection — see CLAUDE_CODE_SDLC_WIZARD.md.
//
// Classification (matches CLAUDE_CODE_SDLC_WIZARD.md → "Mixed-Mode Tier"):
//   simple = LOC < 10K AND tests < 30 AND hooks < 5 AND workflows < 5 AND no stakes
//   complex = ANY high signal OR stakes flag (.env / secrets/ / credentials/ at any depth)
// `score` is an additive ladder kept for transparency (low=0, mid=1, high=2 per signal).
//
// Heuristic is intentionally cheap: a single sync filesystem walk, no parsing.
// It is a setup-time hint, not a runtime gate; users can override the result.

const fs = require('fs');
const path = require('path');

const STAKES_FILES = new Set(['.env', '.env.local', '.env.production', '.env.development', '.envrc']);
const STAKES_DIRS = new Set(['secrets', 'credentials', '.secrets', '.credentials']);
const SKIP_DIRS = new Set([
  'node_modules', '.git', 'dist', 'build', 'out', 'target',
  '.next', '.nuxt', 'coverage', '.cache', 'vendor', '__pycache__',
]);
const SOURCE_EXTS = new Set([
  '.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs',
  '.py', '.go', '.rs', '.rb', '.java', '.kt', '.swift',
  '.c', '.h', '.cpp', '.hpp', '.cc',
  '.sh', '.bash', '.zsh',
]);
const TEST_PATTERNS = [/\.test\.[jt]sx?$/, /\.spec\.[jt]sx?$/, /_test\.go$/, /test_.*\.py$/, /.*_test\.py$/];

function isTestFile(name, parentDir) {
  if (TEST_PATTERNS.some((p) => p.test(name))) return true;
  return parentDir === 'tests' || parentDir === 'test' || parentDir === '__tests__' || parentDir === 'spec';
}

function walk(rootDir, repoRoot, onFile, onDir, visited) {
  let entries;
  try {
    entries = fs.readdirSync(rootDir, { withFileTypes: true });
  } catch (_) {
    return;
  }
  for (const entry of entries) {
    const full = path.join(rootDir, entry.name);
    if (entry.isSymbolicLink()) continue; // don't follow symlinks (cycle / out-of-tree risk)
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      // Resolve real path for cycle detection.
      let realPath;
      try {
        realPath = fs.realpathSync(full);
      } catch (_) {
        continue;
      }
      if (visited.has(realPath)) continue;
      visited.add(realPath);
      onDir && onDir(full, entry.name);
      walk(full, repoRoot, onFile, onDir, visited);
    } else if (entry.isFile()) {
      onFile(full, entry.name, path.basename(rootDir));
    }
  }
}

function countLines(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    if (!content) return 0;
    return content.split('\n').length;
  } catch (_) {
    return 0;
  }
}

function detectComplexity(repoPath) {
  if (!fs.existsSync(repoPath)) {
    throw new Error(`Repo path does not exist: ${repoPath}`);
  }
  const stat = fs.statSync(repoPath);
  if (!stat.isDirectory()) {
    throw new Error(`Repo path is not a directory: ${repoPath}`);
  }
  const repoRoot = path.resolve(repoPath);

  let loc = 0;
  let testFiles = 0;
  let hookFiles = 0;
  let workflowFiles = 0;
  const stakesHits = [];
  const visited = new Set([fs.realpathSync(repoRoot)]);

  walk(
    repoRoot,
    repoRoot,
    (filePath, name, parent) => {
      const ext = path.extname(name).toLowerCase();
      const rel = path.relative(repoRoot, filePath);
      if (STAKES_FILES.has(name)) {
        stakesHits.push(`stakes:file:${rel}`);
      }
      if (SOURCE_EXTS.has(ext) || ext === '.yml' || ext === '.yaml') {
        if (isTestFile(name, parent)) testFiles++;
        else if (SOURCE_EXTS.has(ext)) loc += countLines(filePath);
      }
      if (parent === 'hooks' && filePath.includes(`.claude${path.sep}hooks`) && (ext === '.sh' || ext === '.bash')) {
        hookFiles++;
      }
      if (parent === 'workflows' && filePath.includes(`.github${path.sep}workflows`) && (ext === '.yml' || ext === '.yaml')) {
        workflowFiles++;
      }
    },
    (dirPath, name) => {
      if (STAKES_DIRS.has(name)) {
        const rel = path.relative(repoRoot, dirPath);
        stakesHits.push(`stakes:dir:${rel || name}/`);
      }
    },
    visited
  );

  // Bands match docs: LOC<10K / tests<30 / hooks<5 / workflows<5 = "simple band"
  const signals = [];
  let highHits = 0;
  let score = 0;

  function band(value, midThreshold, highThreshold, label) {
    if (value >= highThreshold) {
      score += 2;
      highHits++;
      signals.push(`${label}:${value} (high → +2)`);
    } else if (value >= midThreshold) {
      score += 1;
      signals.push(`${label}:${value} (mid → +1)`);
    } else {
      signals.push(`${label}:${value} (low → +0)`);
    }
  }

  band(loc, 1000, 10000, 'loc');
  band(testFiles, 5, 30, 'tests');
  band(hookFiles, 3, 5, 'hooks');
  band(workflowFiles, 2, 5, 'workflows');

  let tier = highHits > 0 ? 'complex' : 'simple';
  if (stakesHits.length > 0) {
    tier = 'complex';
    signals.push(...stakesHits, 'override:stakes-forces-complex');
  }

  return { tier, score, signals };
}

module.exports = { detectComplexity };

if (require.main === module) {
  const target = process.argv[2] || '.';
  try {
    const result = detectComplexity(target);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (err) {
    process.stderr.write(`error: ${err.message}\n`);
    process.exit(2);
  }
}
