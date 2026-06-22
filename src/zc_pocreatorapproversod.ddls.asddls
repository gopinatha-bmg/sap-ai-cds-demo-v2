@OData.publish: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@AbapCatalog.sqlViewName: 'ZC_POCRAPPSOD'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@EndUserText.label: 'PO Creator vs Approver SoD Violation'

define view entity ZC_PoCreatorApproverSod
  with parameters
    @EndUserText.label: 'PO Date From'
    p_po_date_from     : abap.dats,
    @EndUserText.label: 'PO Date To'
    p_po_date_to       : abap.dats,
    @EndUserText.label: 'Company Code'
    p_company_code     : bukrs,
    @EndUserText.label: 'Minimum PO Net Value'
    p_amount_threshold : abap.dec( 15, 2 )

  // Identifies POs where the user who created the PO (EKKO-ERNAM) is the same
  // user who released/approved it via Release Strategy (CDHDR/CDPOS change on
  // EKKO-FRGKE reaching final release 'R'). SAP Business Workflow tables
  // (SWWWIHEAD / SWW_WI2OBJ) are intentionally NOT used.
  //
  // Grain: one row per PO item per release change document.
  // TODO: confirm final-release indicator value (FRGKE = 'R') matches the
  //       release strategy configured in this client.

  as select from ekko as h
    inner join ekpo  as p  on  p.ebeln       = h.ebeln
    inner join cdhdr as ch on  ch.objectclas = 'EINKBELEG'
                           and ch.objectid   = h.ebeln
    inner join cdpos as cp on  cp.objectclas = ch.objectclas
                           and cp.objectid   = ch.objectid
                           and cp.changenr   = ch.changenr
                           and cp.tabname    = 'EKKO'
                           and cp.fname      = 'FRGKE'
{
  key h.ebeln                                    as PurchasingDoc,
  key p.ebelp                                    as PoItem,
  key ch.changenr                                as ChangeDocNumber,
  key cp.tabkey                                  as ChangeTableKey,
  key cp.fname                                   as ChangedField,
      h.bukrs                                    as CompanyCode,
      h.bsart                                    as PoDocType,
      h.lifnr                                    as Supplier,
      h.ekorg                                    as PurchOrg,
      h.ekgrp                                    as PurchGroup,
      h.bedat                                    as PoDate,
      h.waers                                    as Currency,
      h.ernam                                    as PoCreatedBy,
      ch.username                                as PoApprovedBy,
      ch.udate                                   as ApprovalDate,
      ch.utime                                   as ApprovalTime,
      cp.value_old                               as ReleaseValueOld,
      cp.value_new                               as ReleaseValueNew,
      p.matnr                                    as Material,
      p.txz01                                    as ItemText,
      p.werks                                    as Plant,
      p.menge                                    as PoQuantity,
      p.meins                                    as PoUom,
      p.netpr                                    as NetPrice,
      p.netwr                                    as NetValue,

      cast( 'X' as abap.char( 1 ) )              as SodViolationFlag
}
where  h.bukrs       = :p_company_code
  and  h.bedat       between :p_po_date_from and :p_po_date_to
  and  p.netwr       >= :p_amount_threshold
  and  cp.value_new  = 'R'           // final release reached
  and  h.ernam       = ch.username   // SoD violation: creator == approver