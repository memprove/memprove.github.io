# memprove.dev

The website of [memprove](https://github.com/memprove/memprove): the homepage, the docs, the changelog and `llms.txt`. Built with [Astro](https://astro.build) and [Starlight](https://starlight.astro.build), deployed to GitHub Pages by `.github/workflows/deploy.yml`.

## Where the content comes from

| Page | Source |
| --- | --- |
| `/` homepage, `/about/`, `/roadmap/`, `/404` | `src/pages/` in this repository |
| `/docs/` Quickstart | `src/fragments/quickstart.md`, with parts of memprove's `README.md` and a recorded Pack |
| `/docs/guide/…` | memprove's `docs/guide.md`, one page per `##` section |
| `/how-it-works/` | `src/fragments/how-it-works.md` plus memprove's `docs/architecture.md` |
| `/docs/takeover-eval/` | memprove's `docs/takeover-eval.md` |
| `/changelog/` | GitHub releases of memprove/memprove, then its `CHANGELOG.md` |
| `/llms.txt`, `/llms-full.txt` | `src/fragments/llms.md` with the page list; all pages in one file |
| `/install.sh` | `public/install.sh`, the one-line installer (`curl -fsSL https://memprove.dev/install.sh \| sh`) |
| every doc page as `.md` | the same Markdown, next to the page (`/docs/guide/the-context-pack.md`) |

`scripts/sync-docs.mjs` generates the docs pages before each build: it clones memprove/memprove (or uses `MEMPROVE_REPO`), splits and rewrites the Markdown, and writes the generated files, which are not committed (see `.gitignore`). Edit the docs in memprove/memprove, not here.

## Every output on the homepage is real

The terminal output on the homepage and on `/how-it-works/` was recorded, not written: `demo/record.sh` builds the example repository `demo/tinyini` (a small INI parser tested with pytest) commit by commit and runs memprove 0.1.0 on it. The output is in `src/data/demo/*.txt`; the pages read it at build time. The one exception is fig. 4 (an agent setting memprove up from `llms.txt`), marked as a mock-up in `src/data/agent-setup.json` until it is recorded in Claude Code, Codex and Cursor.

To record again, for example after a release, on a machine with that release installed fresh (the ledger's sequence numbers start from an empty `~/.memprove`):

```bash
demo/record.sh          # rewrites src/data/demo/*.txt
npm run build           # fails if a figure no longer finds the line it shows
```

## The installer

`public/install.sh` is served as it is at `https://memprove.dev/install.sh`. It is POSIX `sh`: it picks the release archive for the machine (`aarch64-apple-darwin` or `x86_64-unknown-linux-gnu`; anything else stops with a pointer to the source build), takes the latest release unless `MEMPROVE_VERSION` names one, downloads the archive and its `.sha256` file from the GitHub release, stops unless the SHA-256 matches, and runs the archive's `scripts/install.sh --from-binaries bin`, passing on `--prefix`, `--write-profile` and `--no-write-profile`. Everything is inside `main`, called on the last line, so a download cut short runs nothing.

```bash
npm run test:install     # offline: fake curl, uname and release; shellcheck when it is installed
```

`scripts/test-install.sh` runs it under `/bin/sh` (`INSTALLER_SH=bash` picks another shell) with a `PATH` that holds only the tools it may need, and the deploy workflow runs it before every build. It does not download anything; after a release, also run the installer for real on both platforms.

## Build

Node 22 or later.

```bash
npm ci
npm run dev                                   # http://localhost:4321, docs from a fresh clone of memprove main
MEMPROVE_REPO=../memprove npm run dev         # docs from a local checkout
MEMPROVE_REF=v0.1.0 npm run build             # docs from a tag
npm run build                                 # sync docs, build into dist/, run scripts/check-dist.mjs
```

`scripts/check-dist.mjs` fails the build if a page, a raw `.md` copy or `llms.txt` is missing, if an internal link or `#fragment` does not resolve, if the homepage's HTML, CSS and JS exceed 150 KB (fonts excluded), or if a build-machine path leaked into the output.

`public/og.png` (the link-preview image) is committed; regenerate it with `NODE_PATH=$(npm root -g) node scripts/og.mjs` after changing the headline or the verdict colours (needs Playwright).

## Deploy

`.github/workflows/deploy.yml` builds every pull request and deploys every push to `main`. It also runs by hand (Actions → Deploy memprove.dev → Run workflow) and on a `repository_dispatch` event of type `memprove-updated`, so memprove/memprove can ask for a rebuild after a release.

One-time setup, before the first merge to `main`:

1. Settings → Pages → Build and deployment → Source: **GitHub Actions**. With "Deploy from a branch", GitHub would publish this repository's source files instead of the site.
2. The custom domain `memprove.dev` stays as set in the Pages settings; `public/CNAME` only keeps it in the artifact.
3. Optional: a repository variable `MEMPROVE_REF` (Settings → Secrets and variables → Actions → Variables) pins the docs to a tag such as `v0.1.0`; without it the docs follow memprove's `main`.

## Design

Light, grid-paper page with dark terminal blocks; Inter, Source Serif 4 and IBM Plex Mono (self-hosted through Fontsource). The tokens are in `src/styles/tokens.css`: the base layer (paper, ink, lines, type, terminal) is meant to be shared by future products, and the four verdict colours belong to memprove. A verdict is always shown with its word, never by colour alone. Without JavaScript, or with reduced motion, every figure shows a still frame.

The site sets no cookies and loads nothing from third parties.
