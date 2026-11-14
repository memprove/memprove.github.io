import releaseJson from '../data/release.json';

export const release = releaseJson;

type Repo = { stars: number | null; commit: string; releases: { tag: string; name: string; date: string; url: string }[] };
// Written by scripts/sync-docs.mjs; missing when the sync has not run.
const generated = import.meta.glob<{ default: Repo }>('../data/generated/repo.json', { eager: true });
export const repo: Repo = Object.values(generated)[0]?.default ?? { stars: null, commit: 'unknown', releases: [] };

export const installCommands = {
  macos: archiveCommands(release.targets.macos.triple),
  linux: archiveCommands(release.targets.linux.triple),
  source: [
    'git clone https://github.com/memprove/memprove && cd memprove',
    'cargo fetch --locked',
    'cargo build --offline --release -p memprove-cli -p memprove-daemon',
    'scripts/install.sh --from-binaries target/release',
  ],
};

function archiveCommands(triple: string): string[] {
  const name = `memprove-${release.version}-${triple}`;
  return [`curl -LO ${release.base}/${name}.tar.gz`, `tar -xzf ${name}.tar.gz && cd ${name}`, 'scripts/install.sh --from-binaries bin'];
}
