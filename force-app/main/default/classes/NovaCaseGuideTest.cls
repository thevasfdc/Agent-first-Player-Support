@IsTest
private class NovaCaseGuideTest {

    @IsTest
    static void buildsContextForCase() {
        Case c = new Case(
            Subject = 'Account hacked',
            Origin = 'Web',
            Player_ID__c = 'NV-1',
            Platform__c = 'Xbox',
            Issue_Category__c = 'Account & Login',
            Escalation_Reason__c = 'Account security',
            AI_Summary__c = 'Player reports email changed.'
        );
        insert c;

        NovaCaseGuide.Request req = new NovaCaseGuide.Request();
        req.recordId = c.Id;

        Test.startTest();
        List<NovaCaseGuide.Response> res = NovaCaseGuide.getContext(new List<NovaCaseGuide.Request>{ req });
        Test.stopTest();

        Assert.areEqual(c.Id, res[0].caseId);
        Assert.isTrue(res[0].context.contains('NV-1'), 'context should include the player ID');
        Assert.isTrue(res[0].context.contains('Player reports email changed.'), 'context should include the AI summary');
        Assert.isTrue(res[0].context.contains('(no plan yet)'), 'context should show the empty plan');
    }

    @IsTest
    static void handlesUnlinkedRecord() {
        NovaCaseGuide.Request req = new NovaCaseGuide.Request();
        req.recordId = UserInfo.getUserId();

        List<NovaCaseGuide.Response> res = NovaCaseGuide.getContext(new List<NovaCaseGuide.Request>{ req });

        Assert.isNull(res[0].caseId);
        Assert.isTrue(res[0].context.startsWith('No case'), 'should explain that no case is linked');
    }

    @IsTest
    static void knowledgeWithoutCategoryStillQueries() {
        String text = NovaCaseGuide.knowledgeFor(null, null);
        Assert.isNotNull(text);
    }

    @IsTest
    static void knowledgeForEscalationAndIssueCategory() {
        String text = NovaCaseGuide.knowledgeFor('Account security', 'Purchases & Billing');
        Assert.isNotNull(text);
    }
}
