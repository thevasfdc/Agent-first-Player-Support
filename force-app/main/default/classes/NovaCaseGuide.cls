/**
 * Builds the context the advisor-side AI needs for a Nova Games case: case details,
 * the Service Agent's hand-off summary, the current Resolution Plan and the published
 * Knowledge articles for the case's issue category.
 *
 * Used by:
 *  - the "Service Assistant Guide" employee agent (invocable action Get Case Guide Context)
 *  - the Nova_Resolution_Plan prompt template (via NovaResolutionPlanPrompt)
 */
public with sharing class NovaCaseGuide {

    // Issue_Category__c picklist value -> Nova_Support data category API name
    private static final Map<String, String> CATEGORY_BY_ISSUE = new Map<String, String>{
        'Purchases & Billing' => 'Purchases_Billing__c',
        'Account & Login' => 'Account_Login__c',
        'Technical' => 'Technical__c'
    };

    // Escalation_Reason__c picklist value -> data category that holds the advisor procedure
    private static final Map<String, String> CATEGORY_BY_ESCALATION = new Map<String, String>{
        'Account security' => 'Account_Login__c',
        'Payment dispute' => 'Purchases_Billing__c'
    };

    public class Request {
        @InvocableVariable(label='Record ID' description='ID of the Case or Messaging Session the advisor is working on' required=true)
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Case ID' description='ID of the case the context belongs to')
        public String caseId;
        @InvocableVariable(label='Case context' description='Case details, AI hand-off summary, current resolution plan and relevant Knowledge articles')
        public String context;
    }

    @InvocableMethod(label='Get Case Guide Context'
        description='Returns the case details, AI hand-off summary, current resolution plan and relevant Knowledge articles for the case the advisor has open (Case or Messaging Session record).')
    public static List<Response> getContext(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            Id caseId = resolveCaseId(req.recordId);
            if (caseId == null) {
                res.context = 'No case is linked to the record the advisor has open.';
            } else {
                res.caseId = caseId;
                res.context = buildContext(caseId);
            }
            responses.add(res);
        }
        return responses;
    }

    /** Accepts a Case ID or a Messaging Session ID and returns the related Case ID. */
    public static Id resolveCaseId(String recordId) {
        if (String.isBlank(recordId)) {
            return null;
        }
        Id recId = Id.valueOf(recordId);
        if (recId.getSObjectType() == Case.SObjectType) {
            return recId;
        }
        if (recId.getSObjectType() == MessagingSession.SObjectType) {
            List<MessagingSession> sessions = [SELECT CaseId FROM MessagingSession WHERE Id = :recId LIMIT 1];
            return sessions.isEmpty() ? null : sessions[0].CaseId;
        }
        return null;
    }

    public static String buildContext(Id caseId) {
        Case c = [
            SELECT CaseNumber, Subject, Status, Priority, Player_ID__c, Platform__c, Issue_Category__c,
                Escalation_Reason__c, AI_Summary__c, Resolution_Plan__c
            FROM Case WHERE Id = :caseId
        ];
        List<String> lines = new List<String>{
            'CASE ' + c.CaseNumber + ': ' + c.Subject,
            'Status: ' + c.Status + ' | Priority: ' + c.Priority,
            'Player ID: ' + valueOrDash(c.Player_ID__c) + ' | Platform: ' + valueOrDash(c.Platform__c),
            'Issue category: ' + valueOrDash(c.Issue_Category__c) + ' | Escalation reason: ' + valueOrDash(c.Escalation_Reason__c),
            '',
            'AI HAND-OFF SUMMARY (from the Nova Support Agent):',
            valueOrDash(c.AI_Summary__c),
            '',
            'CURRENT RESOLUTION PLAN:',
            String.isBlank(c.Resolution_Plan__c) ? '(no plan yet)' : c.Resolution_Plan__c,
            '',
            'RELEVANT KNOWLEDGE ARTICLES:',
            knowledgeFor(c.Escalation_Reason__c, c.Issue_Category__c)
        };
        return String.join(lines, '\n');
    }

    /**
     * Published articles as plain text: first the category implied by the escalation reason
     * (that is where the advisor procedure lives), then the case's issue category.
     */
    public static String knowledgeFor(String escalationReason, String issueCategory) {
        List<String> categories = new List<String>();
        for (String category : new List<String>{
                CATEGORY_BY_ESCALATION.get(escalationReason), CATEGORY_BY_ISSUE.get(issueCategory) }) {
            if (category != null && !categories.contains(category)) {
                categories.add(category);
            }
        }
        String soql = 'SELECT Title, Answer__c FROM Knowledge__kav WHERE PublishStatus = \'Online\' AND Language = \'en_US\'';
        if (!categories.isEmpty()) {
            soql += ' WITH DATA CATEGORY Nova_Support__c AT (' + String.join(categories, ',') + ')';
        }
        soql += ' LIMIT 6';
        List<String> parts = new List<String>();
        for (Knowledge__kav article : Database.query(soql)) {
            parts.add('### ' + article.Title + '\n' + toPlainText(article.Answer__c));
        }
        return parts.isEmpty() ? '(no matching published articles)' : String.join(parts, '\n\n');
    }

    private static String toPlainText(String html) {
        if (String.isBlank(html)) {
            return '';
        }
        String text = html.replaceAll('<li>', '\n- ').replaceAll('</p>|</li>|</ol>|</ul>|<br\\s*/?>', '\n');
        text = text.replaceAll('<[^>]+>', '').unescapeHtml4();
        return text.trim();
    }

    private static String valueOrDash(String value) {
        return String.isBlank(value) ? '-' : value;
    }
}