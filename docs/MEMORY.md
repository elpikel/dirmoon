# Decision log

Dated decision log: what, why, what was rejected.

- 2026-11-24: Claude kit set up (copied from Ditstar). No issue tracker: tasks live locally in `.claude/work/<slug>/`; `/implement` may run on `main`. The product spec and design handover were saved as `docs/design/README.md`; its `tokens.css` and `reference/` files aren't in the repo yet.
- 2026-11-24: Styler, Credo `--strict` and ex_slop added (same setup and `.credo.exs` as Ditstar), all run by `mix precommit`; the Credo checks that Styler rewrites are disabled.
