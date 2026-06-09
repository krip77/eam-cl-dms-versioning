---
name: dms-supersession
description: History of the DMS FM file storage rework — file-storage to in-memory CVAPI; the ABAP file was renamed not duplicated, so no stale draft exists on disk.
metadata:
  type: project
---

The DMS check-in mechanism evolved: temp-file storage (OPEN DATASET/TRANSFER + SAPFTPA) → in-memory CVAPI check-in (`CVAPI_DOC_CREATE` / `CVAPI_DOC_CHECKIN`, `pf_content_provide='TBL'`).

Key fact for archiving: in commit `6e70437` ("Rework DMS file storage to in-memory CVAPI check-in") the ABAP file was **renamed** `z_eam_cl_create_dms_lot_vrs.abap` → `zvfi_fg_e_am_d_cr_dms_lot_ver.abap` (git shows it as a rename, not an add). So the old filename does NOT linger on disk as a stale draft. There is exactly one ABAP FM file.

As of 2026-06-08 the active FM genuinely contains `CVAPI_DOC_CREATE`/`CVAPI_DOC_CHECKIN` (verified by grep) — confirming it is the current in-memory implementation, not a pre-rework draft.

Known harmless staleness inside the active file (do NOT archive the file for this): the header comment block (around lines 48-49) still says the PDF is written to DIR_TEMP / S_DATASET "if needed switch to CVAPI" — leftover prose from before the rework. This is in-content drift, a candidate for a doc-comment fix by the developer, never an archive action.

**Why:** Establishes that the file-storage→in-memory pivot did NOT leave obsolete files behind, only a stale comment.
**How to apply:** If a future task asks to clean up "old DMS drafts", the answer is there are none on disk; only the header comment in the active FM is out of date. See [[project-layout]].
