@AbapCatalog.sqlViewName: 'ZV_PO_CR_APP'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PO Creator Equals Approver - SoD'
@VDM.viewType: #BASIC
@OData.publish: true
define view ZAI_PO_CR_APP
  with parameters
    @EndUserText.label: 'PO Creation Date From'
    p_aedat_from : abap.dats,
    @EndUserText.label: 'PO Creation Date To'
    p_aedat_to   : abap.dats,
    @EndUserText.label: 'Minimum PO Net Value'
    p_po_value   : abap.curr(15,2)
  as select from ekko as h
    inner join   ekpo as i
      on  h.ebeln = i.ebeln
    // Release Strategy approval captured via change documents (ME29N/ME28).
    // CDHDR.objectclas='EINKBELEG', CDPOS.tabname='EKKO', fname commonly 'FRGZU'
    // (release-status bitstring). Some customers also rely on 'FRGKE'/'FRGRL';
    // TODO: confirm which fname your release strategy writes and extend if needed.
    // NOTE: grain is PO item x release-change event. Multiple release codes/steps
    // will yield multiple rows; aggregate in the consumption layer if a single
    // "approver per PO" is required.
    inner join   cdhdr as ch
      on  ch.objectclas = 'EINKBELEG'
      and ch.objectid   = h.ebeln                  // implicit CHAR90<-CHAR10
    inner join   cdpos as cp
      on  cp.objectclas = ch.objectclas
      and cp.objectid   = ch.objectid
      and cp.changenr   = ch.changenr
      and cp.tabname    = 'EKKO'
      and cp.fname      = 'FRGZU'                  // TODO: extend to 'FRGKE'/'FRGRL' if used
{
  key h.ebeln                                         as PurchasingDocument,
  key i.ebelp                                         as PurchasingDocumentItem,
  key ch.changenr                                     as ChangeDocumentNumber,
      h.bukrs                                         as CompanyCode,
      h.bsart                                         as PurchasingDocumentType,
      h.lifnr                                         as Supplier,
      h.ekorg                                         as PurchasingOrganization,
      h.ekgrp                                         as PurchasingGroup,
      h.waers                                         as Currency,
      h.aedat                                         as PurchasingDocumentDate,
      h.ernam                                         as CreatedByUser,
      ch.username                                     as ApprovedByUser,
      ch.udate                                        as ApprovalDate,
      ch.utime                                        as ApprovalTime,
      i.matnr                                         as Material,
      i.werks                                         as Plant,
      i.menge                                         as OrderQuantity,
      i.meins                                         as OrderUnit,
      i.netpr                                         as NetPrice,
      i.netwr                                         as NetOrderValue,
      // Constant criticality; thresholding belongs to the consumption layer
      cast( 3 as abap.int1 )                          as RiskCriticality,
      cast( 'PO Creator equals Approver' as abap.char( 60 ) ) as ExceptionReason
}
where  h.aedat   between :p_aedat_from and :p_aedat_to
  and  ch.udate  between :p_aedat_from and :p_aedat_to   // prune CDHDR scan
  and  i.netwr   >= :p_po_value
  and  h.ernam   =  ch.username           // SoD violation: creator == approver
  and  h.bstyp   =  'F'                   // restrict to Purchase Orders
  and  h.loekz   =  ' '                   // exclude deleted PO headers
  and  i.loekz   =  ' '                   // exclude deleted PO items
  and  cp.value_new <> ''                 // ignore release resets / blanks
  and  cp.value_new <> cp.value_old       // genuine release-status change