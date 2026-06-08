# Planer – Z_EAM_CL_CREATE_DMS_LOT_VRS

Samlade planer och designunderlag för den versionshanterade DMS-checklistan.
Allt på ett ställe, i projektet.

## 🟢 Aktuell plan

- **[fillagring-omstart.md](fillagring-omstart.md)** — *aktiv, ej implementerad ännu.*
  Omstart av fillagringen: checka in checklistans PDF i DMS **in-memory** (SAP-standardens
  `CVAPI`-mekanism) i stället för dagens temp-fil-lösning. Kräver en **ny Z-dokumenttyp**
  med in-work initialstatus (skapa-i-work → checka in fil → klassificera → länkar →
  released). Senast uppdaterad 2026-06-06.

  > Radhänvisningar i planen (t.ex. `z_eam_cl_create_dms_lot_vrs.abap#L539`) pekar på
  > ABAP-filen i repo-roten, en nivå upp från den här mappen.

## 📚 Historik / underlag

- **[design-dokument.html](design-dokument.html)** — ursprungligt tekniskt designdokument
  (svenska) för hela den versionshanterade lösningen.
- **[ursprunglig-plan.md](ursprunglig-plan.md)** — den första planen (todos, alla
  "completed") från designfasen.

## Inte här

- **Prestanda-/OO-refaktorering** (omskrivning till `ZCL_…`, N+1-fixar): separat spår i en
  **egen git-branch** — medvetet utelämnad härifrån.
