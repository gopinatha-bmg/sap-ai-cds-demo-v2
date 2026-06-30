@AbapCatalog.sqlViewName: 'ZV_AMT_APR_EX'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Posted vs Approved Amount Exceptions'
@VDM.viewType: #CONSUMPTION
define view ZAI_AMT_APR_EX
  with parameters
    @EndUserText.label: 'Posting Date From'
    p_budat_from        : budat,
    @EndUserText.label: 'Posting Date To'
    p_budat_to          : budat,
    @EndUserText.label: 'Company Code'
    p_company_code      : bukrs,
    @EndUserText.label: 'Fiscal Year'
    p_fiscal_year       : gjahr,
    @EndUserText.label: 'Amount Threshold'
    p_amount_threshold  : netwr_ap
  // NOTE: The user brief only named BKPF / BSEG / LFA1 / T001 as key tables but
  // did not specify which table holds the "approved amount". EKPO.NETWR is used
  // below ONLY AS A PLACEHOLDER example for a PO-based approval reference.
  // TODO: replace with the real approval source (e.g. EKKO/EKPO aggregate via
  //       EKBE, RBKP/RSEG for MM invoices, an approval workflow table, or a
  //       customer Z-table). Also reconcile currency (doc vs company) before
  //       comparing amounts in multi-currency scenarios.
  as select from bkpf as h
    inner join      bseg as i on  i.bukrs = h.bukrs
                              and i.belnr = h.belnr
                              and i.gjahr = h.gjahr
    left outer join lfa1 as v on  v.lifnr = i.lifnr
    inner join      t001 as c on  c.bukrs = h.bukrs
    left outer join ekpo as ap on  ap.ebeln = i.ebeln    -- TODO: replace approval source
                               and ap.ebelp = i.ebelp
  {
    key h.bukrs                                                as CompanyCode,
    key h.belnr                                                as AccountingDocument,
    key h.gjahr                                                as FiscalYear,
    key i.buzei                                                as LineItem,
        h.budat                                                as PostingDate,
        h.bldat                                                as DocumentDate,
        h.xblnr                                                as ExternalInvoiceNo,
        h.blart                                                as DocumentType,
        i.shkzg                                                as DebitCreditIndicator,
        i.lifnr                                                as Vendor,
        v.name1                                                as VendorName,
        i.wrbtr                                                as PostedAmount,
        i.waers                                                as DocumentCurrency,
        c.waers                                                as CompanyCodeCurrency,
        ap.netwr                                               as ApprovedAmount,
        case
          when ap.netwr is not null and ap.netwr <> 0
            then cast( division( ( i.wrbtr - ap.netwr ) * 100, ap.netwr, 2 ) as abap.dec( 15, 2 ) )
          else cast( 0 as abap.dec( 15, 2 ) )
        end                                                    as VariancePercent,
        // Classification only; the WHERE clause already restricts the result set
        // to exception rows, so this CASE labels the reason without re-stating
        // the filter predicate.
        case
          when ap.netwr is null
               then cast( 'NO_APPROVAL'        as abap.char( 20 ) )
          else      cast( 'OVER_APPROVED_5PCT' as abap.char( 20 ) )
        end                                                    as ExceptionReason,
        cast( 3 as abap.int2 )                                 as RiskCriticality
  }
  where h.bukrs   = :p_company_code
    and h.gjahr   = :p_fiscal_year
    and h.budat   between :p_budat_from and :p_budat_to
    and h.stblg   = ''                  -- exclude reversal documents
    and i.koart   = 'K'                 -- vendor line items only
    and i.wrbtr   >= :p_amount_threshold
    and (    ap.netwr is null
          or i.wrbtr * 100 > ap.netwr * 105 )