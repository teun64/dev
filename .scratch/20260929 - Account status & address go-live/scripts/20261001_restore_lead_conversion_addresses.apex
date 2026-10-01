List<Account> fixes = new List<Account>{
        new Account(Id='0011t00000G83RBAAZ', BillingStreet='Bellstraat 18', BillingPostalCode='6716BA', BillingCity='EDE', BillingCountryCode='NL'),
        new Account(Id='0011t00000G849bAAB', BillingStreet='Buitendijk 22', BillingPostalCode='1145PK', BillingCity='Katwoude', BillingStateCode='NH', BillingCountryCode='NL', BillingLatitude=52.46869, BillingLongitude=5.02928),
        new Account(Id='0013W00000EpIWWQA3', BillingStreet='Noorderbreek 23', BillingPostalCode='1121KD', BillingCity='LANDSMEER', BillingStateCode='NH', BillingCountryCode='NL', BillingLatitude=52.42764, BillingLongitude=4.90892),
        new Account(Id='001bR00000IyJ2EQAV', BillingStreet='Vinkenveld 14', BillingPostalCode='5249JP', BillingCity='Rosmalen', BillingCountryCode='NL'),
        new Account(Id='001bR00000Sgrz3QAB', BillingStreet='Louisestratenusstraat 10', BillingPostalCode='4822vw', BillingCity='Breda', BillingCountryCode='NL')
};
for (Account a : fixes) update a;
// 2026-10-01 BAG correction (PDOK locatieserver): Louisestratenusstraat 10, 4822vw -> Louise Stratenusstraat 10, 4822VW Breda (NB)
update new Account(Id='001bR00000Sgrz3QAB', BillingStreet='Louise Stratenusstraat 10', BillingPostalCode='4822VW', BillingCity='Breda', BillingStateCode='NB', BillingCountryCode='NL', BillingLatitude=51.61167397, BillingLongitude=4.72622433);
