/**
 * Subscriber for Nova_Plan_Request__e. Runs as the user set in NovaPlanRequestTriggerConfig
 * (the integration user), not as the agent user that escalated the case.
 */
trigger NovaPlanRequestTrigger on Nova_Plan_Request__e (after insert) {
    List<Id> caseIds = new List<Id>();
    for (Nova_Plan_Request__e request : Trigger.new) {
        caseIds.add(Id.valueOf(request.Case_Id__c));
    }
    if (!caseIds.isEmpty()) {
        NovaResolutionPlanService.generate(caseIds);
    }
}
