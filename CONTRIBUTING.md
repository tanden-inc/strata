# Contributing

## Setup

```bash
make setup
```

This installs the git hooks (`.githooks/pre-commit`) and refreshes the mooncakes index.
The pre-commit hook runs `moon fmt --check`, `moon check --deny-warn` and `moon info`; if an interface file
(`pkg.generated.mbti`) changes, the commit stops so you can review and stage the API diff deliberately.

## Workflow

Strata is developed test-first. The rules of the road are in [AGENTS.md](AGENTS.md): package map, API conventions,
the TDD loop, and how snapshots are updated. In short:

1. Write or extend a test in the package's `*_test.mbt`.
2. Run it: `moon test --target js path/to/pkg` (js isolates panics per test) or `moon test --target native`.
3. Implement until green, then `moon info && moon fmt` and review the `.mbti` diff.

## Pull requests

- Keep public API changes visible in `pkg.generated.mbti`; explain them in the PR description.
- Add a line to `CHANGELOG.md` under *Unreleased*.
- CI runs `make ci`; run it locally before pushing.
