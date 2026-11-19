// Brainrot Bay: a make.fun roblox-brainrot-01 entry (Node 22, stdlib only).
//
// The game is the Rojo project in this directory. Build the place first:
//   /home/hatch/workspace/tools/rojo/rojo build default.project.json --output game.rbxl
// Then this program hands the entry in: it copies game.rbxl, src/,
// screenshots/ and PLAY.json from beside this file to /output and writes
// /output/dossier.json, the summary the judge reads, with the vendored
// make.fun library (vendor/makefun-roblox.ts, the kit's copy, unchanged).
//
// The grader runs it with /output as the target; locally, stand in for
// /output with MAKEFUN_OUTPUT_DIR:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
//
// Any name starting with a dot (".gitkeep", ".DS_Store", ...) fails the
// entry, so the recursive copy below drops those names on purpose.

import { copyFileSync, existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

const repoRoot = fileURLToPath(new URL('.', import.meta.url));
const outDir = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

function copyTreeSkippingDotfiles(fromDir: string, toDir: string): void {
	mkdirSync(toDir, { recursive: true });
	for (const name of readdirSync(fromDir)) {
		if (name.startsWith('.')) {
			continue;
		}
		const from = join(fromDir, name);
		const to = join(toDir, name);
		if (statSync(from).isDirectory()) {
			copyTreeSkippingDotfiles(from, to);
		} else {
			copyFileSync(from, to);
		}
	}
}

mkdirSync(outDir, { recursive: true });

// Fail fast, with a readable reason, when a screenshot breaks the
// gate's caps (3-4 files, each at most 256 KiB): buildDossier would
// refuse the entry anyway, but its error names the cap, not the file.
const shotsDir = join(repoRoot, 'screenshots');
if (existsSync(shotsDir)) {
	const shots = readdirSync(shotsDir).filter((name) => !name.startsWith('.'));
	if (shots.length < 3 || shots.length > 4) {
		throw new Error(`Brainrot Bay: expected 3-4 screenshots, found ${shots.length}`);
	}
	for (const name of shots) {
		const size = statSync(join(shotsDir, name)).size;
		if (size > 262144) {
			throw new Error(`Brainrot Bay: screenshot ${name} is ${size} bytes, over the 256 KiB cap`);
		}
	}
}

// The gate's place_file row refuses a place past 32 MiB, so check the
// file before copying it in rather than handing the grader a dead run.
const placePath = join(repoRoot, 'game.rbxl');
const placeSize = statSync(placePath).size;
if (placeSize > 32 * 1024 * 1024) {
	throw new Error(`Brainrot Bay: game.rbxl is ${placeSize} bytes, over the 32 MiB place_file cap`);
}

copyFileSync(join(repoRoot, 'game.rbxl'), join(outDir, 'game.rbxl'));
copyFileSync(join(repoRoot, 'PLAY.json'), join(outDir, 'PLAY.json'));
copyTreeSkippingDotfiles(join(repoRoot, 'src'), join(outDir, 'src'));
if (existsSync(join(repoRoot, 'screenshots'))) {
	copyTreeSkippingDotfiles(join(repoRoot, 'screenshots'), join(outDir, 'screenshots'));
}

// The scorer's own caps (kit reference/gate.json): text_max_bytes shapes
// the dossier text; the other caps refuse an entry the scorer would
// refuse (a place past 500000 instances, scripts past 8 MiB of source or
// past 1048576 path characters in all, more than 4 screenshots or one
// past 256 KiB).
writeFileSync(
	join(outDir, 'dossier.json'),
	buildDossier(outDir, {
		text_max_bytes: 65536,
		screenshots: { max: 4, max_bytes: 262144 },
		max_instances: 500000,
		scripts_max_source_bytes: 8388608,
		scripts_max_path_chars: 1048576,
	}),
);

console.log('Brainrot Bay: dossier written to ' + outDir);
