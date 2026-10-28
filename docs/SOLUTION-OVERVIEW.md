# Nova Games: agent-first player support (solution overview)

Developer Edition org `<ORG_ID>` · CLI alias `fde-dev` · source in `FDE Project/nova-support`.
Fictional brand "Nova Games", a re-creation of the pattern delivered at a global gaming client. No client data.

---

## 1. Scenarios the solution handles today

| # | Scenario (what the player says) | Who handles it | What happens | Case at the end |
|---|---|---|---|---|
| S1 | "My gems never arrived" → steps work | **Nova (AI) only** | Intake (player ID + platform) → steps from the *Missing purchase* article, tailored to platform → "Did that fix it?" → yes → case closed | Closed, **Resolved by AI**, AI resolution summary |
| S2 | Crash on launch / can't connect / password reset | **Nova only** | Same as S1, with the *Technical* or *Account & Login* articles | Closed, Resolved by AI |
| S3 | Steps don't work after 2 tries, or no article fits | Nova → **human** | Nova writes a hand-off summary → escalation → advisor gets the chat | Escalated, reason **No answer found** |
| S4 | "Someone hacked my account" | Nova → **human** (immediately) | Intake only (no troubleshooting) → escalate | Escalated, **Account security**, Priority **High** |
| S5 | "I was charged twice" / chargeback | Nova → **human** (immediately) | Intake only → escalate | Escalated, **Payment dispute**, Priority **High** |
| S6 | "I want a real person" | Nova → **human** | Asks once for ID + platform; escalates even if the player refuses | Escalated, **Customer requested human** |
| S7 | Player gets angry | Nova → **human** | Escalates | Escalated, **Negative sentiment** |
| S8 | Off-topic / prompt injection ("ignore your rules…") | **Nova** | Polite redirect; guardrail rules | Case stays New |
| S9 | Any escalated case (S3–S7) | **Advisor + AI** | Resolution Plan written to the Case within ~10 s; advisor uses **Service Assistant Guide**: "next", "done / player confirmed…", "draft a reply", "summarize" | Plan steps ticked ✅ as the advisor progresses |
| S10 | Platform failure (Case can't be created, agent unavailable) | **Human** | Omni-Channel fallback queue: chat goes straight to Chat Support Queue | Case (if created) stays New |

---

## 2. How it works end to end

```
PLAYER (Experience site chat)
  │  Messaging for In-App and Web → channel "Web Chat"
  ▼
OMNI-CHANNEL: Nova - Inbound Chat Routing (flow)
  1. create Case (Origin Web, Status New)
  2. link Case to the Messaging Session (MessagingSession.CaseId)
  3. Route Work → Nova Support Agent   (fallback: Chat Support Queue)
  ▼
NOVA SUPPORT AGENT (Agentforce Service Agent, runs as the locked-down agent user)
  Router ─► Player Intake  ── flow Nova - Update Case Details ─► Case: Player ID, Platform, Category, Subject
         ─► Purchases & Billing / Account & Login / Technical
                │ Answer Questions with Knowledge → data library "Nova Knowledge" (Data 360 vector index,
                │                                   published + public articles only, Nova Support categories)
                ├─ fixed  → flow Nova - Mark Resolved by AI ─► Case Closed, Resolved by AI
                └─ not fixed / sensitive / "human" ─► Escalation topic
  Escalation ── flow Nova - Prepare Escalation ─► Case: AI Summary, Escalation Reason, Priority, Status Escalated
             └─ @utils.escalate → OMNI-CHANNEL: Nova - Escalation to Advisor → Chat Support Queue
  ▼                                                            │
RECORD-TRIGGERED: Nova - Generate Resolution Plan             │ (in parallel)
  Case Status → Escalated → Apex NovaResolutionPlanService     │
  (prompt rules + NovaCaseGuide context: case, AI summary,     │
   Knowledge for escalation reason + category)                 │
  → Einstein Models API (GPT-4o via Trust Layer)               │
  → Case.Resolution_Plan__c  (Goal + ⬜ steps + "Say:" lines)   │
  ▼                                                            ▼
ADVISOR (Service Console, Omni-Channel "Available - Messaging") accepts the chat
  Case already has: Player ID, Platform, Category, AI Summary, Escalation Reason, Resolution Plan
  Agentforce panel → SERVICE ASSISTANT GUIDE (employee agent, runs as the advisor)
     "next"             → Apex NovaCaseGuide (reads case + plan) → current step + suggested reply
     "player confirmed…"→ ticks ⬜→✅ via flow Nova - Update Resolution Plan → next step
     "draft a reply" / "summarize" / procedure questions (Knowledge)
```

**Design principles (interview talking points)**
1. **Agent first, human when it matters:** every chat starts with AI; anything sensitive goes to a person.
2. **Deterministic guardrails in Agent Script:** troubleshooting and escalation are locked until intake is saved (`available when intakeDone == True`); IDs come from context, never from the LLM.
3. **Grounding only in governed content:** published, public, categorised Knowledge through a Data 360 retriever; the draft article never reaches the AI.
4. **Trust boundary:** the customer-facing agent runs as a locked-down agent user; the advisor's guide runs with the advisor's own permissions.
5. **Everything lands on the Case:** intake, summary, reason, plan, progress. That makes it measurable (Resolved by AI, escalation reasons) and auditable.
6. **Graceful failure:** fallback queue on every route; the agent never traps a player.

---

## 3. Every component touched in the org (current state)

### 3.1 Built by you before this work (chat POC)
| Component | Type | API name |
|---|---|---|
| Omni-Channel | Setting | — |
| Available - Messaging | Presence status | `Available_Messaging` |
| Presence configuration | Presence config | `default_presence_config` |
| Chat Support Queue | Queue | `Chat_Support_Queue` |
| Test | Queue (unused) | `TestQueue` |
| Chat Routing Config | Routing configuration | `Chat_Routing_Config` |
| Web Chat | Messaging channel | `Web_Chat` *(routing later changed by Claude, see 3.6)* |
| Web Chat Deployment | Embedded Service deployment (**Web**, used by the site) | `Web_Chat_Deployment` |
| Web_Chat | Embedded Service deployment (Mobile type, not used by the site) | `Web_Chat` |
| Customer Service | Experience Cloud site (LWR) | `Customer_Service1` |
| ESW_Web_Chat_Deplo_… | Embedded Service site (auto) | `ESW_Web_Chat_Deplo_1792798284283` |
| Service Console + Omni-Channel utility | App configuration | — |

### 3.2 Org features turned on by you (Oct 24)
| Component | Note |
|---|---|
| Data 360 | "Get Started" provisioning |
| Lightning Knowledge | Can't be disabled |

### 3.3 Data model (Claude)
| Component | Type | API name |
|---|---|---|
| Player ID | Case field, Text(40) | `Case.Player_ID__c` |
| Platform | Case field, picklist | `Case.Platform__c` |
| Issue Category | Case field, picklist | `Case.Issue_Category__c` |
| AI Summary | Case field, long text | `Case.AI_Summary__c` |
| Escalation Reason | Case field, picklist | `Case.Escalation_Reason__c` |
| Resolution Plan | Case field, long text | `Case.Resolution_Plan__c` |
| Resolved by AI | Case field, checkbox | `Case.Resolved_By_AI__c` |
| Answer | Knowledge field, rich text | `Knowledge__kav.Answer__c` |
| Nova Support | Data category group (Purchases & Billing, Account & Login, Technical) | `Nova_Support` |

### 3.4 Knowledge content and grounding
| Component | Type | By |
|---|---|---|
| 6 published articles (missing purchase, refund policy, password reset, account compromised, crash on launch, connection issues), visible internally + public KB + customers | Knowledge data | Claude |
| 1 draft article (Season 5 battle pass) | Knowledge data, deliberately unpublished | Claude |
| Nova Knowledge | Agentforce Data Library (Knowledge → Data 360 stream, DMO, vector search index, retriever `KA_Nova_Knowledge`), ID `1JDg7000005hBN7GAM` | You |

### 3.5 Customer-facing agent
| Component | Type | API name | By |
|---|---|---|---|
| Nova Support Agent | Agentforce Service Agent (Agent Script), **v2 Active** | `Nova_Support_Agent` (Bot `0Xxg7000001ueJxCAI`) | You created, Claude wrote the script and published |
| Agent user | Einstein Agent User | `nova_support_agent@your-org.ext` | Auto |
| Agent permission sets (auto) | Permission sets | `Nova_Support_Agent897699190_Permissions`, `NextGen_1bYg7000000RTSXEA4_Permissions`, PSG `AgentforceServiceAgentUserPsg` | Auto |
| Nova - Update Case Details | Autolaunched flow (agent action) | `Nova_Update_Case_Details` | Claude |
| Nova - Prepare Escalation | Autolaunched flow (agent action) | `Nova_Prepare_Escalation` | Claude |
| Nova - Mark Resolved by AI | Autolaunched flow (agent action) | `Nova_Mark_Resolved_By_AI` | Claude |

### 3.6 Routing
| Component | Type | API name | By |
|---|---|---|---|
| Nova - Inbound Chat Routing | Omni-Channel flow | `Nova_Inbound_Chat_Routing` | Claude built; **you fixed** Route Work (fallback queue) |
| Nova - Escalation to Advisor | Omni-Channel flow | `Nova_Escalation_To_Advisor` | Claude |
| Web Chat (**modified**) | Messaging channel: Queue → **Flow** routing, fallback Chat Support Queue | `Web_Chat` | Claude (original in `backup/`) |
| Nova Test API | Embedded Service deployment, Custom Client/API, **unpublished**, test-only | `Nova_Test_API` | Claude |

### 3.7 Advisor side
| Component | Type | API name | By |
|---|---|---|---|
| Service Assistant Guide | Agentforce **Employee** Agent (Agent Script), **v1 Active** | `Service_Assistant_Agent` | You created, Claude wrote the script, renamed and published |
| NovaCaseGuide | Apex (invocable "Get Case Guide Context") | `NovaCaseGuide` | Claude |
| NovaResolutionPlanService | Apex (invocable + Queueable, Einstein Models API) | `NovaResolutionPlanService` | Claude |
| Apex tests (6, passing) | Apex test classes | `NovaCaseGuideTest`, `NovaResolutionPlanServiceTest` | Claude |
| Nova - Generate Resolution Plan | Record-triggered flow (Case → Escalated) | `Nova_Generate_Resolution_Plan` | Claude |
| Nova - Update Resolution Plan | Autolaunched flow (agent action) | `Nova_Update_Resolution_Plan` | Claude |

### 3.8 Security
| Component | Type | API name | By |
|---|---|---|---|
| Nova Support Access | Permission set: field access to all Nova fields + access to Service Assistant Guide; assigned to **you** and the **agent user** | `Nova_Support_Access` | Claude |

### 3.9 Created and later removed (nothing left behind except Deleted Fields)
| What | Why removed |
|---|---|
| Case fields Robot Serial Number, Robot Model; category group `Kinetix_Support` | KUKA idea, switched back to the client-style |
| First versions of Player ID / Platform | Re-created during the switch |
| Prompt template `Nova_Resolution_Plan` | Apex grounding for Flex templates not available in this org → replaced by Apex + Models API |
| ~20 test Cases | Deleted after tests (your own test chats' Cases remain) |

Deleted custom fields stay in *Case → Fields & Relationships → Deleted Fields* for 15 days.

---

## 4. Known quality gaps (to tune next)

| Area | Gap | Lever |
|---|---|---|
| Knowledge | Only 6 short articles → generic answers and plans | Richer articles (exact menu paths, error codes, policy limits, macros) give the biggest quality gain |
| Nova replies | Can be long, stacks several questions, robotic hand-off text | Tighter tone rules (one question per turn, ≤ 3 sentences, no "User requested escalation…") |
| Resolution Plan | "Say:" lines claim actions are done before they are; long resolution notes; can repeat intake questions | Prompt rules: Say lines must ask or inform, never claim completion; ≤ 6 steps; "done when" criteria |
| Guide | Doesn't see the live chat (works from summary + what the advisor types) | Production: Messaging Record Grounding / Conversation API |
| Model | Default GPT-4o for the plan | Try a stronger model in the Models API call |
