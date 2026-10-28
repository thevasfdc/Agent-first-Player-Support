@IsTest
private class NovaResolutionPlanServiceTest {

    @IsTest
    static void writesPlanToCase() {
        Case c = new Case(Subject = 'Account hacked', Origin = 'Web', Escalation_Reason__c = 'Account security',
            Issue_Category__c = 'Account & Login', AI_Summary__c = 'Email changed by someone else.');
        insert c;

        Test.startTest();
        NovaResolutionPlanService.generate(new List<Id>{ c.Id });
        Test.stopTest();

        c = [SELECT Resolution_Plan__c FROM Case WHERE Id = :c.Id];
        Assert.isTrue(c.Resolution_Plan__c.startsWith('Goal:'), 'plan should be written to the case');
    }

    @IsTest
    static void promptContainsInstructionsAndCase() {
        Case c = new Case(Subject = 'Gems missing', Origin = 'Web');
        insert c;

        String prompt = NovaResolutionPlanService.buildPrompt(c.Id);

        Assert.isTrue(prompt.contains('ownership verification'), 'prompt should carry the plan rules');
        Assert.isTrue(prompt.contains('Gems missing'), 'prompt should carry the case context');
    }

    @IsTest
    static void publishesAndGeneratesFromEvent() {
        Case c = new Case(Subject = 'Event test', Origin = 'Web', Escalation_Reason__c = 'Account security');
        insert c;

        Test.startTest();
        EventBus.publish(new Nova_Plan_Request__e(Case_Id__c = c.Id));
        Test.getEventBus().deliver();
        Test.stopTest();

        c = [SELECT Resolution_Plan__c FROM Case WHERE Id = :c.Id];
        Assert.isNotNull(c.Resolution_Plan__c, 'the event subscriber should write the plan');
    }
}
