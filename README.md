# ZVFI_FG_E_AM_D_CR_DMS_LOT_VER

Version-managed DMS checklist documents for QM follow-up actions (SAP EAM/QM).

Standard `EAM_CL_CREATE_DMS_LOT` creates a **new DMS document for every completed
checklist**. This custom function module instead creates a **new version of an
existing document** for the same technical object + inspection plan, archives the
previous version, and releases the newest one.

## What it does

1. **Guard clauses** mirror the standard FM (inspection lot/order read,
   `cl_eam_cl_cu=>otpl_read`, workpaper = `EAM_CL_PRINT`, form title).
2. **Statuses from customizing** – released/archived statuses are read at runtime
   from DMS customizing table `TDWS` per document type:
   - released = `TDWS-FRKNZ = 'X'`
   - archived = status type `TDWS-DOSAR = 'A'`
   - the `gc_status_*` constants are only a fallback.
3. **Technical object per lot** – taken directly from `i_qals`
   (`LS_EQUNR` → `EQUI`, otherwise `LS_TPLNR` → `IFLOT`), because an order can
   carry an object list with one inspection lot per object.
4. **Spool → PDF** – `EAM_CL_PRINT` spool converted to PDF.
5. **Find existing document** – `DRAD` on doctype + object link, then matches the
   classification (class type `017`, class `D_CL`) on **individual characteristics**
   (no concatenation):

   | Characteristic | Source | Type |
   |----------------|--------|------|
   | `D_CL_PLNTY`   | `QALS-PLNTY` | CHAR1  |
   | `D_CL_PLNNR`   | `QALS-PLNNR` | CHAR8  |
   | `D_CL_PLNAL`   | `QALS-PLNAL` | CHAR2  |
   | `D_CL_WERKS`   | `QALS-WERK`  | CHAR4  |
   | `D_CL_MATNR`   | `QALS-MATNR` | CHAR18 |

6. **First version** – `BAPI_DOCUMENT_CREATE2` + classification via `BAPI_OBJCL_CHANGE`.
7. **New version** – `BAPI_DOCUMENT_CREATENEWVRS2`, check-in new PDF
   (`BAPI_DOCUMENT_CHECKIN2`), re-assert characteristics, archive the previous version.
8. **Concurrency (optional)** – `ENQUEUE` on the series via an optional customer lock
   object (single key field `SCOPE`, CHAR50, mode E), released at `COMMIT WORK`.
   Degrades gracefully with a warning if the lock object is missing.
9. **Idempotency (optional)** – if `gc_char_lot` is set, `PRUEFLOS` is stored on the
   version so re-running the same lot does not create a duplicate.
10. **Logging/commit** – builds `E_PROTOCOL`, `cl_eam_cl_msg_tool=>add_msg_to_log`,
    `COMMIT WORK` unless `I_TEST`.

## Files

- [`zvfi_fg_e_am_d_cr_dms_lot_ver.abap`](zvfi_fg_e_am_d_cr_dms_lot_ver.abap) – the function module + helper FORMs.
- [`plans/`](plans/) – all plans and design docs for this work (see [`plans/README.md`](plans/README.md)); the design document moved to [`plans/design-dokument.html`](plans/design-dokument.html).

## Configuration prerequisites

- Document class `D_CL` (class type `017`) with characteristics `D_CL_PLNTY`,
  `D_CL_PLNNR`, `D_CL_PLNAL`, `D_CL_WERKS`, `D_CL_MATNR`.
- A document type whose status network allows Released → Archived, with the
  released status flagged (`FRKNZ`) and an Archive status type (`DOSAR = 'A'`).
- Optional: a customer lock object for concurrency control and a characteristic
  for lot-based idempotency.

## Backlog

- **Content versions**: when a protocol already exists for the lot, update the
  existing version with a new PDF (capture adjustments) instead of skipping.
  Requires content versions on the document type, check-out/replace of the
  original, and a size/hash comparison to avoid unnecessary content instances.

## Note

The standard SAP reference sources used during design
(`EAM_CL_CREATE_DMS_LOT`, `EAM_CL_CREATE_DMS_ORDER`) are intentionally **not**
included in this repository.
