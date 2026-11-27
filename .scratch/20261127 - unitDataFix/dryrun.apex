// READ-ONLY dry run (any org): lists the Product2 changes the unit data fix would make. Nothing is written.
for (Product2 p : [SELECT ProductCode, Name, IsActive, Subscription25__Cost_Type__c, QuantityUnitOfMeasure FROM Product2 WHERE
        (QuantityUnitOfMeasure = null) OR (QuantityUnitOfMeasure NOT IN ('Piece(s)', 'Month(s)', 'Hour(s)')) OR (Subscription25__Cost_Type__c = 'NON_RECURRING' AND QuantityUnitOfMeasure = 'Month(s)')
        ORDER BY Subscription25__Cost_Type__c, QuantityUnitOfMeasure, ProductCode]) {
    String target = 'REVIEW';
    if (p.QuantityUnitOfMeasure == null && p.Subscription25__Cost_Type__c == 'NON_RECURRING') target = 'Piece(s)';
    else if (p.QuantityUnitOfMeasure == null && p.Subscription25__Cost_Type__c == 'RECURRING') target = 'Month(s)';
    else if (p.QuantityUnitOfMeasure == null && p.Subscription25__Cost_Type__c == 'RECURRING_DAILY') target = 'REVIEW (no daily unit in picklist)';
    else if (p.Subscription25__Cost_Type__c == 'RECURRING' && (p.QuantityUnitOfMeasure == 'Month' || p.QuantityUnitOfMeasure == '12' || p.QuantityUnitOfMeasure == '24')) target = 'Month(s)';
    else if (p.Subscription25__Cost_Type__c == 'NON_RECURRING' && p.QuantityUnitOfMeasure == 'Month(s)') target = 'REVIEW (prepaid bundle? keep Month(s) or Piece(s))';
    System.debug('TS_U ' + p.ProductCode + ' | ' + p.IsActive + ' | ' + p.Subscription25__Cost_Type__c + ' | ' + p.QuantityUnitOfMeasure + ' -> ' + target);
}
