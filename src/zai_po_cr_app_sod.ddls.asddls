@AbapCatalog.sqlViewName: 'ZV_PO_CR_APP_SOD'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PO Creator = Approver SoD Violation'
@VDM.viewType: #CONSUMPTION
define view ZAI_PO_CR_APP_SOD
  with parameters
    @EndUserText.label: 'PO Creation Date From'
    p_aedat_from : aedat,
    @EndUserText.label: 'PO Creation Date To'
    p_aedat_to   : aedat,
    @EndUserText.label: 'PO Net Value Threshold'
    p_po_value   : netwr
  as select from ekko as h
    // Aggregate PO net value once, independent of change-doc fan-out
    inner join ( select ebeln,
                        sum( netwr ) as po_net_value
                   from ekpo
                   where loekz = ''
                   group by ebeln ) as v on v.ebeln = h.ebeln
    // Release Strategy approver via change docs (ME29N individual, ME28 collective)
    // TODO: refine with cp.value_new vs value_old to exclude release withdrawals
    inner join cdhdr as ch on  ch.objectclas = 'EINKBELEG'
                           and ch.objectid   = h.ebeln
                           and ch.tcode      in ( 'ME29N', 'ME28' )
    inner join cdpos as cp on  cp.objectclas = ch.objectclas
                           and cp.objectid   = ch.objectid
                           and cp.changenr   = ch.changenr
                           and cp.tabname    = 'EKKO'
                           and cp.fname      = 'FRGZU'
                           and cp.value_new <> '' // approximate "release set" (not reset)
{
  key h.ebeln                                  as PurchasingDocument,
  key ch.changenr                              as ChangeDocNumber,
      h.bukrs                                  as CompanyCode,
      h.bsart                                  as DocumentType,
      h.lifnr                                  as Supplier,
      h.ekorg                                  as PurchasingOrg,
      h.ekgrp                                  as PurchasingGroup,
      h.waers                                  as Currency,
      h.aedat                                  as PurchasingDocumentDate,
      h.ernam                                  as CreatedByUser,
      ch.username                              as ApprovedByUser,
      ch.udate                                 as ApprovalDate,
      ch.utime                                 as ApprovalTime,
      ch.tcode                                 as ApprovalTcode,
      v.po_net_value                           as PoNetValue,
      cast( 3 as abap.int1 )                   as RiskCriticality
}
where h.aedat   between :p_aedat_from and :p_aedat_to
  and h.bstyp   = 'F'
  and h.ernam   = ch.username        // SoD: creator = approver
  and v.po_net_value >= :p_po_value  // actual PO value vs threshold