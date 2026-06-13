@AbapCatalog.sqlViewName: 'ZV_POCREQAPP'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'PO Creator Equals Approver - SoD'
@VDM.viewType: #CONSUMPTION
// Grain: one row per PO item per release change document.
// NOTE: Brief mentions "accounting document line" grain, but no FI tables are
// joined here (PO release happens before posting). If FI-level grain is truly
// required, layer this view with BSEG on EBELN/EBELP.
// RiskCriticality scale: 1=Low, 2=Medium, 3=High.
define view ZAI_PO_CR_EQ_APP
  with parameters
    @EndUserText.label: 'PO Creation Date From'
    p_aedat_from : aedat,
    @EndUserText.label: 'PO Creation Date To'
    p_aedat_to   : aedat,
    @EndUserText.label: 'Minimum PO Net Value'
    p_po_value   : netwr

  as select from ekko as po

    inner join ekpo as it
      on  it.ebeln = po.ebeln

    // Release-strategy approval event captured in change docs (ME28/ME29N).
    // FRGZU = release status field on EKKO. Restrict to actual release
    // events (value_new populated and changed).
    inner join cdhdr as ch
      on  ch.objectclas = 'EINKBELEG'
      and ch.objectid   = po.ebeln

    inner join cdpos as cp
      on  cp.objectclas = ch.objectclas
      and cp.objectid   = ch.objectid
      and cp.changenr   = ch.changenr
      and cp.tabname    = 'EKKO'
      and cp.fname      = 'FRGZU'

    // Inline PO-level net value aggregation (replaces external summary CDS).
    inner join
      ( select ebeln,
               sum( netwr ) as PoNetValue
          from ekpo
         where loekz = ''
         group by ebeln ) as ag
      on ag.ebeln = po.ebeln

{
  key po.ebeln                                as PurchaseOrder,
  key it.ebelp                                as PurchaseOrderItem,
  key cp.changenr                             as ChangeDocNumber,
      po.bukrs                                as CompanyCode,
      po.bsart                                as DocumentType,
      it.lifnr                                as Supplier,
      po.ekorg                                as PurchasingOrg,
      po.ekgrp                                as PurchasingGroup,
      po.waers                                as Currency,
      po.aedat                                as PoCreationDate,
      po.ernam                                as PoCreatedBy,
      ch.username                             as PoApprovedBy,
      ch.udate                                as ApprovalDate,
      ch.utime                                as ApprovalTime,
      it.netwr                                as ItemNetValue,
      ag.PoNetValue                           as PoNetValue,
      cast( 3 as abap.int1 )                  as RiskCriticality
}

where po.aedat        between :p_aedat_from and :p_aedat_to
  and po.ernam        =  ch.username        // SoD core: creator == approver
  and po.bstyp        =  'F'                // Purchase Order
  and po.loekz        =  ''
  and it.loekz        =  ''
  and cp.value_new   <> ''                  // actual release event
  and cp.value_new   <> cp.value_old
  and ag.PoNetValue   >= :p_po_value