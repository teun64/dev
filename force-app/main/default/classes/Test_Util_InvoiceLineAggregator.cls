@isTest
private class Test_Util_InvoiceLineAggregator {

    @IsTest
    private static void test_groupsLinesByKey(){
        List<Util_InvoiceLineAggregator.LineInput> inputs = new List<Util_InvoiceLineAggregator.LineInput>{
            line('G1', 1, 10, 2.10, 12.10, 21, 'S'),
            line('G1', 1, 5, 1.05, 6.05, 21, 'S'),
            line('G2', 2, 20, 4.20, 24.20, 21, 'S')
        };

        Util_InvoiceLineAggregator.AggregationResult result = Util_InvoiceLineAggregator.aggregate(inputs, false, 'LINE');

        System.assertEquals(2, result.lines.size(), 'Expected 2 grouped lines');
        System.assertEquals(2, result.lines[0].quantity, 'G1 quantity should be summed');
        System.assertEquals(15, result.lines[0].netAmount, 'G1 net amount should be summed');
        System.assertEquals(2, result.lines[1].quantity);
        System.assertEquals(20, result.lines[1].netAmount);

        System.assertEquals(35, result.netAmount, 'Total net should be the sum of both groups');
        System.assertEquals(1, result.vatBreakdown.size(), 'Single VAT code S expected');
        System.assertEquals(7.35, result.vatBreakdown[0].vatAmount, 'VAT breakdown should sum the raw line VAT amounts');
        System.assertEquals(42.35, result.vatBreakdown[0].grossAmount);
    }

    @IsTest
    private static void test_rawVsGroupedVatRoundingDiverges(){
        // Two lines that round to a different total VAT depending on whether VAT is computed
        // per raw line (1.23 + 1.23 = 2.46) or on the grouped net amount (24.69 * 10% = 2.47).
        List<Util_InvoiceLineAggregator.LineInput> inputs = new List<Util_InvoiceLineAggregator.LineInput>{
            line('G1', 1, 12.345, 1.23, 13.575, 10, 'S'),
            line('G1', 1, 12.345, 1.23, 13.575, 10, 'S')
        };

        Util_InvoiceLineAggregator.AggregationResult perLine = Util_InvoiceLineAggregator.aggregate(inputs, false, 'LINE');
        Util_InvoiceLineAggregator.AggregationResult perGroup = Util_InvoiceLineAggregator.aggregate(inputs, true, 'LINE');

        System.assertEquals(2.46, perLine.vatBreakdown[0].vatAmount, 'Per-raw-line VAT should sum the individual line amounts');
        System.assertEquals(2.47, perGroup.vatBreakdown[0].vatAmount, 'Per-grouped-line VAT should be recomputed off the merged net amount');
    }

    @IsTest
    private static void test_totalVsLineVatMethod(){
        List<Util_InvoiceLineAggregator.LineInput> inputs = new List<Util_InvoiceLineAggregator.LineInput>{
            line('G1', 1, 100, 21.5, 121.5, 21, 'S')
        };

        Util_InvoiceLineAggregator.AggregationResult totalMethod = Util_InvoiceLineAggregator.aggregate(inputs, false, 'TOTAL');
        Util_InvoiceLineAggregator.AggregationResult lineMethod = Util_InvoiceLineAggregator.aggregate(inputs, false, 'LINE');

        System.assertEquals(21.00, totalMethod.vatBreakdown[0].vatAmount, 'TOTAL method recomputes VAT from net * percentage');
        System.assertEquals(21.5, lineMethod.vatBreakdown[0].vatAmount, 'LINE method uses the raw line VAT amount as-is');
    }

    private static Util_InvoiceLineAggregator.LineInput line(String groupKey, Decimal qty, Decimal net, Decimal vat, Decimal gross, Decimal vatPct, String vatCode){
        Util_InvoiceLineAggregator.LineInput input = new Util_InvoiceLineAggregator.LineInput();
        input.groupKey = groupKey;
        input.quantity = qty;
        input.netAmount = net;
        input.vatAmount = vat;
        input.grossAmount = gross;
        input.vatPercentage = vatPct;
        input.vatCode = vatCode;
        return input;
    }
}
