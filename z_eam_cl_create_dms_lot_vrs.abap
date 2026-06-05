FUNCTION z_eam_cl_create_dms_lot_vrs.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(I_QALS) LIKE  QALS STRUCTURE  QALS
*"     VALUE(I_QAVE) LIKE  QAVE STRUCTURE  QAVE
*"     VALUE(I_QAPO) TYPE  QAPO OPTIONAL
*"     VALUE(I_NO_LOG_SAVE) TYPE  XFELD DEFAULT SPACE
*"     VALUE(I_TEST) TYPE  XFELD DEFAULT SPACE
*"     VALUE(I_DIALOG) TYPE  XFELD DEFAULT SPACE
*"  EXPORTING
*"     VALUE(E_SUBRC) LIKE  SY-SUBRC
*"  TABLES
*"      E_PROTOCOL STRUCTURE  RQEVP
*"----------------------------------------------------------------------
*  QM follow-up adapter for version-managed DMS checklists.
*  All logic lives in ZCL_EAM_CL_CREATE_DMS_LOT_VRS.
*  Configuration (class, characteristics, statuses) is set here as
*  constants so SAP customizers have one place to adjust.
*----------------------------------------------------------------------
  CONSTANTS:
    " >>> FILL IN: document class + characteristics per your configuration <<<
    lc_class       TYPE klasse_d    VALUE 'D_CL',
    lc_classtype   TYPE klassenart  VALUE '017',
    lc_char_plnty  TYPE atnam       VALUE 'D_CL_PLNTY',
    lc_char_plnnr  TYPE atnam       VALUE 'D_CL_PLNNR',
    lc_char_plnal  TYPE atnam       VALUE 'D_CL_PLNAL',
    lc_char_werk   TYPE atnam       VALUE 'D_CL_WERKS',
    lc_char_matnr  TYPE atnam       VALUE 'D_CL_MATNR',
    " Optional: lot-number characteristic for idempotency. SPACE = disabled.
    lc_char_lot    TYPE atnam       VALUE space,
    " Fallback statuses if DMS customizing (TDWS) yields nothing.
    lc_status_rel  TYPE dokst       VALUE 'FR',
    lc_status_arc  TYPE dokst       VALUE 'AR',
    " Must match the standard 'id_iprt_options' in the EAM_CL_PRINT FG.
    lc_iprt_id     TYPE c LENGTH 30 VALUE 'IPRT_OPTIONS',
    " Storage category for the PDF original (SPACE = DMS default).
    lc_storage_cat TYPE c LENGTH 10 VALUE space,
    " Customer lock object for concurrency (single SCOPE key, mode E).
    " SPACE = locking disabled (FM still works without it).
    lc_lock_object TYPE c LENGTH 30 VALUE space,
    lc_wsappl_pdf  TYPE dappl       VALUE 'PDF'.

  DATA(lo) = NEW zcl_eam_cl_create_dms_lot_vrs(
    iv_class       = lc_class
    iv_classtype   = lc_classtype
    iv_char_plnty  = lc_char_plnty
    iv_char_plnnr  = lc_char_plnnr
    iv_char_plnal  = lc_char_plnal
    iv_char_werk   = lc_char_werk
    iv_char_matnr  = lc_char_matnr
    iv_char_lot    = lc_char_lot
    iv_lock_object = lc_lock_object
    iv_storage_cat = lc_storage_cat
    iv_wsappl      = lc_wsappl_pdf
    iv_iprt_id     = lc_iprt_id
    iv_status_rel  = lc_status_rel
    iv_status_arc  = lc_status_arc ).

  DATA lt_protocol TYPE zcl_eam_cl_create_dms_lot_vrs=>ty_protocol.

  lo->execute(
    EXPORTING
      is_qals        = i_qals
      is_qave        = i_qave
      is_qapo        = i_qapo
      iv_no_log_save = i_no_log_save
      iv_test        = i_test
      iv_dialog      = i_dialog
    IMPORTING
      ev_subrc       = e_subrc
    CHANGING
      ct_protocol    = lt_protocol ).

  APPEND LINES OF lt_protocol TO e_protocol.

ENDFUNCTION.
