*&---------------------------------------------------------------------*
*&  Belongs in the function group TOP include (e.g. LZ...TOP).
*&  Version-managed DMS checklist document for QM follow-up actions.
*&---------------------------------------------------------------------*
TYPES: BEGIN OF ty_charkv,
         charname  TYPE atnam,
         charvalue TYPE atwrt,
       END OF ty_charkv,
       ty_charkv_t TYPE STANDARD TABLE OF ty_charkv WITH DEFAULT KEY.

CLASS lcl_eam_dms_lot_vrs_service DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: ty_protocol_t TYPE STANDARD TABLE OF rqevp WITH DEFAULT KEY,

           BEGIN OF ty_request,
             qals        TYPE qals,
             qave        TYPE qave,
             qapo        TYPE qapo,
             no_log_save TYPE xfeld,
             test        TYPE xfeld,
             dialog      TYPE xfeld,
           END OF ty_request,

           BEGIN OF ty_doc_key,
             dokar TYPE draw-dokar,
             doknr TYPE draw-doknr,
             dokvr TYPE draw-dokvr,
             doktl TYPE draw-doktl,
           END OF ty_doc_key,

           BEGIN OF ty_result,
             subrc    TYPE sy-subrc,
             protocol TYPE ty_protocol_t,
             returns  TYPE bapiret2_t,
             document TYPE ty_doc_key,
           END OF ty_result.

    CLASS-METHODS execute
      IMPORTING
        is_request       TYPE ty_request
      RETURNING
        VALUE(rs_result) TYPE ty_result.

  PRIVATE SECTION.
    CONSTANTS:
      gc_classtype       TYPE klassenart  VALUE '017',
      gc_class           TYPE klasse_d    VALUE 'D_CL',
      gc_char_plnty      TYPE atnam       VALUE 'D_CL_PLNTY',
      gc_char_plnnr      TYPE atnam       VALUE 'D_CL_PLNNR',
      gc_char_plnal      TYPE atnam       VALUE 'D_CL_PLNAL',
      gc_char_werk       TYPE atnam       VALUE 'D_CL_WERKS',
      gc_char_matnr      TYPE atnam       VALUE 'D_CL_MATNR',
      gc_char_lot        TYPE atnam       VALUE space,
      gc_status_released TYPE dokst       VALUE 'FR',
      gc_status_archived TYPE dokst       VALUE 'AR',
      gc_iprt_options    TYPE c LENGTH 30 VALUE 'IPRT_OPTIONS',
      gc_storage_cat     TYPE c LENGTH 10 VALUE space,
      gc_wsappl_pdf      TYPE dappl       VALUE 'PDF',
      gc_fm_name         TYPE c LENGTH 30 VALUE 'Z_EAM_CL_CREATE_DMS_LOT_VRS'.

    TYPES: ty_class_num_t  TYPE STANDARD TABLE OF bapi1003_alloc_values_num WITH DEFAULT KEY,
           ty_class_char_t TYPE STANDARD TABLE OF bapi1003_alloc_values_char WITH DEFAULT KEY,
           ty_class_curr_t TYPE STANDARD TABLE OF bapi1003_alloc_values_curr WITH DEFAULT KEY,

           BEGIN OF ty_search_result,
             found       TYPE abap_bool,
             document    TYPE ty_doc_key,
             char_values TYPE ty_class_char_t,
           END OF ty_search_result.

    CLASS-METHODS build_key_chars
      IMPORTING
        is_qals        TYPE qals
      RETURNING
        VALUE(rt_keys) TYPE ty_charkv_t.

    CLASS-METHODS get_tech_object
      IMPORTING
        is_qals  TYPE qals
      EXPORTING
        ev_dokob TYPE drad-dokob
        ev_objky TYPE drad-objky.

    CLASS-METHODS determine_statuses
      IMPORTING
        iv_doctype  TYPE draw-dokar
      EXPORTING
        ev_released TYPE dokst
        ev_archived TYPE dokst.

    CLASS-METHODS find_existing_doc
      IMPORTING
        iv_doctype       TYPE draw-dokar
        iv_dokob         TYPE drad-dokob
        iv_objky         TYPE drad-objky
        it_keys          TYPE ty_charkv_t
      RETURNING
        VALUE(rs_result) TYPE ty_search_result.

    CLASS-METHODS read_doc_classification
      IMPORTING
        is_document TYPE ty_doc_key
      EXPORTING
        et_num      TYPE ty_class_num_t
        et_char     TYPE ty_class_char_t
        et_curr     TYPE ty_class_curr_t
        et_return   TYPE bapiret2_t.

    CLASS-METHODS get_char_value
      IMPORTING
        it_char         TYPE ty_class_char_t
        iv_charname     TYPE atnam
      RETURNING
        VALUE(rv_value) TYPE atwrt.

    CLASS-METHODS matches_key_chars
      IMPORTING
        it_char         TYPE ty_class_char_t
        it_keys         TYPE ty_charkv_t
      RETURNING
        VALUE(rv_match) TYPE abap_bool.

    CLASS-METHODS build_classif_objectkey
      IMPORTING
        is_document  TYPE ty_doc_key
      RETURNING
        VALUE(rv_key) TYPE c LENGTH 50.

    CLASS-METHODS generate_spool
      IMPORTING
        is_checklist    TYPE i_maintorderinspectionlot
        is_t390         TYPE t390
        iv_formtitle    TYPE papertext
        iv_print_lang   TYPE spras
        is_qals         TYPE qals
      RETURNING
        VALUE(rv_spool) TYPE tsp01-rqident.

    CLASS-METHODS display_spool
      IMPORTING
        iv_spool TYPE tsp01-rqident.

    CLASS-METHODS spool_to_pdf
      IMPORTING
        iv_spool  TYPE tsp01-rqident
      EXPORTING
        ev_pdf    TYPE xstring
      CHANGING
        ct_return TYPE bapiret2_t.

    CLASS-METHODS create_first_version
      IMPORTING
        is_otpl      TYPE eam_cl_cu_otpl
        iv_pdf       TYPE xstring
        iv_formtitle TYPE papertext
        iv_aufnr     TYPE aufnr
        iv_dokob     TYPE drad-dokob
        iv_objky     TYPE drad-objky
        is_qals      TYPE qals
        it_keys      TYPE ty_charkv_t
        iv_status    TYPE dokst
      EXPORTING
        es_doc       TYPE ty_doc_key
      CHANGING
        ct_return    TYPE bapiret2_t.

    CLASS-METHODS create_new_version
      IMPORTING
        is_otpl       TYPE eam_cl_cu_otpl
        is_document   TYPE ty_doc_key
        iv_pdf        TYPE xstring
        iv_formtitle  TYPE papertext
        iv_aufnr      TYPE aufnr
        iv_dokob      TYPE drad-dokob
        iv_objky      TYPE drad-objky
        is_qals       TYPE qals
        it_keys       TYPE ty_charkv_t
        iv_status_new TYPE dokst
        iv_status_old TYPE dokst
      EXPORTING
        es_doc        TYPE ty_doc_key
      CHANGING
        ct_return     TYPE bapiret2_t.

    CLASS-METHODS checkin_pdf
      IMPORTING
        is_document  TYPE ty_doc_key
        iv_pdf       TYPE xstring
        iv_formtitle TYPE papertext
      CHANGING
        ct_return    TYPE bapiret2_t.

    CLASS-METHODS write_pdf_tempfile
      IMPORTING
        iv_pdf  TYPE xstring
      EXPORTING
        ev_path TYPE string
        ev_ok   TYPE abap_bool.

    CLASS-METHODS ensure_object_links
      IMPORTING
        is_document TYPE ty_doc_key
        iv_dokob    TYPE drad-dokob
        iv_objky    TYPE drad-objky
        iv_aufnr    TYPE aufnr
      CHANGING
        ct_return   TYPE bapiret2_t.

    CLASS-METHODS set_doc_chars
      IMPORTING
        is_document TYPE ty_doc_key
        it_keys     TYPE ty_charkv_t
        iv_char_lot TYPE atnam
        is_qals     TYPE qals
      CHANGING
        ct_return   TYPE bapiret2_t.

    CLASS-METHODS set_status
      IMPORTING
        is_document TYPE ty_doc_key
        iv_status   TYPE dokst
      CHANGING
        ct_return   TYPE bapiret2_t.

    CLASS-METHODS append_sysmsg_return
      CHANGING
        ct_return TYPE bapiret2_t.

    CLASS-METHODS has_bapi_error
      IMPORTING
        it_return       TYPE bapiret2_t
      RETURNING
        VALUE(rv_error) TYPE abap_bool.

    CLASS-METHODS append_protocol_message
      IMPORTING
        iv_prueflos TYPE qals-prueflos
      CHANGING
        ct_protocol TYPE ty_protocol_t.

    CLASS-METHODS append_return_protocol
      IMPORTING
        it_return   TYPE bapiret2_t
      CHANGING
        ct_protocol TYPE ty_protocol_t.

    CLASS-METHODS save_log_and_commit
      IMPORTING
        iv_aufnr       TYPE aufnr
        iv_no_log_save TYPE xfeld
        iv_test        TYPE xfeld
        it_return      TYPE bapiret2_t
        it_protocol    TYPE ty_protocol_t.
ENDCLASS.

CLASS lcl_eam_dms_lot_vrs_service IMPLEMENTATION.
  METHOD execute.
    DATA: ls_otpl       TYPE eam_cl_cu_otpl,
          ls_order      TYPE aufk,
          ls_t390       TYPE t390,
          ls_checklist  TYPE i_maintorderinspectionlot,
          lv_aufnr      TYPE aufnr,
          lv_print_lang TYPE spras VALUE 'E',
          lv_formtitle  TYPE papertext,
          lv_dokob      TYPE drad-dokob,
          lv_objky      TYPE drad-objky,
          lt_keys       TYPE ty_charkv_t,
          lv_status_rel TYPE dokst,
          lv_status_arc TYPE dokst,
          ls_search     TYPE ty_search_result,
          lv_lot_value  TYPE atwrt,
          lv_prueflos_c TYPE atwrt,
          lv_skip       TYPE abap_bool,
          lv_spool      TYPE tsp01-rqident,
          lv_pdf        TYPE xstring.

    CLEAR rs_result.

    SELECT SINGLE * FROM i_maintorderinspectionlot
      INTO @ls_checklist
      WHERE inspectionlot = @is_request-qals-prueflos.
    IF sy-subrc <> 0 OR ls_checklist-mainchecklistisdeactivated = abap_true.
      RETURN.
    ENDIF.

    lv_aufnr = ls_checklist-maintenanceorder.
    IF lv_aufnr IS INITIAL.
      lv_aufnr = is_request-qals-aufnr.
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
      WHERE pm_appl = 'O'
        AND workpaper = @ls_otpl-workpaper.
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

    determine_statuses(
      EXPORTING
        iv_doctype  = ls_otpl-doctype
      IMPORTING
        ev_released = lv_status_rel
        ev_archived = lv_status_arc ).

    get_tech_object(
      EXPORTING
        is_qals  = is_request-qals
      IMPORTING
        ev_dokob = lv_dokob
        ev_objky = lv_objky ).
    IF lv_dokob IS INITIAL.
      append_protocol_message(
        EXPORTING
          iv_prueflos = is_request-qals-prueflos
        CHANGING
          ct_protocol = rs_result-protocol ).
      rs_result-subrc = 4.
      RETURN.
    ENDIF.

    lt_keys = build_key_chars( is_request-qals ).

*   Search and idempotency run before spool/PDF to avoid expensive reprints
*   when the lot has already created the target version.
    ls_search = find_existing_doc(
      iv_doctype = ls_otpl-doctype
      iv_dokob   = lv_dokob
      iv_objky   = lv_objky
      it_keys    = lt_keys ).

    IF ls_search-found = abap_true AND gc_char_lot IS NOT INITIAL.
      lv_lot_value = get_char_value(
        it_char     = ls_search-char_values
        iv_charname = gc_char_lot ).
      lv_prueflos_c = is_request-qals-prueflos.
      IF lv_lot_value = lv_prueflos_c.
        lv_skip = abap_true.
      ENDIF.
    ENDIF.

    IF is_request-test IS NOT INITIAL OR lv_skip = abap_true.
      rs_result-subrc = 0.
      rs_result-document = ls_search-document.
      append_protocol_message(
        EXPORTING
          iv_prueflos = is_request-qals-prueflos
        CHANGING
          ct_protocol = rs_result-protocol ).
      append_return_protocol(
        EXPORTING
          it_return   = rs_result-returns
        CHANGING
          ct_protocol = rs_result-protocol ).
      save_log_and_commit(
        iv_aufnr       = lv_aufnr
        iv_no_log_save = is_request-no_log_save
        iv_test        = is_request-test
        it_return      = rs_result-returns
        it_protocol    = rs_result-protocol ).
      RETURN.
    ENDIF.

    lv_spool = generate_spool(
      is_checklist  = ls_checklist
      is_t390       = ls_t390
      iv_formtitle  = lv_formtitle
      iv_print_lang = lv_print_lang
      is_qals       = is_request-qals ).
    IF lv_spool IS INITIAL.
      rs_result-subrc = 4.
      RETURN.
    ENDIF.

    IF is_request-dialog IS NOT INITIAL.
      display_spool( lv_spool ).
    ENDIF.

    spool_to_pdf(
      EXPORTING
        iv_spool  = lv_spool
      IMPORTING
        ev_pdf    = lv_pdf
      CHANGING
        ct_return = rs_result-returns ).
    IF lv_pdf IS INITIAL.
      rs_result-subrc = 4.
    ELSEIF ls_search-found = abap_true.
      create_new_version(
        EXPORTING
          is_otpl       = ls_otpl
          is_document   = ls_search-document
          iv_pdf        = lv_pdf
          iv_formtitle  = lv_formtitle
          iv_aufnr      = lv_aufnr
          iv_dokob      = lv_dokob
          iv_objky      = lv_objky
          is_qals       = is_request-qals
          it_keys       = lt_keys
          iv_status_new = lv_status_rel
          iv_status_old = lv_status_arc
        IMPORTING
          es_doc        = rs_result-document
        CHANGING
          ct_return     = rs_result-returns ).
      IF has_bapi_error( rs_result-returns ) = abap_true.
        rs_result-subrc = 8.
      ELSE.
        rs_result-subrc = 0.
      ENDIF.
    ELSE.
      create_first_version(
        EXPORTING
          is_otpl      = ls_otpl
          iv_pdf       = lv_pdf
          iv_formtitle = lv_formtitle
          iv_aufnr     = lv_aufnr
          iv_dokob     = lv_dokob
          iv_objky     = lv_objky
          is_qals      = is_request-qals
          it_keys      = lt_keys
          iv_status    = lv_status_rel
        IMPORTING
          es_doc       = rs_result-document
        CHANGING
          ct_return    = rs_result-returns ).
      IF has_bapi_error( rs_result-returns ) = abap_true.
        rs_result-subrc = 8.
      ELSE.
        rs_result-subrc = 0.
      ENDIF.
    ENDIF.

    append_protocol_message(
      EXPORTING
        iv_prueflos = is_request-qals-prueflos
      CHANGING
        ct_protocol = rs_result-protocol ).
    append_return_protocol(
      EXPORTING
        it_return   = rs_result-returns
      CHANGING
        ct_protocol = rs_result-protocol ).
    save_log_and_commit(
      iv_aufnr       = lv_aufnr
      iv_no_log_save = is_request-no_log_save
      iv_test        = is_request-test
      it_return      = rs_result-returns
      it_protocol    = rs_result-protocol ).
  ENDMETHOD.

  METHOD build_key_chars.
    rt_keys = VALUE #(
      ( charname = gc_char_plnty charvalue = is_qals-plnty )
      ( charname = gc_char_plnnr charvalue = is_qals-plnnr )
      ( charname = gc_char_plnal charvalue = is_qals-plnal )
      ( charname = gc_char_werk  charvalue = is_qals-werk  )
      ( charname = gc_char_matnr charvalue = is_qals-matnr ) ).
  ENDMETHOD.

  METHOD get_tech_object.
    CLEAR: ev_dokob, ev_objky.
    IF is_qals-ls_equnr IS NOT INITIAL.
      ev_dokob = 'EQUI'.
      ev_objky = is_qals-ls_equnr.
    ELSEIF is_qals-ls_tplnr IS NOT INITIAL.
      ev_dokob = 'IFLOT'.
      ev_objky = is_qals-ls_tplnr.
    ENDIF.
  ENDMETHOD.

  METHOD determine_statuses.
    ev_released = gc_status_released.
    ev_archived = gc_status_archived.

    SELECT dokst FROM tdws UP TO 1 ROWS
      INTO @ev_released
      WHERE dokar = @iv_doctype
        AND frknz = @abap_true
      ORDER BY dokst.
    ENDSELECT.
    IF sy-subrc <> 0.
      ev_released = gc_status_released.
    ENDIF.

    SELECT dokst FROM tdws UP TO 1 ROWS
      INTO @ev_archived
      WHERE dokar = @iv_doctype
        AND dosar = 'A'
      ORDER BY dokst.
    ENDSELECT.
    IF sy-subrc <> 0.
      ev_archived = gc_status_archived.
    ENDIF.
  ENDMETHOD.

  METHOD find_existing_doc.
    TYPES: BEGIN OF ty_link,
             doknr TYPE drad-doknr,
             doktl TYPE drad-doktl,
           END OF ty_link.

    DATA: lt_seen   TYPE SORTED TABLE OF ty_link WITH UNIQUE KEY doknr doktl,
          ls_doc    TYPE ty_doc_key,
          lv_actvr  TYPE draw-dokvr,
          ls_return TYPE bapiret2,
          lt_num    TYPE ty_class_num_t,
          lt_char   TYPE ty_class_char_t,
          lt_curr   TYPE ty_class_curr_t,
          lt_return TYPE bapiret2_t.

    CLEAR rs_result.

    SELECT doknr, doktl FROM drad
      INTO TABLE @DATA(lt_links)
      WHERE dokar = @iv_doctype
        AND dokob = @iv_dokob
        AND objky = @iv_objky.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_links INTO DATA(ls_link).
      INSERT VALUE #( doknr = ls_link-doknr doktl = ls_link-doktl ) INTO TABLE lt_seen.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      CLEAR lv_actvr.
      CALL FUNCTION 'BAPI_DOCUMENT_GETACTVERSION'
        EXPORTING
          documenttype    = iv_doctype
          documentnumber  = ls_link-doknr
          documentpart    = ls_link-doktl
        IMPORTING
          documentversion = lv_actvr
          return          = ls_return.
      IF lv_actvr IS INITIAL.
        CONTINUE.
      ENDIF.

      ls_doc = VALUE #( dokar = iv_doctype
                        doknr = ls_link-doknr
                        dokvr = lv_actvr
                        doktl = ls_link-doktl ).
      CLEAR: lt_num, lt_char, lt_curr, lt_return.
      read_doc_classification(
        EXPORTING
          is_document = ls_doc
        IMPORTING
          et_num      = lt_num
          et_char     = lt_char
          et_curr     = lt_curr
          et_return   = lt_return ).

      IF matches_key_chars( it_char = lt_char it_keys = it_keys ) = abap_true.
        rs_result-found       = abap_true.
        rs_result-document    = ls_doc.
        rs_result-char_values = lt_char.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_doc_classification.
    DATA lv_key TYPE c LENGTH 50.

    lv_key = build_classif_objectkey( is_document ).

    CALL FUNCTION 'BAPI_OBJCL_GETDETAIL'
      EXPORTING
        objectkey       = lv_key
        objecttable     = 'DRAW'
        classnum        = gc_class
        classtype       = gc_classtype
      TABLES
        allocvaluesnum  = et_num
        allocvalueschar = et_char
        allocvaluescurr = et_curr
        return          = et_return.
  ENDMETHOD.

  METHOD get_char_value.
    CLEAR rv_value.
    READ TABLE it_char INTO DATA(ls_char) WITH KEY charact = iv_charname.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF ls_char-value_neutral IS NOT INITIAL.
      rv_value = ls_char-value_neutral.
    ELSE.
      rv_value = ls_char-value_char.
    ENDIF.
  ENDMETHOD.

  METHOD matches_key_chars.
    rv_match = abap_true.
    LOOP AT it_keys INTO DATA(ls_key).
      IF get_char_value( it_char = it_char iv_charname = ls_key-charname ) <> ls_key-charvalue.
        rv_match = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_classif_objectkey.
    CLEAR rv_key.
    rv_key+0(3)  = is_document-dokar.
    rv_key+3(25) = is_document-doknr.
    rv_key+28(2) = is_document-dokvr.
    rv_key+30(3) = is_document-doktl.
  ENDMETHOD.

  METHOD generate_spool.
    DATA: ls_wworkpaper TYPE wworkpaper,
          lv_device(10) TYPE c,
          lv_uname      TYPE syuname,
          lv_datum      TYPE sydatum,
          itcpp         TYPE itcpp,
          lv_uuid       TYPE sysuuid-c.

    CLEAR rv_spool.

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
      TO MEMORY ID gc_iprt_options.

    SUBMIT (is_t390-abapname)
      WITH p_aufnr  = is_checklist-maintenanceorder
      WITH p_qalsn  = is_qals-prueflos
      WITH p_mem_id = lv_uuid
      AND RETURN.

    IMPORT itcpp-tdspoolid FROM MEMORY ID lv_uuid.
    rv_spool = itcpp-tdspoolid.
  ENDMETHOD.

  METHOD display_spool.
    DATA lv_lastspool TYPE com_search_tv_last_spool.

    lv_lastspool = iv_spool.
    CALL FUNCTION 'COM_SE_SPOOL_DISPLAY'
      EXPORTING
        iv_spool_no = lv_lastspool.
  ENDMETHOD.

  METHOD spool_to_pdf.
    DATA: lt_pdf  TYPE TABLE OF tline,
          lv_size TYPE i.

    CLEAR ev_pdf.

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
      append_sysmsg_return( CHANGING ct_return = ct_return ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING
        input_length = lv_size
      IMPORTING
        buffer       = ev_pdf
      TABLES
        binary_tab   = lt_pdf
      EXCEPTIONS
        failed       = 1
        OTHERS       = 2.
    IF sy-subrc <> 0.
      append_sysmsg_return( CHANGING ct_return = ct_return ).
      CLEAR ev_pdf.
    ENDIF.
  ENDMETHOD.

  METHOD create_first_version.
    DATA: ls_docdata TYPE bapi_doc_draw2,
          lt_drad    TYPE TABLE OF bapi_doc_drad,
          lt_drat    TYPE TABLE OF bapi_doc_drat,
          lt_files   TYPE TABLE OF bapi_doc_files2,
          lt_charval TYPE TABLE OF bapi_characteristic_values,
          lt_class   TYPE TABLE OF bapi_class_allocation,
          lv_path    TYPE string,
          lv_ok      TYPE abap_bool,
          ls_return  TYPE bapiret2.

    CLEAR es_doc.
    ls_docdata-documenttype = is_otpl-doctype.
    ls_docdata-statusextern = iv_status.

    lt_drad = VALUE #(
      ( objecttype = iv_dokob  objectkey = iv_objky )
      ( objecttype = 'PMAUFK' objectkey = iv_aufnr ) ).

    lt_drat = VALUE #( ( language = sy-langu description = iv_formtitle ) ).
    lt_class = VALUE #( ( classtype = gc_classtype classname = gc_class status = '1' ) ).

    LOOP AT it_keys INTO DATA(ls_key).
      APPEND VALUE #( classtype = gc_classtype
                      classname = gc_class
                      charname  = ls_key-charname
                      charvalue = ls_key-charvalue ) TO lt_charval.
    ENDLOOP.

    IF gc_char_lot IS NOT INITIAL.
      APPEND VALUE #( classtype = gc_classtype
                      classname = gc_class
                      charname  = gc_char_lot
                      charvalue = is_qals-prueflos ) TO lt_charval.
    ENDIF.

    write_pdf_tempfile(
      EXPORTING
        iv_pdf  = iv_pdf
      IMPORTING
        ev_path = lv_path
        ev_ok   = lv_ok ).
    IF lv_ok = abap_true.
      APPEND VALUE #( storagecategory = gc_storage_cat
                      wsapplication   = gc_wsappl_pdf
                      docfile         = lv_path
                      description     = iv_formtitle ) TO lt_files.
    ELSE.
      append_sysmsg_return( CHANGING ct_return = ct_return ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_DOCUMENT_CREATE2'
      EXPORTING
        documentdata         = ls_docdata
        pf_ftp_dest          = 'SAPFTPA'
        pf_http_dest         = 'SAPHTTPA'
      IMPORTING
        documenttype         = es_doc-dokar
        documentnumber       = es_doc-doknr
        documentpart         = es_doc-doktl
        documentversion      = es_doc-dokvr
        return               = ls_return
      TABLES
        objectlinks          = lt_drad
        documentdescriptions = lt_drat
        characteristicvalues = lt_charval
        classallocations     = lt_class
        documentfiles        = lt_files.
    APPEND ls_return TO ct_return.
  ENDMETHOD.

  METHOD create_new_version.
    DATA: lv_actvr   TYPE draw-dokvr,
          lv_num     TYPE i,
          lt_copy    TYPE TABLE OF bapi_doc_drad_select,
          ls_return  TYPE bapiret2,
          lv_doctype TYPE bapi_doc_aux-doctype,
          lv_docnr   TYPE bapi_doc_aux-docnumber,
          lv_docpart TYPE bapi_doc_aux-docpart,
          lv_docvers TYPE bapi_doc_aux-docversion.

    CLEAR es_doc.
    lv_actvr = is_document-dokvr.

    CALL FUNCTION 'BAPI_DOCUMENT_GETACTVERSION'
      EXPORTING
        documenttype    = is_otpl-doctype
        documentnumber  = is_document-doknr
        documentpart    = is_document-doktl
        documentversion = is_document-dokvr
      IMPORTING
        documentversion = lv_actvr
        return          = ls_return.
    IF lv_actvr IS INITIAL.
      lv_actvr = is_document-dokvr.
    ENDIF.

    lv_num = lv_actvr.
    lv_num = lv_num + 1.
    es_doc = VALUE #( dokar = is_otpl-doctype
                      doknr = is_document-doknr
                      doktl = is_document-doktl
                      dokvr = |{ lv_num WIDTH = 2 ALIGN = RIGHT PAD = '0' }| ).

    lt_copy = VALUE #( ( objecttype = '*' ) ).

    CALL FUNCTION 'BAPI_DOCUMENT_CREATENEWVRS2'
      EXPORTING
        refdocumenttype    = is_otpl-doctype
        refdocumentnumber  = is_document-doknr
        refdocumentpart    = is_document-doktl
        refdocumentversion = lv_actvr
        newdocumentversion = es_doc-dokvr
        copyoriginals      = space
        copyclassification = 'X'
        copydocbom         = space
      IMPORTING
        doctype            = lv_doctype
        docnumber          = lv_docnr
        docpart            = lv_docpart
        docversion         = lv_docvers
        return             = ls_return
      TABLES
        copyobjectlinks    = lt_copy.
    APPEND ls_return TO ct_return.
    IF ls_return-type CA 'EAX'.
      RETURN.
    ENDIF.

    IF lv_docvers IS NOT INITIAL.
      es_doc-dokvr = lv_docvers.
    ENDIF.
    IF lv_docpart IS NOT INITIAL.
      es_doc-doktl = lv_docpart.
    ENDIF.

    checkin_pdf(
      EXPORTING
        is_document  = es_doc
        iv_pdf       = iv_pdf
        iv_formtitle = iv_formtitle
      CHANGING
        ct_return    = ct_return ).

    ensure_object_links(
      EXPORTING
        is_document = es_doc
        iv_dokob    = iv_dokob
        iv_objky    = iv_objky
        iv_aufnr    = iv_aufnr
      CHANGING
        ct_return   = ct_return ).

    set_doc_chars(
      EXPORTING
        is_document = es_doc
        it_keys     = it_keys
        iv_char_lot = gc_char_lot
        is_qals     = is_qals
      CHANGING
        ct_return   = ct_return ).

    set_status(
      EXPORTING
        is_document = es_doc
        iv_status   = iv_status_new
      CHANGING
        ct_return   = ct_return ).

    set_status(
      EXPORTING
        is_document = is_document
        iv_status   = iv_status_old
      CHANGING
        ct_return   = ct_return ).
  ENDMETHOD.

  METHOD checkin_pdf.
    DATA: lt_files  TYPE TABLE OF bapi_doc_files2,
          lv_path   TYPE string,
          lv_ok     TYPE abap_bool,
          ls_return TYPE bapiret2.

    write_pdf_tempfile(
      EXPORTING
        iv_pdf  = iv_pdf
      IMPORTING
        ev_path = lv_path
        ev_ok   = lv_ok ).
    IF lv_ok = abap_false.
      append_sysmsg_return( CHANGING ct_return = ct_return ).
      RETURN.
    ENDIF.

    lt_files = VALUE #( ( storagecategory = gc_storage_cat
                          wsapplication   = gc_wsappl_pdf
                          docfile         = lv_path
                          description     = iv_formtitle ) ).

    CALL FUNCTION 'BAPI_DOCUMENT_CHECKIN2'
      EXPORTING
        documenttype    = is_document-dokar
        documentnumber  = is_document-doknr
        documentpart    = is_document-doktl
        documentversion = is_document-dokvr
        pf_ftp_dest     = 'SAPFTPA'
        pf_http_dest    = 'SAPHTTPA'
      IMPORTING
        return          = ls_return
      TABLES
        documentfiles   = lt_files.
    APPEND ls_return TO ct_return.
  ENDMETHOD.

  METHOD write_pdf_tempfile.
    DATA: lv_dir  TYPE c LENGTH 100,
          lv_uuid TYPE sysuuid-c.

    CLEAR: ev_path, ev_ok.

    CALL 'C_SAPGPARAM' ID 'NAME'  FIELD 'DIR_TEMP'
                       ID 'VALUE' FIELD lv_dir.               "#EC CI_CCALL
    CALL FUNCTION 'SYSTEM_UUID_C_CREATE'
      IMPORTING
        uuid = lv_uuid.

    ev_path = |{ lv_dir }/{ lv_uuid }.pdf|.

    OPEN DATASET ev_path FOR OUTPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      CLEAR ev_path.
      RETURN.
    ENDIF.

    TRANSFER iv_pdf TO ev_path.
    CLOSE DATASET ev_path.
    ev_ok = abap_true.
  ENDMETHOD.

  METHOD ensure_object_links.
    DATA: lt_links       TYPE TABLE OF bapi_doc_drad,
          lt_links_delta TYPE TABLE OF bapi_doc_drad,
          ls_return      TYPE bapiret2.

    CALL FUNCTION 'BAPI_DOCUMENT_GETDETAIL2'
      EXPORTING
        documenttype    = is_document-dokar
        documentnumber  = is_document-doknr
        documentpart    = is_document-doktl
        documentversion = is_document-dokvr
        getobjectlinks  = 'X'
      IMPORTING
        return          = ls_return
      TABLES
        objectlinks     = lt_links.

    IF iv_objky IS NOT INITIAL.
      READ TABLE lt_links TRANSPORTING NO FIELDS
        WITH KEY objecttype = iv_dokob objectkey = iv_objky.
      IF sy-subrc <> 0.
        APPEND VALUE #( objecttype = iv_dokob objectkey = iv_objky ) TO lt_links_delta.
      ENDIF.
    ENDIF.

    IF iv_aufnr IS NOT INITIAL.
      READ TABLE lt_links TRANSPORTING NO FIELDS
        WITH KEY objecttype = 'PMAUFK' objectkey = iv_aufnr.
      IF sy-subrc <> 0.
        APPEND VALUE #( objecttype = 'PMAUFK' objectkey = iv_aufnr ) TO lt_links_delta.
      ENDIF.
    ENDIF.

    IF lt_links_delta IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_DOCUMENT_CHANGE2'
      EXPORTING
        documenttype    = is_document-dokar
        documentnumber  = is_document-doknr
        documentpart    = is_document-doktl
        documentversion = is_document-dokvr
      IMPORTING
        return          = ls_return
      TABLES
        objectlinks     = lt_links_delta.
    APPEND ls_return TO ct_return.
  ENDMETHOD.

  METHOD set_doc_chars.
    DATA: lt_num    TYPE ty_class_num_t,
          lt_char   TYPE ty_class_char_t,
          lt_curr   TYPE ty_class_curr_t,
          lt_return TYPE bapiret2_t,
          ls_char   TYPE bapi1003_alloc_values_char,
          lv_key    TYPE c LENGTH 50.

    read_doc_classification(
      EXPORTING
        is_document = is_document
      IMPORTING
        et_num      = lt_num
        et_char     = lt_char
        et_curr     = lt_curr
        et_return   = lt_return ).

    LOOP AT it_keys INTO DATA(ls_key).
      READ TABLE lt_char ASSIGNING FIELD-SYMBOL(<char>)
        WITH KEY charact = ls_key-charname.
      IF sy-subrc = 0.
        <char>-value_neutral = ls_key-charvalue.
        <char>-value_char    = ls_key-charvalue.
      ELSE.
        CLEAR ls_char.
        ls_char-charact       = ls_key-charname.
        ls_char-value_neutral = ls_key-charvalue.
        ls_char-value_char    = ls_key-charvalue.
        APPEND ls_char TO lt_char.
      ENDIF.
    ENDLOOP.

    IF iv_char_lot IS NOT INITIAL.
      READ TABLE lt_char ASSIGNING FIELD-SYMBOL(<lot_char>)
        WITH KEY charact = iv_char_lot.
      IF sy-subrc = 0.
        <lot_char>-value_neutral = is_qals-prueflos.
        <lot_char>-value_char    = is_qals-prueflos.
      ELSE.
        CLEAR ls_char.
        ls_char-charact       = iv_char_lot.
        ls_char-value_neutral = is_qals-prueflos.
        ls_char-value_char    = is_qals-prueflos.
        APPEND ls_char TO lt_char.
      ENDIF.
    ENDIF.

    lv_key = build_classif_objectkey( is_document ).
    CLEAR lt_return.
    CALL FUNCTION 'BAPI_OBJCL_CHANGE'
      EXPORTING
        objectkey          = lv_key
        objecttable        = 'DRAW'
        classnum           = gc_class
        classtype          = gc_classtype
      TABLES
        allocvaluesnumnew  = lt_num
        allocvaluescharnew = lt_char
        allocvaluescurrnew = lt_curr
        return             = lt_return.
    APPEND LINES OF lt_return TO ct_return.
  ENDMETHOD.

  METHOD set_status.
    DATA: ls_data   TYPE bapi_doc_draw2,
          ls_datax  TYPE bapi_doc_draw2x,
          ls_return TYPE bapiret2.

    ls_data-statusextern  = iv_status.
    ls_datax-statusextern = 'X'.

    CALL FUNCTION 'BAPI_DOCUMENT_CHANGE2'
      EXPORTING
        documenttype    = is_document-dokar
        documentnumber  = is_document-doknr
        documentpart    = is_document-doktl
        documentversion = is_document-dokvr
        documentdata    = ls_data
        documentdatax   = ls_datax
      IMPORTING
        return          = ls_return.
    APPEND ls_return TO ct_return.
  ENDMETHOD.

  METHOD append_sysmsg_return.
    DATA ls_return TYPE bapiret2.

    ls_return-type       = sy-msgty.
    ls_return-id         = sy-msgid.
    ls_return-number     = sy-msgno.
    ls_return-message_v1 = sy-msgv1.
    ls_return-message_v2 = sy-msgv2.
    ls_return-message_v3 = sy-msgv3.
    ls_return-message_v4 = sy-msgv4.
    IF ls_return-type IS INITIAL.
      ls_return-type = 'E'.
    ENDIF.
    APPEND ls_return TO ct_return.
  ENDMETHOD.

  METHOD has_bapi_error.
    rv_error = abap_false.
    LOOP AT it_return INTO DATA(ls_return).
      IF ls_return-type CA 'EAX'.
        rv_error = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD append_protocol_message.
    DATA ls_protocol TYPE rqevp.

    MESSAGE i040(eam_cl) WITH iv_prueflos gc_fm_name INTO ls_protocol-prot_zeile.
    MOVE-CORRESPONDING sy TO ls_protocol.
    APPEND ls_protocol TO ct_protocol.
  ENDMETHOD.

  METHOD append_return_protocol.
    DATA ls_protocol TYPE rqevp.

    LOOP AT it_return INTO DATA(ls_return) WHERE message IS NOT INITIAL.
      CLEAR ls_protocol.
      MOVE-CORRESPONDING sy TO ls_protocol.
      ls_protocol-prot_zeile = ls_return-message.
      APPEND ls_protocol TO ct_protocol.
    ENDLOOP.
  ENDMETHOD.

  METHOD save_log_and_commit.
    DATA lt_logh TYPE bal_t_logh.

    IF iv_no_log_save IS INITIAL AND
       iv_test        IS INITIAL AND
       it_protocol    IS NOT INITIAL.
      cl_eam_cl_msg_tool=>add_msg_to_log(
        EXPORTING
          iv_subobject = cl_eam_cl_util=>gc_applog_subobject_sud
          iv_ordernr   = iv_aufnr
          it_return    = it_return
          iv_not_save  = abap_false
          iv_alprog    = sy-cprog
        CHANGING
          ct_logs      = lt_logh ).
    ENDIF.

    IF iv_test IS INITIAL.
      COMMIT WORK.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

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
*  Thin QM follow-up adapter. Keep this FM in configuration and maintain
*  behavior in the local OO service above.
*----------------------------------------------------------------------
  DATA(ls_request) = VALUE lcl_eam_dms_lot_vrs_service=>ty_request(
    qals        = i_qals
    qave        = i_qave
    qapo        = i_qapo
    no_log_save = i_no_log_save
    test        = i_test
    dialog      = i_dialog ).

  DATA(ls_result) = lcl_eam_dms_lot_vrs_service=>execute( ls_request ).

  e_subrc = ls_result-subrc.
  APPEND LINES OF ls_result-protocol TO e_protocol.
ENDFUNCTION.
