---
name: project-layout
description: Canonical/active files of the CL FMs project and which files must never be archived (gitignored reference sources, intentional plan history).
metadata:
  type: project
---

Small single-purpose ABAP repo for a version-managed DMS checklist FM (EAM/QM/DMS).

Active / canonical:
- `zvfi_fg_e_am_d_cr_dms_lot_ver.abap` — the ONE active function module (FM `zvfi_fg_e_am_d_cr_dms_lot_ver`). This is the live source. Do not archive.
- `README.md` (repo root) — current project README.
- `plans/fillagring-omstart.md` — the CURRENT/active plan (in-memory CVAPI rework). Referenced as "🟢 Aktuell plan" in `plans/README.md`.
- `plans/README.md` — index that explicitly labels which plan docs are current vs history.

Intentional history (kept on purpose, NOT stale — do not archive):
- `plans/ursprunglig-plan.md` — first plan, all todos completed. `plans/README.md` lists it under "📚 Historik / underlag".
- `plans/design-dokument.html` — original design doc, listed as history in `plans/README.md`.

**Never archive (sensitive / by-design):**
- `eam_cl_create_dms_lot.abap`, `eam_cl_create_dms_order.abap`, `INCLUDE LEAM_CL_FOLF01.abap` — SAP standard reference sources, **gitignored on purpose** (proprietary, not for publication). Used as design reference; README explicitly notes they are intentionally excluded from VCS. Untracked != stale here.
- `.cursor/`, `.vscode/`, `.claude/` — editor/tooling dirs, gitignored.
- `.gitignore` — config.

**Why:** `plans/README.md` is the authoritative map of current-vs-history. Trust it before flagging any plan doc as stale.
**How to apply:** Before any future cleanup, re-read `plans/README.md` to see if the "current plan" pointer has moved. Only then could an older plan become a genuine archive candidate. See [[dms-supersession]].
