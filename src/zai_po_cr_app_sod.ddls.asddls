@AbapCatalog.sqlViewName: 'ZV_PO_CR_APP_SOD'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PO Creator Equals Approver - SoD Check'
@VDM.viewType: #CONSUMPTION
define view ZAI_PO_CR_APP_SOD
  with parameters
    @EndUserText.label: 'PO Creation Date From'
    p_aedat_from : budat,
    @EndUserText.label: 'PO Creation Date To'
    p_aedat_to   : budat,
    @EndUserText.label: 'Minimum PO Net Value'
    p_po_value   : netwr_ap
  as select from ekko as h
    inner join   ekpo  as i  on  i.ebeln = h.ebeln
    // TODO performance: consider extracting CDHDR/CDPOS lookup into a base CDS
    //                   (ZAI_PO_REL_APPR) pre-filtered on objectclas='EINKBELEG'
    //                   and aggregated to one approver row per PO.
    inner join   cdhdr as ch on  ch.objectclas = 'EINKBELEG'
                             and ch.objectid   = cast( h.ebeln as abap.char(90) )
    inner join   cdpos as cp on  cp.objectclas = ch.objectclas
                             and cp.objectid   = ch.objectid
                             and cp.changenr   = ch.changenr
                             and cp.tabname    = 'EKKO'
                             and ( cp.fname = 'FRGZU' or cp.fname = 'FRGKE' )
{
  key h.ebeln                                 as PurchasingDocument,
  key i.ebelp                                 as PurchasingDocumentItem,
  key ch.changenr                             as ChangeDocumentNumber, // grain: PO item x release change
      h.bukrs                                 as CompanyCode,
      h.bsart                                 as PurchasingDocumentType,
      h.lifnr                                 as Supplier,
      h.aedat                                 as PurchasingDocumentDate,
      h.ernam                                 as CreatedBy,
      ch.username                             as ApprovedBy,
      ch.udate                                as ApprovalDate,
      ch.utime                                as ApprovalTime,
      cp.tabname                              as ChangedTable,
      cp.fname                                as ChangedField,
      cp.value_new                            as ReleaseStatusNew,
      cp.value_old                            as ReleaseStatusOld,
      i.netwr                                 as ItemNetValue,
      h.waers                                 as Currency,
      // Risk indicator: constant; consumption layer can apply thresholds/UI
      cast( 3 as abap.int1 )                  as RiskCriticality
}
where h.aedat   between :p_aedat_from and :p_aedat_to
  and i.netwr   >= :p_po_value
  and h.ernam   = ch.username        // creator = approver (SoD violation)
  and i.loekz   = ' '                // exclude deleted PO items
  and h.loekz   = ' '                // exclude deleted PO header
  // TODO: optionally narrow to actual release-set events, e.g. cp.value_new <> ' '