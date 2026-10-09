# rossoctl/repo-template

A GitHub **template repository** carrying the rossoctl documentation convention: a `docs/`
tree where every kind of document has one home and one lifecycle, with CI gates that keep the
convention from rotting.

Derived from the shape proven in [`rossoctl/moca`](https://github.com/rossoctl/moca), plus an
append-only `docs/reports/` for measured implementation results.

> **Using this template?** Click **Use this template** above, then follow
> [Bootstrapping](#bootstrapping) to replace the placeholders. Delete this section and
> everything above `---` once done, replacing it with your project's own README.

## What you get

```
docs/
├── README.md                  # the router + the lifecycle rules (read this first)
├── <project>-overview.md      # executive overview — all essential info, kept current
├── glossary.md
├── specs/                     # deep designs — revised in place, versioned
│   ├── README.md              #   the registry: canonical ids + status
│   └── 0000-spec-template.md
├── adrs/                      # one decision per file — permanent, immutable
│   ├── README.md
│   └── 0000-adr-template.md
├── reports/                   # what a phase built and measured — append-only
│   ├── README.md
│   └── 0000-report-template.md
├── demos/                     # performed walkthroughs, in acts
│   └── README.md
├── notes/                     # investigations, runbooks, dead ends
│   └── README.md
└── plans/                     # LOCAL ONLY — gitignored, CI-enforced
    └── README.md
```

Plus: `CLAUDE.md` (agent instructions for the convention), `GOVERNANCE.md` (pointers to the
org-level documents), `LICENSE`, `CODEOWNERS`, `CONTRIBUTING.md`, the org lint configs, and a
`docs` CI workflow.

### The idea in one table

| Artifact     | Answers                              | Lifecycle                            |
| ------------ | ------------------------------------ | ------------------------------------ |
| **Overview** | the whole picture, briefly           | kept current                         |
| **Spec**     | what & why, in depth                 | **revised in place**, versioned      |
| **ADR**      | one decision + consequences          | **permanent, immutable**             |
| **Report**   | what was built and **measured**      | **append-only, never rewritten**     |
| **Demo**     | how to show it working               | updated when commands change         |
| **Note**     | an investigation, runbook, dead end  | dated, left as-is                    |
| **Plan**     | how, in what order                   | **local-only — written, run, deleted** |

The two distinctions that carry the most weight:

- **A plan is never committed.** Code is the source of truth for _how_; a committed plan is a
  stale copy of the code that misleads. Write it → execute it → delete it.
- **Specs revise, reports do not.** A spec says what _will_ be true and is corrected as you
  learn. A report says what _was_ true when measured, and is never retro-edited — because its
  most valuable content is the record of a prediction that turned out wrong.

## Bootstrapping

After creating your repo from this template:

```sh
# 1. Replace the placeholders. <PROJECT> is the repo name; <TEAM> the owning GitHub team.
grep -rl --exclude-dir=.git -e '<PROJECT>' -e '<TEAM>' . \
  | xargs sed -i '' -e 's|<PROJECT>|myrepo|g' -e 's|<TEAM>|myrepo-maintainers|g'
# (GNU sed: use `sed -i` without the '' argument)

# 2. Rename the overview to match.
git mv docs/PROJECT-overview.md docs/myrepo-overview.md

# 3. Install the hooks — the commit-msg one enforces the Assisted-By trailer.
pre-commit install && pre-commit install --hook-type commit-msg

# 4. Check it all still hangs together.
./scripts/check-no-committed-plans.sh && ./scripts/check-doc-headers.sh
```

Then:

- Fill in `docs/<project>-overview.md` — it is the front door.
- Confirm `@rossoctl/<TEAM>` in `CODEOWNERS` exists and has write access, or GitHub ignores
  the file silently.
- Add your language's ignores to `.gitignore` and hooks to `.pre-commit-config.yaml` (both
  have a marked section at the end).
- Replace this README.

Paths inside the templates that are still placeholders (`` `<file>.md` ``, `` `<topic>-report.md` ``)
are written as **inline code, not links**, so the link checker has nothing unresolvable to
chase while the template is still a template. Turn them into real markdown links as you fill
them in — CI then keeps them honest.

### What the template deliberately leaves out

Issue templates, the PR template and the org-wide security policy are **inherited
automatically** from [`rossoctl/.github`](https://github.com/rossoctl/.github), so they are not
duplicated here. `LICENSE` and `CODEOWNERS` _are_ included, because GitHub does not inherit
those — a repo without a LICENSE is all-rights-reserved whatever the org intends.

## CI gates

`.github/workflows/docs.yml` runs on every PR:

| Gate              | What it catches                                                      |
| ----------------- | -------------------------------------------------------------------- |
| No committed plans | a plan slipped into a PR; `.gitignore` alone is advisory             |
| Doc headers        | a spec without `Version:`/`Status:`, an ADR without `Deciders:`, a report without its "not verified" section |
| Markdown lint      | structural markdown problems (org `.markdownlint-cli2.yaml`)        |
| Link check         | relative cross-links broken by a rename (org `.lychee.toml`)         |

---

_Assisted-By: Claude Code_
