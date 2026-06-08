# Versionshanterad DMS-checklista — fillagring via CVAPI (in-memory)

## Problem & mål

Det som sänkte oss i fredags var **incheckningen av filen**: nuvarande FM skriver PDF:en
till en temp-fil på appservern (`OPEN DATASET`/`TRANSFER`) och checkar in via `SAPFTPA`
(kräver `S_DATASET`) — bräckligt och felbenäget. SAP:s egen `create_dms_from_spool`
(include `LEAM_CL_FOLF01`) gör det **in-memory**. Mål: bygg fillagringen på samma sätt.

## Låsta beslut (ändras inte)

- **Fillagring = CVAPI-familjen, in-memory** (`pf_content_provide='TBL'`). Ingen temp-fil,
  inget `S_DATASET`/SAPFTPA. SAP:s interna metod för exakt detta scenario.
- **Nytt dokument vs ny version**: logiken behålls (`find_existing_doc`).
- **Identitet/klassificering**: 5 egenskaper `D_CL_PLNTY/PLNNR/PLNAL/WERKS/MATNR`
  (klasstyp `017`, klass `D_CL`) + tekniskt objekt (EQUI/IFLOT) som objektlänk.
- **Scenario 3** (omkörning av samma lot): uppskjutet (se Framåtblick).

## CVAPI-familjen vi använder

- `CVAPI_DOC_CREATE` — nytt DIR med innehåll (scenario 1).
- `CVAPI_DOC_CHECKIN` — original på ny version (scenario 2) och framtida ersättning på
  samma version.
- `CVAPI_DOC_CHECKOUT_VIEW` — checka ut original in-memory (framtida scenario 3).

Mekaniken (ur standarden): `CONVERT_OTFSPOOLJOB_2_PDF (pdf_destination='X')` →
`SCMS_XSTRING_TO_BINARY` → `DRAO`-tabell → CVAPI med `pf_content_provide='TBL'`,
`pt_content`/`pt_files_x`/`pt_drad_x`/`pt_drat_x`. Returnerar dokumentnyckeln.
CVAPI har **ingen klassificeringsparameter** → klassificering sätts separat
(`BAPI_OBJCL_CHANGE`) på den returnerade nyckeln.

## Status & doktyp (viktig upptäckt)

För att kunna **låsa upp klassificeringen** i en låst/releasad status krävs statustyp `L`
(semi-lock). Statustyp `L` **kan inte vara initialstatus** → systemet kan inte längre
auto-sätta "released" vid skapande. Konsekvens: **dokumentet skapas i en icke-releasad
initialstatus, och programmet sätter released explicit som sista steg** (vi tar över den
transitionen — `rel_auto = abap_false`, `set_status`). För ny version krävs dessutom att
den releasade statusen tillåter **ändring av original** (statustyp `O`).

Detta gäller oavsett:
- **Primär väg** — omkonfigurera den delade doktypens statusnätverk (icke-releasad initial
  → `RE` som typ `L`). OBS: påverkar alla dokument på den doktypen — bekräfta mot kund.
- **Fallback** — dedikerad Z-doktyp med samma nätverk (`In Work` → `RE` typ `L` → arkiv).

ABAP-flödet är **identiskt** i båda fallen. FM:en pekar på doktypen via `gc_doctype`
(fallback `otpl-doctype`).

## Flöde

**Scenario 1 — första version** (`create_first_version`):
1. `CVAPI_DOC_CREATE` in-memory: `gc_doctype`, **icke-releasad initialstatus**, två
   objektlänkar (tekniskt objekt + `PMAUFK`), beskrivning, PDF-innehåll. → nyckel. `COMMIT`.
2. `BAPI_OBJCL_CHANGE` — 5 klass-egenskaper (tillåtet i icke-releasad status). `COMMIT`.
3. `set_status` → **released explicit** (fil finns + klassificering klar). `COMMIT`.

**Scenario 2 — ny version** (`create_new_version`):
1. `BAPI_DOCUMENT_CREATENEWVRS2` (kopierar länkar + klassificering; `copyoriginals='X'`).
   `COMMIT`.
2. `CVAPI_DOC_CHECKIN` — nya PDF:en in-memory på nya versionen. `COMMIT`.
3. Säkerställ länkar/egenskaper; `set_status` released; arkivera föregående version. `COMMIT`.

## Ändringar (en fil: `zvfi_fg_e_am_d_cr_dms_lot_ver.abap`)

**Ta bort (temp-fil):** `write_pdf_tempfile`, `fill_bapi_file_entry`; ersätt `checkin_pdf`.
**Lägg till:** konstant `gc_doctype`; `build_drao_content` (xstring → DRAO);
`create_doc_with_content` (`CVAPI_DOC_CREATE`, icke-releasad); `checkin_content`
(`CVAPI_DOC_CHECKIN`).
**Ändra:** `create_first_version` → CVAPI + `BAPI_OBJCL_CHANGE` + explicit release;
`create_new_version` → `checkin_content`; använd `gc_doctype`; **staged commits**;
explicit release alltid (`rel_auto = abap_false`).
**Oförändrat:** guard clauses, `get_tech_object`, `build_key_chars`, `generate_spool`,
`spool_to_pdf`, `find_existing_doc`, idempotens-skip, `determine_statuses`, `lock_series`,
protokoll/`add_msg_to_log`.
**Spara** standardkällan `create_dms_from_spool` som referensfil i repot.

> Projektkopian `plans/fillagring-omstart.md` synkas när vi lämnar plan-läget.

## Framåtblick (utanför nuvarande scope, men API-valet stödjer det)

Scenario 3-variant: backat usage decision → satt igen på **samma** inspection lot, där
filen ändrats. Önskat: behåll versionen, byt original. Lösning med CVAPI:
`CVAPI_DOC_CHECKOUT_VIEW` (checka ut) → `CVAPI_DOC_CHECKIN` (checka in ny fil på samma
version). Med **content versions** aktiverat blir gamla originalet en content-version
(Not-Active) och nya Active → full spårbarhet. Fallgrop att hantera då: naiv check-in kan
skapa ett *andra* original i stället för att ersätta. Inget av detta byggs nu, men CVAPI är
valt just för att det täcker även detta — till skillnad från BAPI:erna för in-memory.

## Att verifiera på systemet (config)

- Statusnätverk: icke-releasad initialstatus + `RE` som typ `L` (semi-lock, klassificering
  editerbar). Statustyp `O` om original ska kunna bytas (ny version / framtida scenario 3).
- Mellan-commits: bekräfta att `BAPI_OBJCL_CHANGE` / `CVAPI_DOC_CHECKIN` behöver
  dokumentet committat först.
- `determine_statuses` plockar rätt statusar ur `TDWS` (released `FRKNZ='X'`, arkiv
  `DOSAR='A'`).

## Verifiering (end-to-end)

1. **Scenario 1** — lot utan tidigare dokument: DIR skapas in-memory i icke-releasad
   status, klassificeras (5 chars), länkas, sätts sedan released av programmet. `CV03N`:
   originalet öppnas, status released, klassificering finns, **ingen temp-fil**.
2. **Scenario 2** — UD på en *annan* lot, samma objekt + provplan: ny version, ny PDF
   incheckad in-memory, föregående version arkiverad.
3. `DIR_TEMP` orört; inget `S_DATASET` krävs.
4. `I_TEST='X'` — inga DB-ändringar; `E_PROTOCOL` + applikationslogg kompletta (ingen BL203).
5. Scenario 3: omkörning av samma lot hoppas fortfarande över.
