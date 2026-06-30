@AbapCatalog.sqlViewName: 'ZV_GL_WKND_HIGH'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'GL Postings on Weekend > Threshold'
@VDM.viewType: #COMPOSITE
define view ZAI_GL_WKND
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from       : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to         : budat,
    @EndUserText.label: 'Company Code'
    p_company_code     : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year      : gjahr,
    @EndUserText.label: 'Amount Threshold (Local Currency)'
    p_amount_threshold : dmbtr

  // NOTE: Public-holiday filtering requires a factory calendar (SCAL/TFACS)
  //       and is intentionally deferred to the consumption layer.
  //       This base view exposes weekend (Sat/Sun) high-value GL postings.
  //       LFA1 join intentionally omitted: brief targets GL postings, not vendor lines.

  as select from bkpf as h
    inner join bseg as i
      on  i.bukrs = h.bukrs
      and i.belnr = h.belnr
      and i.gjahr = h.gjahr
{
  key h.bukrs                                                                as CompanyCode,
  key h.belnr                                                                as AccountingDocument,
  key h.gjahr                                                                as FiscalYear,
  key i.buzei                                                                as LineItem,
      h.blart                                                                as DocumentType,
      h.budat                                                                as PostingDate,
      h.bldat                                                                as DocumentDate,
      h.cpudt                                                                as EntryDate,
      h.usnam                                                                as EnteredBy,
      h.xblnr                                                                as ExternalReference,
      h.waers                                                                as DocumentCurrency,
      i.hkont                                                                as GLAccount,
      i.dmbtr                                                                as AmountInLocalCurrency,
      i.wrbtr                                                                as AmountInDocCurrency,
      i.shkzg                                                                as DebitCreditIndicator,
      i.koart                                                                as AccountType,
      h.stblg                                                                as ReverseDocument,
      // Weekday: 1900-01-05 was a Friday. Days mod 7:
      //   0=Fri, 1=Sat, 2=Sun, 3=Mon, 4=Tue, 5=Wed, 6=Thu
      // Therefore weekend = (mod = 1 OR mod = 2).
      cast( division( dats_days_between( cast('19000105' as dats), h.budat ), 1, 0 ) as abap.int4 ) as DaysSinceFriAnchor,
      cast( 3 as abap.int1 )                                                 as RiskCriticality
}
where     h.budat   between :p_budat_from and :p_budat_to
      and h.bukrs   = :p_company_code
      and h.gjahr   = :p_fiscal_year
      and h.stblg   = ''                              -- exclude reversal documents themselves
      and i.dmbtr   >= :p_amount_threshold
      // Weekend predicate: (days_since_fri_anchor mod 7) in (1,2)  -> Sat or Sun
      and (   mod( dats_days_between( cast('19000105' as dats), h.budat ), 7 ) = 1
           or mod( dats_days_between( cast('19000105' as dats), h.budat ), 7 ) = 2 )
      // TODO: extend with TFACS / factory calendar lookup in consumption layer for public holidays.