/**
 * Generates the advisor's step-by-step Resolution Plan for an escalated Nova Games case.
 * Called by the record-triggered flow "Nova - Generate Resolution Plan" when a case becomes
 * Escalated. The LLM call goes through the Einstein Trust Layer (Models API) and runs in a
 * Queueable because callouts aren't allowed during a record save.
 */
public with sharing class NovaResolutionPlanService {

    @TestVisible
    private static final String INSTRUCTIONS = String.join(new List<String>{
        'You are a senior Nova Games player-support lead writing a resolution plan for a human support advisor who has just taken over a chat from the AI agent.',
        'Use ONLY the procedure in the Knowledge articles below and the facts in the case. Never invent policies, tools, screens, timelines or amounts.',
        'If a step needs a tool outside Salesforce (for example the game account admin tool), say "in the game account admin tool"; do not invent Salesforce screens.',
        '',
        'Write plain text in exactly this layout (no markdown, no bold, no headings other than those shown):',
        'Goal: <one sentence: what a successful outcome is for this player>',
        'Known facts: <player ID, platform, issue, what the player already tried, from the case and AI hand-off summary>',
        '',
        '⬜ 1. <short action title>',
        '   What to do: <the concrete action for the advisor, from the procedure>',
        '   Ask the player for: <exactly what to collect, or "nothing">',
        '   Done when: <the observable condition that lets the advisor tick this step>',
        '   Say: "<one short, friendly message the advisor can send now>"',
        '   Escalate if: <only when the procedure gives a reason to escalate; otherwise leave this line out>',
        '',
        '(repeat for each step)',
        '',
        'Rules:',
        '- 3 to 6 steps, in the order the advisor should do them. Each step header must start with "⬜ N." so progress can be ticked.',
        '- Never ask for information listed in Known facts.',
        '- Each "Say" is the message to send once that step\'s action is complete (step 1 asks; later steps may confirm what was just done).',
        '- If the escalation reason is Account security, ownership verification is step 1.',
        '- The last step is: close the case with resolution notes (list the 2 to 3 facts the notes must contain).',
        '- At most 300 words.',
        '',
        '--- CASE ---'
    }, '\n');

    @InvocableMethod(label='Generate Resolution Plan'
        description='Queues generation of the advisor Resolution Plan for each case (Einstein LLM, grounded in the case and Knowledge).')
    public static void generate(List<Id> caseIds) {
        System.enqueueJob(new PlanJob(caseIds));
    }

    public static String buildPrompt(Id caseId) {
        return INSTRUCTIONS + '\n' + NovaCaseGuide.buildContext(caseId);
    }

    public class PlanJob implements Queueable, Database.AllowsCallouts {
        private final List<Id> caseIds;

        public PlanJob(List<Id> caseIds) {
            this.caseIds = caseIds;
        }

        public void execute(QueueableContext context) {
            List<Case> updates = new List<Case>();
            for (Id caseId : caseIds) {
                updates.add(new Case(Id = caseId, Resolution_Plan__c = callModel(buildPrompt(caseId))));
            }
            update updates;
        }
    }

    private static String callModel(String prompt) {
        if (Test.isRunningTest()) {
            return 'Goal: test\n⬜ 1. Test step';
        }
        aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
        request.modelName = 'sfdc_ai__DefaultGPT4Omni';
        aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest();
        body.prompt = prompt;
        request.body = body;
        aiplatform.ModelsAPI.createGenerations_Response response = new aiplatform.ModelsAPI().createGenerations(request);
        return response.Code200.generation.generatedText;
    }
}
