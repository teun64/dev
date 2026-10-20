/**
 * Shared invoice line grouping + VAT breakdown math, extracted from Ctrl_Invoice so the
 * human-readable invoice PDF and the EN16931 CII XML (Svc_CIIInvoiceXmlBuilder) can never
 * disagree on how lines are merged or how VAT is rounded.
 *
 * Preserves two independently-controlled behaviors from the original Ctrl_Invoice logic:
 * - Lines are ALWAYS grouped by groupKey (Invoice_Grouping__c), summing quantity and net amount.
 * - VAT/gross totals are computed either from each raw (ungrouped) line's own amounts, or
 *   recomputed from the grouped net amount * vatPercentage - controlled by recomputeVatOnGroupedLines,
 *   matching the Account.Invoice_Grouping__c-driven branch in Ctrl_Invoice. This changes rounding
 *   behavior, so it is not a cosmetic switch - keep it wired to the same source flag on both sides.
 */
public with sharing class Util_InvoiceLineAggregator {

    public class LineInput {
        public String groupKey;
        public Decimal quantity;
        public Decimal netAmount;
        public Decimal vatAmount;
        public Decimal grossAmount;
        public Decimal vatPercentage;
        public String vatCode;
        public Object sourceItem;
    }

    public class AggregatedLine {
        public String groupKey;
        public Decimal quantity;
        public Decimal netAmount;
        public Decimal vatAmount;
        public Decimal grossAmount;
        public Decimal vatPercentage;
        public String vatCode;
        public Object anchorItem;
    }

    public class VatBreakdown {
        public String code;
        public Decimal percentage;
        public Decimal netAmount;
        public Decimal vatAmount;
        public Decimal grossAmount;
    }

    public class AggregationResult {
        public List<AggregatedLine> lines;
        public List<VatBreakdown> vatBreakdown;
        public Decimal netAmount;
        public Decimal vatAmount;
        public Decimal grossAmount;
    }

    private static final String VAT_METHOD_TOTAL = 'TOTAL';

    public static AggregationResult aggregate(List<LineInput> rawLines, Boolean recomputeVatOnGroupedLines, String vatMethod) {
        AggregationResult result = new AggregationResult();
        result.lines = groupLines(rawLines);
        result.netAmount = 0;

        Map<String, VatAccumulator> accumulatorsByCode = new Map<String, VatAccumulator>();

        if (recomputeVatOnGroupedLines) {
            for (AggregatedLine line : result.lines) {
                line.vatAmount = round(line.netAmount * (line.vatPercentage == null ? 0 : line.vatPercentage) / 100);
                line.grossAmount = round(line.netAmount + line.vatAmount);
                addToAccumulator(accumulatorsByCode, line.vatCode, line.vatPercentage, line.netAmount, line.vatAmount, line.grossAmount);
            }
        } else {
            for (LineInput line : rawLines) {
                addToAccumulator(accumulatorsByCode, line.vatCode, line.vatPercentage, line.netAmount, line.vatAmount, line.grossAmount);
            }
        }

        for (AggregatedLine line : result.lines) {
            result.netAmount += (line.netAmount == null ? 0 : line.netAmount);
        }

        result.vatBreakdown = new List<VatBreakdown>();
        result.vatAmount = 0;
        result.grossAmount = 0;
        Boolean useTotalMethod = (vatMethod == VAT_METHOD_TOTAL);

        for (VatAccumulator acc : accumulatorsByCode.values()) {
            VatBreakdown breakdown = new VatBreakdown();
            breakdown.code = acc.code;
            breakdown.percentage = acc.percentage;
            breakdown.netAmount = acc.netAmount;
            breakdown.vatAmount = round(useTotalMethod ? (acc.netAmount * acc.percentage) : acc.vatAmountLine);
            breakdown.grossAmount = round(useTotalMethod ? (acc.netAmount + (acc.netAmount * acc.percentage)) : acc.grossAmountLine);
            result.vatBreakdown.add(breakdown);

            result.vatAmount += breakdown.vatAmount;
            result.grossAmount += breakdown.grossAmount;
        }

        result.netAmount = round(result.netAmount);
        result.vatAmount = round(result.vatAmount);
        result.grossAmount = round(result.grossAmount);

        return result;
    }

    private static List<AggregatedLine> groupLines(List<LineInput> rawLines) {
        Map<String, AggregatedLine> linesByGroupKey = new Map<String, AggregatedLine>();
        List<String> orderedKeys = new List<String>();

        for (LineInput raw : rawLines) {
            AggregatedLine line = linesByGroupKey.get(raw.groupKey);
            if (line == null) {
                line = new AggregatedLine();
                line.groupKey = raw.groupKey;
                line.quantity = 0;
                line.netAmount = 0;
                line.vatCode = raw.vatCode;
                line.vatPercentage = raw.vatPercentage;
                line.anchorItem = raw.sourceItem;
                // Baseline to the anchor (first-encountered) raw line's own VAT/gross, matching
                // the original behavior where non-anchor lines in a group never contributed to
                // these two fields unless recomputeVatOnGroupedLines overwrites them below.
                line.vatAmount = raw.vatAmount;
                line.grossAmount = raw.grossAmount;
                linesByGroupKey.put(raw.groupKey, line);
                orderedKeys.add(raw.groupKey);
            }
            line.quantity += (raw.quantity == null ? 0 : raw.quantity);
            line.netAmount += (raw.netAmount == null ? 0 : raw.netAmount);
        }

        List<AggregatedLine> lines = new List<AggregatedLine>();
        for (String key : orderedKeys) {
            lines.add(linesByGroupKey.get(key));
        }
        return lines;
    }

    private static void addToAccumulator(Map<String, VatAccumulator> accumulatorsByCode, String vatCode, Decimal vatPercentage, Decimal netAmount, Decimal vatAmount, Decimal grossAmount) {
        VatAccumulator acc = accumulatorsByCode.get(vatCode);
        if (acc == null) {
            acc = new VatAccumulator();
            acc.code = vatCode;
            Decimal correction = (vatPercentage != null && Math.abs(vatPercentage) > 1) ? 100 : 1;
            acc.percentage = (vatPercentage == null ? 0 : vatPercentage) / correction;
            acc.netAmount = 0;
            acc.vatAmountLine = 0;
            acc.grossAmountLine = 0;
            accumulatorsByCode.put(vatCode, acc);
        }
        acc.netAmount += (netAmount == null ? 0 : netAmount);
        acc.vatAmountLine += (vatAmount == null ? 0 : vatAmount);
        acc.grossAmountLine += (grossAmount == null ? 0 : grossAmount);
    }

    private static Decimal round(Decimal amount) {
        return (amount == null ? 0 : amount).setScale(2, RoundingMode.HALF_UP);
    }

    private class VatAccumulator {
        String code;
        Decimal percentage;
        Decimal netAmount;
        Decimal vatAmountLine;
        Decimal grossAmountLine;
    }
}
