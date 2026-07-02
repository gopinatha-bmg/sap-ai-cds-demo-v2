@AbapCatalog.sqlViewName: 'ZV_BACKDATED_JE'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Back-Dated Journal Entries'
@VDM.viewType: #CONSUMPTION
define view ZAI_BACKDT_JE
  with parameters
    p_budat_from       : budat,
    p_budat_to         : budat,
    p_company_code     : bukrs,
    p_fiscal_year      : gjahr,
    p_amount_threshold : wrbtr
  as select from bkpf as h
    inner join   bseg as i on  i.bukrs = h.bukrs
                           and i.belnr = h.belnr
                           and i.gjahr = h.gjahr
    left outer join lfa1 as v on v.lifnr = i.lifnr

{
  key h.bukrs                                             as CompanyCode,
  key h.belnr                                             as AccountingDocument,
  key h.gjahr                                             as FiscalYear,
  key i.buzei                                             as LineItem,
      h.blart                                             as DocumentType,
      h.bldat                                             as DocumentDate,
      h.budat                                             as PostingDate,
      h.cpudt                                             as EntryDate,
      h.usnam                                             as EnteredBy,
      h.xblnr                                             as ReferenceDocumentNo,
      i.lifnr                                             as Vendor,
      v.name1                                             as VendorName,
      i.koart                                             as AccountType,
      i.wrbtr                                             as AmountInDocCurrency,
      h.waers                                             as DocumentCurrency,
      dats_days_between( h.bldat, h.budat )               as DaysBackdated,
      // Derived severity: >30d high(3), >15d medium(2), else low(1)
      case when dats_days_between( h.bldat, h.budat ) > 30 then cast( 3 as abap.int1 )
           when dats_days_between( h.bldat, h.budat ) > 15 then cast( 2 as abap.int1 )
           else                                                 cast( 1 as abap.int1 )
      end                                                 as RiskCriticality
}
// Header-level back-dating rule: BUDAT more than 5 days after BLDAT.
// NOTE: joining BSEG will repeat header exception per line item; downstream
// consumers should aggregate by (BUKRS, BELNR, GJAHR) or filter KOART if a
// single representative line is required.
// TODO: exclude originals that were reversed later, e.g. via NOT EXISTS on
// BKPF where STBLG = h.belnr, if business wants to suppress reversed docs.
where h.budat between :p_budat_from and :p_budat_to
  and h.bukrs   = :p_company_code
  and h.gjahr   = :p_fiscal_year
  and h.stblg   = ''                                    // this doc is not a reversal
  and i.wrbtr  >= :p_amount_threshold                   // TODO: consider abs(i.dmbtr) for signed / local-currency thresholding
  and h.budat   > dats_add_days( h.bldat, 5, 'INITIAL' )