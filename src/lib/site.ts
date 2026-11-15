import releaseJson from '../data/release.json';

export const release = releaseJson;

type Repo = { stars: number | null; commit: string; releases: { tag: string; name: string; date: string; url: string }[] };
// Written by scripts/sync-docs.mjs; missing when the sync has not run.
const generated = import.meta.glob<{ default: Repo }>('../data/generated/repo.json', { eager: true });
export const repo: Repo = Object.values(generated)[0]?.default ?? { stars: null, commit: 'unknown', releases: [] };

// The one-line installer: public/install.sh, served at memprove.dev/install.sh.
export const installCommand = 'curl -fsSL https://memprove.dev/install.sh | sh';

export const installCommands = {
  script: [installCommand],
  source: [
    'git clone https://github.com/memprove/memprove && cd memprove',
    'cargo fetch --locked',
    'cargo build --offline --release -p memprove-cli -p memprove-daemon',
    'scripts/install.sh --from-binaries target/release',
  ],
};
