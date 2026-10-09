# CLAUDE.md

## Style

- Keep everything short: replies, explanations, comments, docs.
- Use simple English: short sentences, common words.
- Avoid em dashes (—). Do not just swap them for "-" either. Rewrite the sentence instead, for
  example with a comma, a colon, brackets or two sentences.

## Commits

- English only.
- Conventional Commits prefix: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`, `build:`.
- Subject as short as possible. Imperative, lowercase, no trailing period.
- Body only when something genuinely cannot be inferred from the diff.
- Never add `Co-Authored-By`, "Generated with" or any other AI attribution to commits or PR descriptions.
- Do not commit or push before I have checked the changes locally and said they are fine. Then
  commit and push. Several attempts at the same thing make one commit, and attempts that did not
  work make none. Different things done in one session get a commit each. This also goes for
  releases and tags.

## Releases

Releases look like the ones of big projects such as Immich. `.github/release-notes.sh <tag>` builds
the notes: the entry from `CHANGELOG.md` (welcome and highlights), a support section, every commit
since the last release sorted by its prefix (`feat`, `fix`, `docs`, ...) with author and link, and
the full changelog link. So commit subjects end up in public: keep them clear.

1. Read `git log <last tag>..HEAD` and pick the version: only fixes → patch, something new → minor,
   something that breaks or needs the user to act → major.
2. Bump `VERSION` in the `Makefile` and add the entry at the top of `CHANGELOG.md`, in one commit
   (`chore: 1.4.0`).
3. Push, tag and create the release. The Deck's installer fetches the latest release.
   ```bash
   git tag v1.4.0 && git push github main v1.4.0 && git push origin main v1.4.0
   gh release create v1.4.0 --title v1.4.0 --notes "$(.github/release-notes.sh v1.4.0)"
   ```

A minor or major release (has `### Highlights`, gets a heading and the support section):

```markdown
## v1.4.0

_2026-09-24_

Welcome to moondeck-switchbot-wol `v1.4.0`! One or two sentences on what this release is about.

### 🚨 Breaking changes

- Only if there are any: what changed, and what the user has to do.

### Highlights

- First highlight, a few words
- Second highlight
```

A patch release is just a sentence or two, for example: "A small patch. The menu no longer closes
when you press Enter." The list of commits follows on its own.

- Write for users: what they notice, not how the code does it. Friendly and simple.
- Commands and settings they type go in backticks, buttons and labels in bold.
- To change an old release: edit its entry, commit, then
  `gh release edit <tag> --title <tag> --notes "$(.github/release-notes.sh <tag>)"`.

## README

- New UI (a menu, a screen, a setting) gets a screenshot in the README, next to the text about it:
  a real screenshot of it running in Konsole, in English. `scripts/sandbox.sh` gives it data to show.
- When a screen changes, take its screenshot again. The README never shows an old one.

## Testing

Never test against the real setup: the Deck's side edits MoonDeck's settings, and the PC's side
installs a system service that logs somebody in.

- `scripts/sandbox.sh [command]` runs the checkout with its own config, a MoonDeck with one PC
  (`tests/moondeck-settings.json`) and the PC's side as a dry run. It writes nothing outside the
  sandbox. The SwitchBot API is the real one unless `MSW_SB_API` points elsewhere.
- `make check` after every change. It also runs `tests/run.sh`, which tests both ends against a
  fake SwitchBot API, and the login trigger over a real socket.
- New strings: `make pot`, then translate them in `po/de.po`. `msw_msg` has to start its line,
  xgettext does not find it after `then` or `{`.
