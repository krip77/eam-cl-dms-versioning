*&---------------------------------------------------------------------*
*&  Belongs in the function group TOP include (e.g. LZ...TOP).
*&  Key characteristic (name/value) used to identify the document series.
*&---------------------------------------------------------------------*
TYPES: BEGIN OF ty_charkv,
         charname  TYPE atnam,
         charvalue TYPE atwrt,
       END OF ty_charkv,
       ty_charkv_t TYPE STANDARD TABLE OF ty_charkv WITH DEFAULT KEY.

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
*  Version-managed DMS checklist (replaces EAM_CL_CREATE_DMS_LOT as a
*  QM follow-up action). Lot-based: runs per inspection lot.
*
*  Logic:
*   1. Guard: read checklist/order/config, validate EAM_CL_PRINT.
*   2. Get the technical object PER LOT directly from i_qals (LS_EQUNR/LS_TPLNR).
*      (An order can have an object list -> one lot per object.)
*   3. Generate the protocol spool and convert it to PDF.
*   4. Search for an existing document (doctype + object link to the technical
*      object + matching inspection plan in the classification, class type 017).
*   5a. Found -> create a NEW VERSION, check in the new PDF, archive old version.
*   5b. Not found -> create the first version with links + classification + file.
*   6. Ensure links (order + technical object), set status, log.
*
*  >>> TO VERIFY/FILL IN ON THE SYSTEM (see constants below) <<<
*   - GC_CLASS + the GC_CHAR_* key characteristics (one per field) + GC_CHAR_LOT.
*   - GC_STATUS_RELEASED / GC_STATUS_ARCHIVED : document status (FR/AR in config).
*   - GC_IPRT_OPTIONS : must match the standard global 'id_iprt_options'
*     in the function group for EAM_CL_PRINT (memory id for print options).
*   - The status network of the doctype must allow the transition FR -> AR.
*   - The temporary PDF is written on the application server (DIR_TEMP);
*     requires S_DATASET. If needed: switch to in-memory checkin (CVAPI_DOC_CHECKIN).
*   - The FORM routines below go into the function group include (e.g. LZ...F01).
*----------------------------------------------------------------------

  CONSTANTS:
    gc_classtype       TYPE klassenart  VALUE '017',
    " >>> FILL IN: document class + characteristics per your configuration <<<
    gc_class           TYPE klasse_d    VALUE 'D_CL',
    " Key characteristics in class D_CL (class type 017) that identify the
    " document series - one CHAR field each (clean read/write, no parsing):
    "   D_CL_PLNTY (CHAR1)  task list type      <- QALS-PLNTY
    "   D_CL_PLNNR (CHAR8)  task list group     <- QALS-PLNNR
    "   D_CL_PLNAL (CHAR2)  group counter       <- QALS-PLNAL
    "   D_CL_WERKS (CHAR4)  plant               <- QALS-WERK
    "   D_CL_MATNR (CHAR18) material number      <- QALS-MATNR
    gc_char_plnty      TYPE atnam       VALUE 'D_CL_PLNTY',
    gc_char_plnnr      TYPE atnam       VALUE 'D_CL_PLNNR',
    gc_char_plnal      TYPE atnam       VALUE 'D_CL_PLNAL',
    gc_char_werk       TYPE atnam       VALUE 'D_CL_WERKS',
    gc_char_matnr      TYPE atnam       VALUE 'D_CL_MATNR',
    " Optional characteristic for lot no (idempotency). Leave SPACE to disable.
    gc_char_lot        TYPE atnam       VALUE space,
    " Fallback statuses only. At runtime they are read from DMS customizing
    " (TDWS) per doctype: released = TDWS-FRKNZ = 'X', archived = status type
    " TDWS-DOSAR = 'A'. These constants are used only if TDWS yields nothing.
    gc_status_released TYPE dokst       VALUE 'FR',
    gc_status_archived TYPE dokst       VALUE 'AR',
    " Memory ID the print control is exported to. Must match the standard global
    " 'id_iprt_options' that EAM_CL_PRINT imports from. In the EAM print framework
    " these memory-id constants equal their own name (cf. ID_IPRT_ORDDATA), so the
    " value is 'ID_IPRT_OPTIONS'. A mismatch makes EAM_CL_PRINT show the print dialog.
    gc_iprt_options    TYPE c LENGTH 30 VALUE 'ID_IPRT_OPTIONS',
    " >>> FILL IN: storage category for the original (else DMS default category) <<<
    gc_storage_cat     TYPE c LENGTH 10 VALUE space,
    " >>> OPTIONAL: customer lock object for concurrency control (single key
    "     field SCOPE, CHAR50, mode E). SPACE = locking disabled (FM still works). <<<
    gc_lock_object     TYPE c LENGTH 30 VALUE space,
    gc_wsappl_pdf      TYPE dappl       VALUE 'PDF',
    gc_fm_name         TYPE c LENGTH 30 VALUE 'Z_EAM_CL_CREATE_DMS_LOT_VRS'.

  DATA: ls_otpl       TYPE eam_cl_cu_otpl,
        ls_order      TYPE aufk,
        ls_t390       TYPE t390,
        ls_checklist  TYPE i_maintorderinspectionlot,
        lv_formtitle  TYPE papertext,
        lv_print_lang TYPE spras VALUE 'E',
        lv_aufnr      TYPE aufnr,
        lv_dokob      TYPE drad-dokob,
        lv_objky      TYPE drad-objky,
        lt_keys       TYPE ty_charkv_t,
        lv_lot_value  TYPE atwrt,
        lv_prueflos_c TYPE atwrt,
        lv_dummy      TYPE abap_bool,
        gd_spool_nr   TYPE tsp01-rqident,
        lv_lastspool  TYPE com_search_tv_last_spool,
        lv_pdf        TYPE xstring,
        lv_found      TYPE abap_bool,
        lv_skip       TYPE abap_bool,
        lv_locked     TYPE abap_bool,
        lv_err        TYPE abap_bool,
        lv_doknr      TYPE draw-doknr,
        lv_dokvr      TYPE draw-dokvr,
        lv_doktl      TYPE draw-doktl,
        lv_new_dokvr  TYPE draw-dokvr,
        lv_status_rel TYPE dokst,
        lv_status_arc TYPE dokst,
        lv_rel_auto   TYPE abap_bool,
        ls_return     TYPE bapiret2,
        lt_return     TYPE bapiret2_t,
        lt_logh       TYPE bal_t_logh,
        ls_prot       TYPE rqevp.

  CLEAR e_subrc.

*--- 1. Guard clauses (mirror the standard EAM_CL_CREATE_DMS_LOT) -------
  SELECT SINGLE * FROM i_maintorderinspectionlot
    INTO @ls_checklist
    WHERE inspectionlot = @i_qals-prueflos.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  IF ls_checklist-mainchecklistisdeactivated = abap_true.
    RETURN.
  ENDIF.

  lv_aufnr = ls_checklist-maintenanceorder.
  IF lv_aufnr IS INITIAL.
    lv_aufnr = i_qals-aufnr.
  ENDIF.

  SELECT SINGLE * FROM aufk INTO @ls_order WHERE aufnr = @lv_aufnr.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  cl_eam_cl_cu=>otpl_read(
    EXPORTING
      iv_order_type   = ls_order-auart
      iv_plant        = ls_order-werks
      iv_order_number = ls_order-aufnr
    IMPORTING
      es_otpl         = ls_otpl
    EXCEPTIONS
      not_found       = 1
      OTHERS          = 2 ).
  IF sy-subrc <> 0 OR ls_otpl-doctype IS INITIAL.
    RETURN.
  ENDIF.

  SELECT SINGLE * FROM t390 INTO @ls_t390
    WHERE pm_appl = 'O' AND workpaper = @ls_otpl-workpaper.
  IF sy-subrc <> 0 OR ls_t390-abapname <> 'EAM_CL_PRINT'.
    RETURN.
  ENDIF.

  SELECT SINGLE papertext FROM t390_t INTO @lv_formtitle
    WHERE spras     = @lv_print_lang
      AND pm_appl   = @ls_t390-pm_appl
      AND workpaper = @ls_t390-workpaper.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

*   Determine released/archived statuses from DMS customizing (TDWS) for this
*   doctype; constants are only the fallback if customizing yields nothing.
  PERFORM determine_statuses USING ls_otpl-doctype
                                   gc_status_released gc_status_archived
                             CHANGING lv_status_rel lv_status_arc lv_rel_auto.

*--- 2. Technical object PER LOT (directly from i_qals) ----------------
  PERFORM get_tech_object USING i_qals
                          CHANGING lv_dokob lv_objky.
  IF lv_dokob IS INITIAL.
*   The lot has no technical object -> versioning is not possible.
*   message: Inspection lot &1: follow-up action &2
    MESSAGE i040(eam_cl) WITH i_qals-prueflos gc_fm_name INTO ls_prot-prot_zeile.
    MOVE-CORRESPONDING sy TO ls_prot.
    APPEND ls_prot TO e_protocol.
    e_subrc = 4.
    RETURN.
  ENDIF.

*--- 3. Key characteristics + spool + PDF ------------------------------
  PERFORM build_key_chars USING i_qals
                                gc_char_plnty gc_char_plnnr gc_char_plnal
                                gc_char_werk gc_char_matnr
                          CHANGING lt_keys.

  PERFORM generate_spool USING ls_checklist ls_t390 lv_formtitle
                               lv_print_lang gc_iprt_options i_qals
                         CHANGING gd_spool_nr.
  IF gd_spool_nr IS INITIAL.
    e_subrc = 4.
    RETURN.
  ENDIF.

  IF i_dialog IS NOT INITIAL.
    lv_lastspool = gd_spool_nr.
    CALL FUNCTION 'COM_SE_SPOOL_DISPLAY'
      EXPORTING
        iv_spool_no = lv_lastspool.
  ENDIF.

  PERFORM spool_to_pdf USING gd_spool_nr
                       CHANGING lv_pdf lt_return.
  IF lv_pdf IS INITIAL.
    e_subrc = 4.
  ELSE.

*   Concurrency control: lock the series (tech object + insp plan). The lock is
*   released at COMMIT WORK so a parallel lot sees the committed document and
*   creates a NEW version instead of a duplicate.
    IF i_test IS INITIAL.
      PERFORM lock_series USING gc_lock_object ls_otpl-doctype lv_dokob
                                lv_objky lt_keys
                          CHANGING lt_return lv_locked.
    ENDIF.

*--- 4. Search for an existing document for tech object + insp plan -----
    PERFORM find_existing_doc USING ls_otpl-doctype lv_dokob lv_objky
                                    gc_class gc_classtype lt_keys
                              CHANGING lv_found lv_doknr lv_dokvr lv_doktl.

*   Idempotency: has this very lot already produced the version?
    IF lv_found = abap_true AND gc_char_lot IS NOT INITIAL.
      PERFORM read_doc_char USING ls_otpl-doctype lv_doknr lv_dokvr lv_doktl
                                  gc_class gc_classtype gc_char_lot
                            CHANGING lv_lot_value lv_dummy.
      lv_prueflos_c = i_qals-prueflos.
      IF lv_lot_value = lv_prueflos_c.
        lv_skip = abap_true.
      ENDIF.
    ENDIF.

*--- 5. Create version or first document (not in a test run) ----------
    IF i_test IS NOT INITIAL.
*     Test run: no database changes.
      e_subrc = 0.
    ELSEIF lv_skip = abap_true.
*     Lot already processed -> no new version.
      e_subrc = 0.
    ELSEIF lv_found = abap_true.
      PERFORM create_new_version USING ls_otpl lv_doknr lv_dokvr lv_doktl
                                       lv_pdf lv_formtitle lv_aufnr
                                       lv_dokob lv_objky i_qals
                                       gc_class gc_classtype lt_keys
                                       gc_char_lot
                                       lv_status_rel lv_rel_auto gc_wsappl_pdf
                                       gc_storage_cat
                                 CHANGING lv_new_dokvr lt_return ls_return.
      IF ls_return-type CA 'EAX'.
        e_subrc = 8.
      ELSE.
*       Archive the previous (formerly active) version.
        PERFORM set_status USING ls_otpl-doctype lv_doknr lv_dokvr lv_doktl
                                 lv_status_arc
                           CHANGING lt_return.
        e_subrc = 0.
      ENDIF.
    ELSE.
      PERFORM create_first_version USING ls_otpl lv_pdf lv_formtitle lv_aufnr
                                         lv_dokob lv_objky i_qals
                                         gc_class gc_classtype lt_keys
                                         gc_char_lot lv_status_rel lv_rel_auto
                                         gc_wsappl_pdf gc_storage_cat
                                   CHANGING lv_doknr lv_dokvr lv_doktl
                                            lt_return ls_return.
      IF ls_return-type CA 'EAX'.
        e_subrc = 8.
      ELSE.
        e_subrc = 0.
      ENDIF.
    ENDIF.
  ENDIF.

*--- 6. Evaluate overall result -------------------------------------
* Promote to a hard error if ANY sub-step (check-in, object links,
* classification, status) returned an error/abort - not just the first BAPI.
  IF e_subrc = 0.
    PERFORM returns_have_error USING lt_return CHANGING lv_err.
    IF lv_err = abap_true.
      e_subrc = 8.
    ENDIF.
  ENDIF.

*--- 7. Discard partial changes on error (before logging) -----------
* The document BAPIs run in update task and are only persisted by the COMMIT
* WORK below. On error we must NOT leave a half-created/half-versioned document,
* so roll back first; the log save then runs in a clean LUW.
* Safe here: this follow-up action is configured to run AFTER the usage decision
* is completed/committed, so the UD is in its own (already committed) LUW - this
* ROLLBACK only affects our own DMS changes, never the UD.
  IF i_test IS INITIAL AND e_subrc <> 0.
    ROLLBACK WORK.
  ENDIF.

*--- 8. Protocol + log + commit (common exit) -----------------------
* message: Inspection lot &1: follow-up action &2
  MESSAGE i040(eam_cl) WITH i_qals-prueflos gc_fm_name INTO ls_prot-prot_zeile.
  MOVE-CORRESPONDING sy TO ls_prot.
  APPEND ls_prot TO e_protocol.

  LOOP AT lt_return INTO ls_return WHERE message IS NOT INITIAL.
    CLEAR ls_prot.
    MOVE-CORRESPONDING sy TO ls_prot.
    ls_prot-prot_zeile = ls_return-message.
    APPEND ls_prot TO e_protocol.
  ENDLOOP.

* Drop incomplete return rows before logging. A BAPI 'return' on success is
* often an empty row (no type/id/number); the application log rejects such a
* row with message BL203 ("Message incomplete"). A valid message needs at
* least type + id (work area) + number.
  DELETE lt_return WHERE type IS INITIAL OR id IS INITIAL OR number IS INITIAL.

  IF i_no_log_save IS INITIAL AND
     i_test        IS INITIAL AND
     e_protocol[]  IS NOT INITIAL.
    cl_eam_cl_msg_tool=>add_msg_to_log(
      EXPORTING
        iv_subobject = cl_eam_cl_util=>gc_applog_subobject_sud
        iv_ordernr   = lv_aufnr
        it_return    = lt_return
        iv_not_save  = abap_false
        iv_alprog    = sy-cprog
      CHANGING
        ct_logs      = lt_logh ).
  ENDIF.

* Persist: on success the document + log; on error only the log (the document
* changes were already rolled back above).
  IF i_test IS INITIAL.
    COMMIT WORK.
  ENDIF.

ENDFUNCTION.

*&---------------------------------------------------------------------*
*&  Helper routines (placed in the function group include, e.g. LZ...F01)
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*&      Form  GET_TECH_OBJECT
*&---------------------------------------------------------------------*
*  Gets the technical object for the current lot directly from QALS.
*  An order can have an object list -> one lot per object, hence read per lot.
*----------------------------------------------------------------------*
FORM get_tech_object USING    is_qals  TYPE qals
                     CHANGING cv_dokob TYPE drad-dokob
                              cv_objky TYPE drad-objky.
  CLEAR: cv_dokob, cv_objky.
  IF is_qals-ls_equnr IS NOT INITIAL.
    cv_dokob = 'EQUI'.
    cv_objky = is_qals-ls_equnr.
  ELSEIF is_qals-ls_tplnr IS NOT INITIAL.
    cv_dokob = 'IFLOT'.
    cv_objky = is_qals-ls_tplnr.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  BUILD_KEY_CHARS
*&---------------------------------------------------------------------*
*  Builds the list of key characteristics that identify the document series:
*  one characteristic per field (plan type, group, group counter, plant,
*  material). The same list drives search, create and re-assert, so the flow
*  stays clean and there is no concatenation/parsing. Values come straight from
*  QALS in internal format, so search and store always match.
*----------------------------------------------------------------------*
FORM build_key_chars USING    is_qals       TYPE qals
                              iv_char_plnty TYPE atnam
                              iv_char_plnnr TYPE atnam
                              iv_char_plnal TYPE atnam
                              iv_char_werk  TYPE atnam
                              iv_char_matnr TYPE atnam
                     CHANGING ct_keys       TYPE ty_charkv_t.

  DATA ls_kv TYPE ty_charkv.

  CLEAR ct_keys.

  ls_kv-charname = iv_char_plnty.  ls_kv-charvalue = is_qals-plnty.  APPEND ls_kv TO ct_keys.
  ls_kv-charname = iv_char_plnnr.  ls_kv-charvalue = is_qals-plnnr.  APPEND ls_kv TO ct_keys.
  ls_kv-charname = iv_char_plnal.  ls_kv-charvalue = is_qals-plnal.  APPEND ls_kv TO ct_keys.
  ls_kv-charname = iv_char_werk.   ls_kv-charvalue = is_qals-werk.   APPEND ls_kv TO ct_keys.
  ls_kv-charname = iv_char_matnr.  ls_kv-charvalue = is_qals-matnr.  APPEND ls_kv TO ct_keys.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GENERATE_SPOOL
*&---------------------------------------------------------------------*
*  Generates the protocol via EAM_CL_PRINT (spool). Mirrors the standard
*  print block. Memory id for print options = standard id_iprt_options.
*----------------------------------------------------------------------*
FORM generate_spool USING    is_checklist  TYPE i_maintorderinspectionlot
                             is_t390       TYPE t390
                             iv_formtitle  TYPE papertext
                             iv_print_lang TYPE spras
                             iv_iprt_id    TYPE c
                             is_qals       TYPE qals
                    CHANGING cv_spool      TYPE tsp01-rqident.

  DATA: ls_wworkpaper TYPE wworkpaper,
        lv_device(10) TYPE c,
        lv_uname      TYPE syuname,
        lv_datum      TYPE sydatum,
        itcpp         TYPE itcpp,
        lv_uuid       TYPE sysuuid-c.

  CLEAR cv_spool.

  ls_wworkpaper-tdcovtitle = is_checklist-maintenanceorder.
  SHIFT ls_wworkpaper-tdcovtitle LEFT DELETING LEADING '0'.
  CONCATENATE iv_formtitle ls_wworkpaper-tdcovtitle
         INTO ls_wworkpaper-tdcovtitle SEPARATED BY space.
  ls_wworkpaper-pm_appl    = is_t390-pm_appl.
  ls_wworkpaper-workpaper  = is_t390-workpaper.
  ls_wworkpaper-tddest     = 'LP01'.
  ls_wworkpaper-tdcopies   = 1.
  ls_wworkpaper-tdimmed    = ''.
  ls_wworkpaper-tdnewid    = 'X'.
  ls_wworkpaper-tdarmod    = 1.
  ls_wworkpaper-print_lang = iv_print_lang.
  lv_device = 'PRINTER'.
  lv_uname  = sy-uname.
  lv_datum  = sy-datum.

  CALL FUNCTION 'SYSTEM_UUID_C_CREATE'
    IMPORTING
      uuid = lv_uuid.

  EXPORT wworkpaper     FROM ls_wworkpaper
         t390           FROM is_t390
         device         FROM lv_device
         print_language FROM iv_print_lang
         sy_uname       FROM lv_uname
         sy_datum       FROM lv_datum
    TO MEMORY ID iv_iprt_id.

  SUBMIT (is_t390-abapname)
    WITH p_aufnr  = is_checklist-maintenanceorder
    WITH p_qalsn  = is_qals-prueflos
    WITH p_mem_id = lv_uuid
    AND RETURN.

  IMPORT itcpp-tdspoolid FROM MEMORY ID lv_uuid.
  cv_spool = itcpp-tdspoolid.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  SPOOL_TO_PDF
*&---------------------------------------------------------------------*
FORM spool_to_pdf USING    iv_spool  TYPE tsp01-rqident
                  CHANGING cv_pdf    TYPE xstring
                           ct_return TYPE bapiret2_t.

  DATA: lt_pdf  TYPE TABLE OF tline,
        lv_size TYPE i.

  CLEAR cv_pdf.

  CALL FUNCTION 'CONVERT_OTFSPOOLJOB_2_PDF'
    EXPORTING
      src_spoolid              = iv_spool
      no_dialog                = abap_true
    IMPORTING
      pdf_bytecount            = lv_size
    TABLES
      pdf                      = lt_pdf
    EXCEPTIONS
      err_no_otf_spooljob      = 1
      err_no_spooljob          = 2
      err_no_permission        = 3
      err_conv_not_possible    = 4
      err_bad_dstdevice        = 5
      user_cancelled           = 6
      err_spoolerror           = 7
      err_temseerror           = 8
      err_btcjob_open_failed   = 9
      err_btcjob_submit_failed = 10
      err_btcjob_close_failed  = 11
      OTHERS                   = 12.
  IF sy-subrc <> 0.
    PERFORM append_sysmsg_return CHANGING ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
    EXPORTING
      input_length = lv_size
    IMPORTING
      buffer       = cv_pdf
    TABLES
      binary_tab   = lt_pdf
    EXCEPTIONS
      failed       = 1
      OTHERS       = 2.
  IF sy-subrc <> 0.
    PERFORM append_sysmsg_return CHANGING ct_return.
    CLEAR cv_pdf.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  WRITE_PDF_TEMPFILE
*&---------------------------------------------------------------------*
*  Writes the PDF to a temporary file on the application server (DIR_TEMP).
*  Returns the path for check-in via BAPI. Requires S_DATASET.
*----------------------------------------------------------------------*
FORM write_pdf_tempfile USING    iv_pdf  TYPE xstring
                        CHANGING cv_path TYPE string
                                 cv_ok   TYPE abap_bool.

  DATA: lv_dir  TYPE c LENGTH 100,
        lv_uuid TYPE sysuuid-c.

  CLEAR: cv_path, cv_ok.

  CALL 'C_SAPGPARAM' ID 'NAME'  FIELD 'DIR_TEMP'
                     ID 'VALUE' FIELD lv_dir.                 "#EC CI_CCALL
  CALL FUNCTION 'SYSTEM_UUID_C_CREATE'
    IMPORTING
      uuid = lv_uuid.

  cv_path = |{ lv_dir }/{ lv_uuid }.pdf|.

  OPEN DATASET cv_path FOR OUTPUT IN BINARY MODE.
  IF sy-subrc <> 0.
    CLEAR cv_path.
    RETURN.
  ENDIF.
  TRANSFER iv_pdf TO cv_path.
  CLOSE DATASET cv_path.
  cv_ok = abap_true.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  BUILD_CLASSIF_OBJECTKEY
*&---------------------------------------------------------------------*
*  Object key for document classification (class type 017):
*  DOKAR(3) + DOKNR(25) + DOKVR(2) + DOKTL(3).
*----------------------------------------------------------------------*
FORM build_classif_objectkey USING    iv_dokar TYPE draw-dokar
                                      iv_doknr TYPE draw-doknr
                                      iv_dokvr TYPE draw-dokvr
                                      iv_doktl TYPE draw-doktl
                             CHANGING cv_key   TYPE c.
  CLEAR cv_key.
  cv_key+0(3)  = iv_dokar.
  cv_key+3(25) = iv_doknr.
  cv_key+28(2) = iv_dokvr.
  cv_key+30(3) = iv_doktl.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  READ_DOC_CHAR
*&---------------------------------------------------------------------*
*  Reads a characteristic value from a document's classification.
*----------------------------------------------------------------------*
FORM read_doc_char USING    iv_dokar     TYPE draw-dokar
                            iv_doknr     TYPE draw-doknr
                            iv_dokvr     TYPE draw-dokvr
                            iv_doktl     TYPE draw-doktl
                            iv_class     TYPE klasse_d
                            iv_classtype TYPE klassenart
                            iv_charname  TYPE atnam
                   CHANGING cv_value     TYPE atwrt
                            cv_found     TYPE abap_bool.

  DATA: lv_key  TYPE c LENGTH 50,
        lt_num  TYPE TABLE OF bapi1003_alloc_values_num,
        lt_char TYPE TABLE OF bapi1003_alloc_values_char,
        lt_curr TYPE TABLE OF bapi1003_alloc_values_curr,
        lt_ret  TYPE TABLE OF bapiret2,
        ls_char TYPE bapi1003_alloc_values_char.

  CLEAR: cv_value, cv_found.

  PERFORM build_classif_objectkey USING iv_dokar iv_doknr iv_dokvr iv_doktl
                                  CHANGING lv_key.

  CALL FUNCTION 'BAPI_OBJCL_GETDETAIL'
    EXPORTING
      objectkey       = lv_key
      objecttable     = 'DRAW'
      classnum        = iv_class
      classtype       = iv_classtype
    TABLES
      allocvaluesnum  = lt_num
      allocvalueschar = lt_char
      allocvaluescurr = lt_curr
      return          = lt_ret.

  READ TABLE lt_char INTO ls_char WITH KEY charact = iv_charname.
  IF sy-subrc = 0.
    IF ls_char-value_neutral IS NOT INITIAL.
      cv_value = ls_char-value_neutral.
    ELSE.
      cv_value = ls_char-value_char.
    ENDIF.
    cv_found = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  FIND_EXISTING_DOC
*&---------------------------------------------------------------------*
*  Searches documents of the doctype that are linked to the technical object
*  and whose key characteristics (plan type/group/counter/plant/material) all
*  match the current lot. Returns the highest (active) version of the first hit.
*----------------------------------------------------------------------*
FORM find_existing_doc USING    iv_doctype   TYPE draw-dokar
                                iv_dokob     TYPE drad-dokob
                                iv_objky     TYPE drad-objky
                                iv_class     TYPE klasse_d
                                iv_classtype TYPE klassenart
                                it_keys      TYPE ty_charkv_t
                       CHANGING cv_found     TYPE abap_bool
                                cv_doknr     TYPE draw-doknr
                                cv_dokvr     TYPE draw-dokvr
                                cv_doktl     TYPE draw-doktl.

  DATA: lv_actvr TYPE draw-dokvr,
        lv_value TYPE atwrt,
        lv_dummy TYPE abap_bool,
        lv_match TYPE abap_bool,
        ls_kv    TYPE ty_charkv,
        ls_ret   TYPE bapiret2,
        lt_seen  TYPE SORTED TABLE OF draw-doknr WITH UNIQUE KEY table_line.

  CLEAR: cv_found, cv_doknr, cv_dokvr, cv_doktl.

  SELECT doknr, doktl FROM drad
    INTO TABLE @DATA(lt_links)
    WHERE dokar = @iv_doctype
      AND dokob = @iv_dokob
      AND objky = @iv_objky.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  LOOP AT lt_links INTO DATA(ls_link).
    INSERT ls_link-doknr INTO TABLE lt_seen.
    IF sy-subrc <> 0.
      CONTINUE.                       " doknr already processed
    ENDIF.

    CLEAR lv_actvr.
    CALL FUNCTION 'BAPI_DOCUMENT_GETACTVERSION'
      EXPORTING
        documenttype    = iv_doctype
        documentnumber  = ls_link-doknr
        documentpart    = ls_link-doktl
      IMPORTING
        documentversion = lv_actvr
        return          = ls_ret.
    IF lv_actvr IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_match = abap_true.
    LOOP AT it_keys INTO ls_kv.
      PERFORM read_doc_char USING iv_doctype ls_link-doknr lv_actvr ls_link-doktl
                                  iv_class iv_classtype ls_kv-charname
                            CHANGING lv_value lv_dummy.
      IF lv_value <> ls_kv-charvalue.
        lv_match = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF lv_match = abap_true.
      cv_found = abap_true.
      cv_doknr = ls_link-doknr.
      cv_dokvr = lv_actvr.
      cv_doktl = ls_link-doktl.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  CREATE_FIRST_VERSION
*&---------------------------------------------------------------------*
FORM create_first_version USING    is_otpl        TYPE eam_cl_cu_otpl
                                   iv_pdf         TYPE xstring
                                   iv_formtitle   TYPE papertext
                                   iv_aufnr       TYPE aufnr
                                   iv_dokob       TYPE drad-dokob
                                   iv_objky       TYPE drad-objky
                                   is_qals        TYPE qals
                                   iv_class       TYPE klasse_d
                                   iv_classtype   TYPE klassenart
                                   it_keys        TYPE ty_charkv_t
                                   iv_char_lot    TYPE atnam
                                   iv_status      TYPE dokst
                                   iv_rel_auto    TYPE abap_bool
                                   iv_wsappl      TYPE dappl
                                   iv_storage_cat TYPE c
                          CHANGING cv_doknr       TYPE draw-doknr
                                   cv_dokvr       TYPE draw-dokvr
                                   cv_doktl       TYPE draw-doktl
                                   ct_return      TYPE bapiret2_t
                                   cs_return      TYPE bapiret2.

  DATA: ls_docdata TYPE bapi_doc_draw2,
        lt_drad    TYPE TABLE OF bapi_doc_drad,
        ls_drad    TYPE bapi_doc_drad,
        lt_drat    TYPE TABLE OF bapi_doc_drat,
        ls_drat    TYPE bapi_doc_drat,
        lt_files   TYPE TABLE OF bapi_doc_files2,
        ls_files   TYPE bapi_doc_files2,
        lt_charval TYPE TABLE OF bapi_characteristic_values,
        ls_charval TYPE bapi_characteristic_values,
        lt_class   TYPE TABLE OF bapi_class_allocation,
        ls_class   TYPE bapi_class_allocation,
        ls_kv      TYPE ty_charkv,
        lv_doctype TYPE bapi_doc_aux-doctype,
        lv_path    TYPE string,
        lv_ok      TYPE abap_bool.

  CLEAR: cv_doknr, cv_dokvr, cv_doktl, cs_return.

  ls_docdata-documenttype = is_otpl-doctype.
* When the released status is the initial status type, leave it blank: the
* system assigns it automatically once the original is checked in. Setting it
* explicitly (it requires "check in required") would raise message 26269.
  IF iv_rel_auto = abap_false.
    ls_docdata-statusextern = iv_status.
  ENDIF.

* Object links: technical object + order
  ls_drad-objecttype = iv_dokob.
  ls_drad-objectkey  = iv_objky.
  APPEND ls_drad TO lt_drad.
  CLEAR ls_drad.
  ls_drad-objecttype = 'PMAUFK'.
  ls_drad-objectkey  = iv_aufnr.
  APPEND ls_drad TO lt_drad.

* Description
  ls_drat-language    = sy-langu.
  ls_drat-description = iv_formtitle.
  APPEND ls_drat TO lt_drat.

* Classification: class + all key characteristics (+ optional lot no)
  ls_class-classtype = iv_classtype.
  ls_class-classname = iv_class.
  ls_class-status    = '1'.
  APPEND ls_class TO lt_class.

  LOOP AT it_keys INTO ls_kv.
    CLEAR ls_charval.
    ls_charval-classtype = iv_classtype.
    ls_charval-classname = iv_class.
    ls_charval-charname  = ls_kv-charname.
    ls_charval-charvalue = ls_kv-charvalue.
    APPEND ls_charval TO lt_charval.
  ENDLOOP.

  IF iv_char_lot IS NOT INITIAL.
    CLEAR ls_charval.
    ls_charval-classtype = iv_classtype.
    ls_charval-classname = iv_class.
    ls_charval-charname  = iv_char_lot.
    ls_charval-charvalue = is_qals-prueflos.
    APPEND ls_charval TO lt_charval.
  ENDIF.

* Original (PDF) via a temporary application server file
  PERFORM write_pdf_tempfile USING iv_pdf CHANGING lv_path lv_ok.
  IF lv_ok = abap_true.
    ls_files-storagecategory = iv_storage_cat.
    ls_files-wsapplication   = iv_wsappl.
    ls_files-docfile         = lv_path.
    ls_files-description     = iv_formtitle.
    APPEND ls_files TO lt_files.
  ENDIF.

  CALL FUNCTION 'BAPI_DOCUMENT_CREATE2'
    EXPORTING
      documentdata         = ls_docdata
      pf_ftp_dest          = 'SAPFTPA'
      pf_http_dest         = 'SAPHTTPA'
    IMPORTING
      documenttype         = lv_doctype
      documentnumber       = cv_doknr
      documentpart         = cv_doktl
      documentversion      = cv_dokvr
      return               = cs_return
    TABLES
      objectlinks          = lt_drad
      documentdescriptions = lt_drat
      characteristicvalues = lt_charval
      classallocations     = lt_class
      documentfiles        = lt_files.

  APPEND cs_return TO ct_return.

* NOTE: the temp file is deliberately NOT deleted here. Some storage categories
* read the original file only at COMMIT WORK; an early DELETE would yield an
* empty original. Clean DIR_TEMP after commit or via basis housekeeping.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  CREATE_NEW_VERSION
*&---------------------------------------------------------------------*
*  Creates a new version of an existing document, copies object links +
*  classification, checks in the new PDF and ensures links/status.
*----------------------------------------------------------------------*
FORM create_new_version USING    is_otpl        TYPE eam_cl_cu_otpl
                                 iv_doknr       TYPE draw-doknr
                                 iv_dokvr       TYPE draw-dokvr
                                 iv_doktl       TYPE draw-doktl
                                 iv_pdf         TYPE xstring
                                 iv_formtitle   TYPE papertext
                                 iv_aufnr       TYPE aufnr
                                 iv_dokob       TYPE drad-dokob
                                 iv_objky       TYPE drad-objky
                                 is_qals        TYPE qals
                                 iv_class       TYPE klasse_d
                                 iv_classtype   TYPE klassenart
                                 it_keys        TYPE ty_charkv_t
                                 iv_char_lot    TYPE atnam
                                 iv_status      TYPE dokst
                                 iv_rel_auto    TYPE abap_bool
                                 iv_wsappl      TYPE dappl
                                 iv_storage_cat TYPE c
                        CHANGING cv_new_dokvr   TYPE draw-dokvr
                                 ct_return      TYPE bapiret2_t
                                 cs_return      TYPE bapiret2.

  DATA: lv_actvr      TYPE draw-dokvr,
        lv_num        TYPE i,
        lv_prueflos_c TYPE atwrt,
        ls_kv         TYPE ty_charkv,
        lt_copy       TYPE TABLE OF bapi_doc_drad_select,
        ls_copy       TYPE bapi_doc_drad_select,
        lv_doctype    TYPE bapi_doc_aux-doctype,
        lv_docnr      TYPE bapi_doc_aux-docnumber,
        lv_docpart    TYPE bapi_doc_aux-docpart,
        lv_docvers    TYPE bapi_doc_aux-docversion,
        ls_ret        TYPE bapiret2.

  CLEAR: cv_new_dokvr, cs_return.

* Active (highest) version as reference.
  lv_actvr = iv_dokvr.
  CALL FUNCTION 'BAPI_DOCUMENT_GETACTVERSION'
    EXPORTING
      documenttype    = is_otpl-doctype
      documentnumber  = iv_doknr
      documentpart    = iv_doktl
      documentversion = iv_dokvr
    IMPORTING
      documentversion = lv_actvr
      return          = ls_ret.
  IF lv_actvr IS INITIAL.
    lv_actvr = iv_dokvr.
  ENDIF.

* Next version number (numeric; adjust for alphanumeric versioning).
  lv_num = lv_actvr.
  lv_num = lv_num + 1.
  cv_new_dokvr = |{ lv_num WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.

* Copy all object links from the reference version.
  ls_copy-objecttype = '*'.
  APPEND ls_copy TO lt_copy.

  CALL FUNCTION 'BAPI_DOCUMENT_CREATENEWVRS2'
    EXPORTING
      refdocumenttype    = is_otpl-doctype
      refdocumentnumber  = iv_doknr
      refdocumentpart    = iv_doktl
      refdocumentversion = lv_actvr
      newdocumentversion = cv_new_dokvr
      copyoriginals      = space        " no original copied; new one checked in
      copyclassification = 'X'
      copydocbom         = space
    IMPORTING
      doctype            = lv_doctype
      docnumber          = lv_docnr
      docpart            = lv_docpart
      docversion         = lv_docvers
      return             = cs_return
    TABLES
      copyobjectlinks    = lt_copy.
  APPEND cs_return TO ct_return.
  IF cs_return-type CA 'EAX'.
    RETURN.
  ENDIF.

  IF lv_docvers IS NOT INITIAL.
    cv_new_dokvr = lv_docvers.
  ENDIF.

* Check in the new PDF as the original on the new version.
  PERFORM checkin_pdf USING is_otpl iv_doknr cv_new_dokvr iv_doktl
                            iv_pdf iv_formtitle iv_wsappl iv_storage_cat
                      CHANGING ct_return.

* Ensure links: technical object + current order (safety net).
  PERFORM ensure_object_link USING is_otpl-doctype iv_doknr cv_new_dokvr iv_doktl
                                   iv_dokob iv_objky
                             CHANGING ct_return.
  PERFORM ensure_object_link USING is_otpl-doctype iv_doknr cv_new_dokvr iv_doktl
                                   'PMAUFK' iv_aufnr
                             CHANGING ct_return.

* Ensure all key characteristics on the new version (regardless of copy config).
  LOOP AT it_keys INTO ls_kv.
    PERFORM set_doc_char USING is_otpl-doctype iv_doknr cv_new_dokvr iv_doktl
                               iv_class iv_classtype ls_kv-charname ls_kv-charvalue
                         CHANGING ct_return.
  ENDLOOP.

* Idempotency stamp (lot no) on the new version.
  IF iv_char_lot IS NOT INITIAL.
    lv_prueflos_c = is_qals-prueflos.
    PERFORM set_doc_char USING is_otpl-doctype iv_doknr cv_new_dokvr iv_doktl
                               iv_class iv_classtype iv_char_lot lv_prueflos_c
                         CHANGING ct_return.
  ENDIF.

* Status on the new version. Skip when the released status is the initial
* status type: the system assigns it automatically once the original is
* checked in; an explicit SETSTATUS would raise message 26269.
  IF iv_rel_auto = abap_false.
    PERFORM set_status USING is_otpl-doctype iv_doknr cv_new_dokvr iv_doktl iv_status
                       CHANGING ct_return.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  CHECKIN_PDF
*&---------------------------------------------------------------------*
FORM checkin_pdf USING    is_otpl        TYPE eam_cl_cu_otpl
                          iv_doknr       TYPE draw-doknr
                          iv_dokvr       TYPE draw-dokvr
                          iv_doktl       TYPE draw-doktl
                          iv_pdf         TYPE xstring
                          iv_formtitle   TYPE papertext
                          iv_wsappl      TYPE dappl
                          iv_storage_cat TYPE c
                 CHANGING ct_return      TYPE bapiret2_t.

  DATA: lt_files TYPE TABLE OF bapi_doc_files2,
        ls_files TYPE bapi_doc_files2,
        lv_path  TYPE string,
        lv_ok    TYPE abap_bool,
        ls_ret   TYPE bapiret2.

  PERFORM write_pdf_tempfile USING iv_pdf CHANGING lv_path lv_ok.
  IF lv_ok = abap_false.
    PERFORM append_sysmsg_return CHANGING ct_return.
    RETURN.
  ENDIF.

  ls_files-storagecategory = iv_storage_cat.
  ls_files-wsapplication   = iv_wsappl.
  ls_files-docfile         = lv_path.
  ls_files-description     = iv_formtitle.
  APPEND ls_files TO lt_files.

  CALL FUNCTION 'BAPI_DOCUMENT_CHECKIN2'
    EXPORTING
      documenttype    = is_otpl-doctype
      documentnumber  = iv_doknr
      documentpart    = iv_doktl
      documentversion = iv_dokvr
      pf_ftp_dest     = 'SAPFTPA'
      pf_http_dest    = 'SAPHTTPA'
    IMPORTING
      return          = ls_ret
    TABLES
      documentfiles   = lt_files.
  APPEND ls_ret TO ct_return.

* NOTE: see comment in CREATE_FIRST_VERSION - temp file is cleaned after commit.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  ENSURE_OBJECT_LINK
*&---------------------------------------------------------------------*
*  Adds an object link if it is missing on the version (idempotent).
*----------------------------------------------------------------------*
*  iv_dokob/iv_objky are generic (TYPE c) so that both typed fields and
*  literals ('PMAUFK', AUFNR of a different length) can be passed by reference.
FORM ensure_object_link USING    iv_doctype TYPE draw-dokar
                                 iv_doknr   TYPE draw-doknr
                                 iv_dokvr   TYPE draw-dokvr
                                 iv_doktl   TYPE draw-doktl
                                 iv_dokob   TYPE c
                                 iv_objky   TYPE c
                        CHANGING ct_return  TYPE bapiret2_t.

  DATA: lt_links TYPE TABLE OF bapi_doc_drad,
        ls_link  TYPE bapi_doc_drad,
        ls_ret   TYPE bapiret2.

  IF iv_objky IS INITIAL.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_DOCUMENT_GETDETAIL2'
    EXPORTING
      documenttype    = iv_doctype
      documentnumber  = iv_doknr
      documentpart    = iv_doktl
      documentversion = iv_dokvr
      getobjectlinks  = 'X'
    IMPORTING
      return          = ls_ret
    TABLES
      objectlinks     = lt_links.

  READ TABLE lt_links TRANSPORTING NO FIELDS
       WITH KEY objecttype = iv_dokob
                objectkey  = iv_objky.
  IF sy-subrc = 0.
    RETURN.                            " link already exists
  ENDIF.

  CLEAR lt_links.
  ls_link-objecttype = iv_dokob.
  ls_link-objectkey  = iv_objky.
  APPEND ls_link TO lt_links.

  CALL FUNCTION 'BAPI_DOCUMENT_CHANGE2'
    EXPORTING
      documenttype    = iv_doctype
      documentnumber  = iv_doknr
      documentpart    = iv_doktl
      documentversion = iv_dokvr
    IMPORTING
      return          = ls_ret
    TABLES
      objectlinks     = lt_links.
  APPEND ls_ret TO ct_return.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  SET_DOC_CHAR
*&---------------------------------------------------------------------*
*  Sets/updates a characteristic in the document's classification without
*  clearing the other values (reads existing first and sends everything back).
*----------------------------------------------------------------------*
FORM set_doc_char USING    iv_doctype   TYPE draw-dokar
                           iv_doknr     TYPE draw-doknr
                           iv_dokvr     TYPE draw-dokvr
                           iv_doktl     TYPE draw-doktl
                           iv_class     TYPE klasse_d
                           iv_classtype TYPE klassenart
                           iv_charname  TYPE atnam
                           iv_value     TYPE atwrt
                  CHANGING ct_return    TYPE bapiret2_t.

  DATA: lv_key  TYPE c LENGTH 50,
        lt_num  TYPE TABLE OF bapi1003_alloc_values_num,
        lt_char TYPE TABLE OF bapi1003_alloc_values_char,
        lt_curr TYPE TABLE OF bapi1003_alloc_values_curr,
        lt_ret  TYPE TABLE OF bapiret2,
        ls_char TYPE bapi1003_alloc_values_char.

  PERFORM build_classif_objectkey USING iv_doctype iv_doknr iv_dokvr iv_doktl
                                  CHANGING lv_key.

  CALL FUNCTION 'BAPI_OBJCL_GETDETAIL'
    EXPORTING
      objectkey       = lv_key
      objecttable     = 'DRAW'
      classnum        = iv_class
      classtype       = iv_classtype
    TABLES
      allocvaluesnum  = lt_num
      allocvalueschar = lt_char
      allocvaluescurr = lt_curr
      return          = lt_ret.

  READ TABLE lt_char ASSIGNING FIELD-SYMBOL(<char>)
       WITH KEY charact = iv_charname.
  IF sy-subrc = 0.
    <char>-value_neutral = iv_value.
    <char>-value_char    = iv_value.
  ELSE.
    ls_char-charact       = iv_charname.
    ls_char-value_neutral = iv_value.
    ls_char-value_char    = iv_value.
    APPEND ls_char TO lt_char.
  ENDIF.

  CALL FUNCTION 'BAPI_OBJCL_CHANGE'
    EXPORTING
      objectkey          = lv_key
      objecttable        = 'DRAW'
      classnum           = iv_class
      classtype          = iv_classtype
    TABLES
      allocvaluesnumnew  = lt_num
      allocvaluescharnew = lt_char
      allocvaluescurrnew = lt_curr
      return             = lt_ret.
  APPEND LINES OF lt_ret TO ct_return.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  SET_STATUS
*&---------------------------------------------------------------------*
FORM set_status USING    iv_doctype TYPE draw-dokar
                         iv_doknr   TYPE draw-doknr
                         iv_dokvr   TYPE draw-dokvr
                         iv_doktl   TYPE draw-doktl
                         iv_status  TYPE dokst
                CHANGING ct_return  TYPE bapiret2_t.

  DATA: ls_data  TYPE bapi_doc_draw2,
        ls_datax TYPE bapi_doc_draw2x,
        ls_ret   TYPE bapiret2.

  ls_data-statusextern  = iv_status.
  ls_datax-statusextern = 'X'.

  CALL FUNCTION 'BAPI_DOCUMENT_CHANGE2'
    EXPORTING
      documenttype    = iv_doctype
      documentnumber  = iv_doknr
      documentpart    = iv_doktl
      documentversion = iv_dokvr
      documentdata    = ls_data
      documentdatax   = ls_datax
    IMPORTING
      return          = ls_ret.
  APPEND ls_ret TO ct_return.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  DETERMINE_STATUSES
*&---------------------------------------------------------------------*
*  Reads the released/archived document statuses from DMS customizing (TDWS)
*  for the given document type, so the statuses are not hardcoded:
*    - Released = the status flagged as released   (TDWS-FRKNZ = 'X').
*    - Archived = the status whose status type is Archive (TDWS-DOSAR = 'A').
*  Falls back to the supplied default constants if customizing yields nothing.
*  ORDER BY makes the pick deterministic when several statuses qualify.
*
*  cv_rel_auto: TRUE when the released status is also the INITIAL status
*  (status type 'I'). Such a status is assigned automatically by the system on
*  save/check-in, so it must NOT be set explicitly. Here the released status is
*  configured with "check in required", so an explicit early SETSTATUS would
*  raise message 26269 ("Status can only be set when all originals are stored").
*----------------------------------------------------------------------*
FORM determine_statuses USING    iv_doctype  TYPE draw-dokar
                                 iv_def_rel  TYPE dokst
                                 iv_def_arch TYPE dokst
                        CHANGING cv_released TYPE dokst
                                 cv_archived TYPE dokst
                                 cv_rel_auto TYPE abap_bool.

  DATA lv_dosar TYPE tdws-dosar.

  cv_released = iv_def_rel.
  cv_archived = iv_def_arch.
  CLEAR cv_rel_auto.

  SELECT dokst FROM tdws UP TO 1 ROWS
    INTO @cv_released
    WHERE dokar = @iv_doctype
      AND frknz = @abap_true
    ORDER BY dokst.
  ENDSELECT.
  IF sy-subrc <> 0.
    cv_released = iv_def_rel.
  ENDIF.

  SELECT dokst FROM tdws UP TO 1 ROWS
    INTO @cv_archived
    WHERE dokar = @iv_doctype
      AND dosar = 'A'
    ORDER BY dokst.
  ENDSELECT.
  IF sy-subrc <> 0.
    cv_archived = iv_def_arch.
  ENDIF.

* Is the released status also the initial status (type 'I')?
  SELECT SINGLE dosar FROM tdws
    INTO @lv_dosar
    WHERE dokar = @iv_doctype
      AND dokst = @cv_released.
  IF sy-subrc = 0 AND lv_dosar = 'I'.
    cv_rel_auto = abap_true.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  LOCK_SERIES
*&---------------------------------------------------------------------*
*  Concurrency control: lock the logical series (tech object + insp plan) so
*  that parallel UDs do not create duplicates. Requires a customer lock object
*  whose single key field is named SCOPE (CHAR50), mode E. The lock is released
*  automatically at COMMIT WORK (default _SCOPE). If the lock object is missing
*  the call degrades to a warning - the FM still works but without concurrency.
*  _wait = 'X' serializes: a parallel lot waits until this one has committed.
*----------------------------------------------------------------------*
FORM lock_series USING    iv_lock_object TYPE c
                          iv_dokar       TYPE draw-dokar
                          iv_dokob       TYPE c
                          iv_objky       TYPE c
                          it_keys        TYPE ty_charkv_t
                 CHANGING ct_return      TYPE bapiret2_t
                          cv_locked      TYPE abap_bool.

  DATA: lv_scope TYPE c LENGTH 50,
        lv_fm    TYPE rs38l_fnam,
        ls_kv    TYPE ty_charkv.

  CLEAR cv_locked.
  IF iv_lock_object IS INITIAL.
    RETURN.                          " concurrency control disabled
  ENDIF.

* Scope = technical object + all key values. If it exceeds 50 chars it is
* truncated; that only over-serializes (safe), it never causes duplicates.
  lv_scope = iv_dokar && iv_dokob && iv_objky.
  LOOP AT it_keys INTO ls_kv.
    lv_scope = lv_scope && ls_kv-charvalue.
  ENDLOOP.
  CONDENSE lv_scope NO-GAPS.
  lv_fm = 'ENQUEUE_' && iv_lock_object.

  TRY.
      CALL FUNCTION lv_fm
        EXPORTING
          scope          = lv_scope
          _wait          = abap_true
        EXCEPTIONS
          foreign_lock   = 1
          system_failure = 2
          OTHERS         = 3.
      IF sy-subrc = 0.
        cv_locked = abap_true.
      ELSE.
*       Timeout/error while locking - continue best-effort with a warning.
        PERFORM append_text_msg USING 'W'
                'Concurrency lock not set - continuing without lock'
          CHANGING ct_return.
      ENDIF.
    CATCH cx_root.
*     Lock object missing or has a parameter other than SCOPE - degrade.
      PERFORM append_text_msg USING 'W'
              'Lock object missing/invalid - concurrency protection inactive'
        CHANGING ct_return.
  ENDTRY.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  APPEND_SYSMSG_RETURN
*&---------------------------------------------------------------------*
FORM append_sysmsg_return CHANGING ct_return TYPE bapiret2_t.
  DATA ls_ret TYPE bapiret2.
  ls_ret-type       = sy-msgty.
  ls_ret-id         = sy-msgid.
  ls_ret-number     = sy-msgno.
  ls_ret-message_v1 = sy-msgv1.
  ls_ret-message_v2 = sy-msgv2.
  ls_ret-message_v3 = sy-msgv3.
  ls_ret-message_v4 = sy-msgv4.
  IF ls_ret-type IS INITIAL.
    ls_ret-type = 'E'.
  ENDIF.
* Guarantee a complete message (avoid BL203). If no real system message was
* set, fall back to the generic free-text message 00(398) = &1&2&3&4.
  IF ls_ret-id IS INITIAL OR ls_ret-number IS INITIAL.
    ls_ret-id     = '00'.
    ls_ret-number = '398'.
    IF ls_ret-message_v1 IS INITIAL.
      ls_ret-message_v1 = 'Operation failed (no system message)'.
    ENDIF.
  ENDIF.
  APPEND ls_ret TO ct_return.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  APPEND_TEXT_MSG
*&---------------------------------------------------------------------*
*  Appends a complete free-text message to the return table using the generic
*  message 00(398) = &1&2&3&4, so the application log never rejects it (BL203).
*  The text is split across the four 50-char message variables.
*----------------------------------------------------------------------*
FORM append_text_msg USING    iv_type   TYPE bapiret2-type
                              iv_text   TYPE csequence
                     CHANGING ct_return TYPE bapiret2_t.

  DATA: ls_ret TYPE bapiret2,
        lv_c   TYPE c LENGTH 200.

  lv_c = iv_text.
  ls_ret-type       = iv_type.
  ls_ret-id         = '00'.
  ls_ret-number     = '398'.
  ls_ret-message_v1 = lv_c(50).
  ls_ret-message_v2 = lv_c+50(50).
  ls_ret-message_v3 = lv_c+100(50).
  ls_ret-message_v4 = lv_c+150(50).
  ls_ret-message    = iv_text.
  APPEND ls_ret TO ct_return.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  RETURNS_HAVE_ERROR
*&---------------------------------------------------------------------*
*  TRUE if any return row is an error ('E') or abort ('A'). Warnings ('W'),
*  info ('I') and success ('S') do not count - so the optional concurrency
*  warning never turns the run into a failure.
*----------------------------------------------------------------------*
FORM returns_have_error USING    it_return TYPE bapiret2_t
                        CHANGING cv_error  TYPE abap_bool.
  DATA ls_ret TYPE bapiret2.
  CLEAR cv_error.
  LOOP AT it_return INTO ls_ret WHERE type CA 'AE'.
    cv_error = abap_true.
    EXIT.
  ENDLOOP.
ENDFORM.
