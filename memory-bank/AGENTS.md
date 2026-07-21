# Manually-Maintained Packages

Everything else `dots` installs comes from either nixpkgs proper (kept
current via `nix flake update` bumping the `nixpkgs` input) or
`modules/core/alien-packages.nix`'s native package-manager integration
(pacman/paru/zypper/tdnf — kept current by the OS's own package manager).
The packages below are the exceptions: each is built from a **pinned
upstream source snapshot with no nixpkgs attribute**, so nothing bumps
them automatically — they go stale silently unless a human (or an AI
instructed to do so) revisits them by hand.

Ask an AI to "update the manually-maintained packages" (or name one
specifically, e.g. "update lazytask") to work through the relevant entry
below. **Update this file itself** whenever a package is added, removed,
or its pinning mechanism changes (new/removed vendored patch, switched
hash type, etc.) — this list is only useful if it stays accurate.

## General update procedure (applies to every entry below)

1. Check the package's GitHub releases/tags page for a newer version
   than the one currently pinned.
2. Bump the version string and the `rev`/`url` field(s) that embed it.
3. **Deliberately break the fixed-output hash first**, then let Nix tell
   you the correct one — this is more reliable than trying to compute it
   out-of-band:
   - Set the `hash`/`sha256` field to `lib.fakeHash` (or any obviously
     wrong `sha256-AAAA...=` string).
   - Run the build (`nix build .#homeConfigurations.default.activationPackage
     --override-input dots-local git+file://$HOME/dots-local --no-link`
     works for all three below, or target the package's own derivation
     more narrowly if you know how it's exposed).
   - Nix's "hash mismatch" error prints the real `got:` hash — paste that
     back into the field.
4. If the derivation also has a `cargoHash`/`vendorHash`/`npmDepsHash`
   (lockfile-content hash, independent of the source hash above — see
   per-package notes below for which of these apply), repeat step 3 for
   that field too: it will *also* need bumping whenever `Cargo.lock`/
   `go.sum`/`package-lock.json` changed between the old and new version,
   which is effectively always.
5. If the package carries a vendored patch (currently only `lazytask` —
   see its entry), re-verify it still applies before finalizing the
   bump: clone the *new* tag fresh in a scratch dir (e.g. `/tmp/`) and
   run `patch -p1 --dry-run < pkgs/patches/<name>.patch`.
   - If it applies cleanly, done — no patch changes needed.
   - If it fails, the patched lines moved or changed shape upstream:
     manually re-apply the same *intent* (not the same text) against the
     new source, regenerate the patch via `git diff` in that scratch
     clone, and overwrite the vendored `.patch` file with the fresh
     diff. Never hand-edit an existing `.patch` file directly — always
     regenerate it from a real clone+diff, so it stays an honest,
     applicable diff against a known upstream commit. Verify the
     regenerated patch against a *second*, independent fresh clone of
     the same tag before trusting it (rules out local-state
     contamination in the first clone).
6. Rebuild and validate the same way any other change to this repo is
   validated: `nix flake check --override-input dots-local
   git+file://$HOME/dots-local`, then the full `activationPackage` build
   above, then (if on a machine where you can) a real `apply-dots` run
   plus a smoke-test of the actual binary (see each entry's "smoke test"
   note for what "works" means for that specific tool).
7. Add a dated entry to `memory-bank/decisions.md` noting the version
   bump (old → new version, whether the patch needed regenerating, and
   how it was validated) — follow the existing dated-entry format there.

---

## `pkgs/lazytask.nix` — `lazytask`

- **What it is:** a lazygit-style TUI for TaskChampion/Taskwarrior, not
  in nixpkgs and no AUR package exists either.
- **Upstream:** https://github.com/OsamaMahmood/lazytask — check the
  releases/tags page for anything newer than `v0.1.0`.
- **Fields to bump:** `version` (currently `"0.1.0"`); `src.rev` is
  `"v${version}"` so it follows automatically; `src.hash` (currently
  `"sha256-oY/FADDb0olkxFUuKyuCM5ZLc9sTRqPzry4zqki8fhI="`) must be
  cleared/recomputed per the general procedure; `cargoHash` (currently
  `"sha256-kgtZc1+Bmmdbv9seYTpXafZIfvqi886VyjgbP9ocTIc="`, from
  `rustPlatform.buildRustPackage`'s `Cargo.lock` vendoring) must also be
  recomputed — it will always change on a version bump since `Cargo.lock`
  will differ.
- **Vendored patch:** `pkgs/patches/lazytask-env-sync.patch`, applied via
  this file's `patches = [ ./patches/lazytask-env-sync.patch ];`. Adds a
  ~15-line opt-in hook to `src/app.rs`'s `App::new()` that calls the
  upstream `TaskChampionIntegration::configure_sync()` automatically when
  `LAZYTASK_SYNC_SERVER_URL`/`_CLIENT_ID`/`_ENCRYPTION_SECRET` env vars
  are all set (see `memory-bank/decisions.md`'s 2026-07-21 entries for
  the full investigation trail on *why* this exists — upstream has no
  native way to pre-configure sync at all). **Must be re-verified against
  every version bump** per step 5 above — `App::new()`'s surrounding code
  is exactly the kind of thing that can shift between releases.
- **Consumer to be aware of:** `modules/suites/pim-apps.nix`'s
  `lazytaskPkg` wrapper sets those three env vars from
  `dotsLocal.taskSync` and assumes `configure_sync()` is still reachable
  the same way the patch calls it — if a version bump changes
  `configure_sync()`'s signature or `SyncSettings`'s fields, the patch's
  Rust code (not just its applicability) needs updating to match, and the
  wrapper may need updating too if the env var contract changes.
- **Smoke test after bumping:** run `lazytask` under a pty (it's a TUI,
  won't run under a plain redirect) — e.g.
  `script -qec "timeout 3 lazytask" /tmp/out.log` — and confirm no
  panic/error, and that `~/.local/share/lazytask/client_id` still gets
  created/reused as expected.

## `pkgs/quarkdown.nix` — `quarkdown`

- **What it is:** a Markdown compiler ("Markdown with superpowers") not
  in nixpkgs, packaged from upstream's prebuilt per-platform release
  archive (not built from source — since v2.1.0 upstream ships a
  self-contained archive with its own launcher, jars, and bundled JRE, so
  this derivation is just "unpack and preserve the layout").
- **Upstream:** https://github.com/iamgio/quarkdown/releases — check for
  anything newer than `v2.4.0`.
- **Fields to bump:** `version` (currently `"2.4.0"`); `src.url` embeds
  `v${version}` and the fixed filename `quarkdown-linux-x64.zip` so it
  follows automatically as long as upstream keeps that exact asset naming
  convention (confirm the release still ships a `quarkdown-linux-x64.zip`
  asset — if upstream renames/restructures release assets, the URL
  itself needs manual adjustment, not just the version); `src.hash`
  (currently `"sha256-zyOqC+XWl7aY8UugO1QhzP74htJjR61iH5tyEtwH+c8="`) must
  be cleared/recomputed per the general procedure. No `cargoHash`/
  `vendorHash` (nothing is compiled — `dontBuild = true`).
- **Vendored patch:** none.
- **Smoke test after bumping:** `quarkdown --version` (or equivalent
  upstream-documented flag) matches the new version, and `mainProgram`
  (`bin/quarkdown`) still resolves its bundled JRE/launcher correctly
  without any Nix-provided `jre` — i.e. it runs at all, not just prints
  a version string.

## `modules/features/butterfish.nix` — `butterfish` (inline `butterfish-pkg`)

- **What it is:** an AI-shell wrapper (`bf` alias), built inline in this
  feature module (not a separate `pkgs/*.nix` file) via
  `pkgs.buildGoModule`, since it's small and only ever consumed from
  here.
- **Upstream:** https://github.com/bakks/butterfish/releases — check for
  anything newer than `v0.4.3`.
- **Fields to bump (inside the `butterfish-pkg` derivation):** `version`
  (currently `"0.4.3"`); `src.rev` is `"v${version}"` so it follows
  automatically; `src.sha256` (currently
  `"0gn3pyrc2n9xpls8hlvndi3ziijwq81xxls805xy40plkak14cw5"` — note: this
  one is in the older base32 `sha256` format, not the newer
  `sha256-base64=` form the other two entries use; either format works,
  but don't assume it's already SRI-formatted when copying a new value
  in) must be cleared/recomputed per the general procedure; `vendorHash`
  (currently `"sha256-b3clnCSWgf1Ro4qWUUmOjwpWEMzeff2O0zZV21efLdg="`, from
  `buildGoModule`'s `go.sum` vendoring) must also be recomputed — it will
  always change on a version bump since `go.sum` will differ.
- **Vendored patch:** none.
- **Note:** `doCheck = false` is intentional (upstream's tests try to
  download tiktoken encodings from the internet, which fails in the Nix
  sandbox) — don't "fix" this by re-enabling `doCheck` during a bump
  unless upstream has actually removed that network dependency; verify
  first rather than assuming it still applies.
- **Smoke test after bumping:** the `bf` alias
  (`butterfish shell -u '<baseUrl>' -m '<model>' -b <shellPkg>`) still
  launches without error against a real `dotsLocal.butterfishEndpoint`
  config — full functional (LLM roundtrip) testing isn't required, just
  confirm the binary starts and accepts its flags.
