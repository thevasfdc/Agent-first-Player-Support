# Curated grounding pipeline: Batch Data Transform → Search Index → Retriever → Custom Retriever

Your the client steps, adapted to the Nova org (`fde-dev`, data space `default`).
Goal: the agents are grounded **only** in published, public, player-support articles, and not in Company News, drafts or stale categories, through a pipeline you control end to end.

---

## What Data 360 holds today (checked 2026-10-25)

| Data model object (DMO) | Rows | What's in it |
|---|---|---|
| `ssot__KnowledgeArticleVersion__dlm` | **11** | All 10 published articles **plus the draft**: Data 360 ingests everything |
| `DataCategorySelectionCustom__dlm` | 11 | Article ↔ category links, including 4 for **Company_News** |
| `DataCategoryCustom__dlm` | 9 | Nova_Support categories **plus stale KUKA ones** (Software_Licensing, Robot_Faults_Operation, Connectivity_Monitoring, a second "All") that were deleted in Salesforce |

Category IDs you'll see:

| DeveloperName | Data Category Id | Keep? |
|---|---|---|
| Purchases_Billing | `02ng7000000fEyIAAU` | ✅ |
| Account_Login | `02ng7000000fEyJAAU` | ✅ |
| Technical | `02ng7000000fEyKAAU` | ✅ |
| Company_News | `02ng7000000fOj7AAE` | ❌ |
| All (Nova_Support) | `02ng7000000fEyHAAU` | ❌ (parent; includes Company News) |
| Software_Licensing, Robot_Faults_Operation, Connectivity_Monitoring, All | `02ng7000000fEBt…EBw` | ❌ stale |

**the client → Nova mapping:** the client filtered on one curated category ("Service Assistant pilot"). Nova has no single curated category, so filter on the **three support categories** (Purchases_Billing, Account_Login, Technical).

**Expected output:** **6 rows** (the 6 published support articles). Excluded: 4 Company News articles + 1 draft.

## Baseline result: before the curated pipeline (2026-10-25)

| Test | Result |
|---|---|
| Nova (player agent): "When are the offices closed?" / "When is the esports championship?" | Refused as off-topic. The **topic guardrails** stop it before any Knowledge search (first line of defence) |
| Service Assistant Guide, General FAQ: "Per our knowledge articles, when is the summer esports championship final?" | **Answered from Company News**: "July 18–20, 2026, at the Austin Convention Center" → **irrelevant content leaks through the current library** (`Nova_Support.All`) |
| Guide: "Which days are the offices closed in 2026?" | Not found (partial retrieval while the index catches up) |

After the swap, the esports question must return "not in our knowledge articles".

---

## Step 1: Batch Data Transform

**Data 360 → Data Transforms → New → Batch Data Transform → Data Model Objects → data space `default` → Next**

1. **Add input data → `DataCategoryCustom`**
   Fields: `Id`, `DeveloperName`, `DataCategoryGroupId`, `MasterLabel`
   - If the preview doesn't show the Nova categories, **increase the sample size** (your the client tip).
2. **+ → Filter** on that input: `DeveloperName` **equals** `Purchases_Billing` **OR** `Account_Login` **OR** `Technical`
   (the client equivalent: `DeveloperName = Service Assistant pilot`.) This also drops the stale KUKA rows.
3. **Add input data → `DataCategorySelectionCustom`**
   Fields: `Id`, `DataCategoryId`, `ParentId`
4. **+ → Join (Join 1)**, **Inner**: Filter 1 `Id` = DataCategorySelectionCustom `DataCategoryId`
5. **Add input data → `KnowledgeArticleVersion`** (`ssot__KnowledgeArticleVersion__dlm`)
   Fields: `Id`, `Name`, `Answer_c` (the article body), `Description` (summary), `URL`, `ArticleNumber`, `KnowledgeArticleId`, `KnowledgePublicationStatus`, `IsVisibleInPublicKnowledgeBase`, `VersionNumber`, `FirstPublishedDateTime`, `Language`, `DataSourceId`, `DataSourceObjectId`
6. **+ → Filter (Filter 2)** on KnowledgeArticleVersion: `KnowledgePublicationStatus` = `Online`
   - Optional, to match today's library: AND `IsVisibleInPublicKnowledgeBase` = true, AND `Language` = `en_US`
7. **Join 1 → + → Join (Join 2)** with Filter 2, **Inner**: Join 1 `ParentId` = Filter 2 `Id`
8. **Join 2 → + → Output → Create New DMO**
   - Name: `Nova Agent Knowledge` (API name e.g. `Nova_Agent_Knowledge`)
   - Category: **Other**
   - Write mode: upsert / replace
   - **Primary key:** KnowledgeArticleVersion `Id` · **Key qualifier:** `DataCategoryId` (same as the client, so an article in two categories doesn't collide)
   - Map the fields from step 5 (keep `Answer_c`, `Name`, `Description`, `URL`, `KnowledgePublicationStatus`, `DataCategoryId`, `DeveloperName`)
9. **Save → Run Now** (the client tip: check the status is Processing, else click Run Now)

**Check:** tell me and I'll query the new DMO. Expected **6 rows**, no Company News, no draft.

---

## Step 2: Search Index

**Data 360 → Search Index → New → Advanced Setup → Hybrid Search → Source object = `Nova Agent Knowledge` DMO**

- **Chunking → Manage fields:** add `Answer_c`
  - Strip HTML: the client used **false**. The Nova article bodies are HTML lists, so **true** usually gives cleaner chunks. Try true; if steps lose their numbering, switch back.
  - **Prepend fields to each chunk:** on → add `Name`, `Description`
- **Fields for filtering:** drag `KnowledgePublicationStatus` to the right (add `DeveloperName` too, so you can filter by category at query time)
- **Review & Build:** give the index a unique name, e.g. `Nova_Agent_Knowledge_Index`
- **Check:** open the index → processing history should show **6 records** processed

---

## Step 3: Retriever

**Einstein Studio / Data 360 → Retrievers → New → Individual Retriever → Data Cloud → select the `Nova Agent Knowledge` DMO + `Nova_Agent_Knowledge_Index` → Next**

- **Filters:** optional `KnowledgePublicationStatus = Online`. This is where a data library "does its magic" (your the client note); here the transform has already done it.
- **Number of results:** the client used 50. With 6 articles anything ≥ 10 behaves the same; 20 is enough.
- **Fields to return:**
  - Related attributes → `<DMO>_chunk` → **Chunk**
  - Related attributes → `<DMO>_chunk` → **Source Record Id**
  - Related attributes → `<DMO>_index` → **Data Source**
  - Related attributes → `<DMO>_index` → **Data Source Object**
  - Optional: `Name`, `URL` (for citations)
- **Citations:** enable
- **Save → Activate**

---

## Step 4: Custom Retriever in a data library

**Setup → Agentforce Data Library → New Library** `Nova Agent Knowledge (curated)` → **Add data → Custom Retriever → select the retriever from step 3 → Save**

The data library is the wrapper the agents' **Answer Questions with Knowledge** action uses (the client: "used by SRA & SR").

---

## Step 5: Swap the agents (Claude does this once you say "library ready")

1. Read the new library ID (`1JD…`) with `sf agent adl list`.
2. In **both** agent scripts set `knowledge: rag_feature_config_id: "ARFPC_<new library id>"`:
   - Nova Support Agent → publish **v3** (v2 stays as rollback)
   - Service Assistant Guide → publish **v2**
3. **Before/after test** (same questions on both versions):

| Question to Nova | Old library (`Nova_Support.All`) | New curated library |
|---|---|---|
| "My gems never arrived" | Answers from *Missing purchase* | Same answer |
| "When are your offices closed?" | **May answer from Company News** (the problem) | No grounding → offers a human ("No answer found") |
| "What are the battle pass rewards?" | Draft excluded (public-only) | Excluded (Online-only filter) |

4. Rollback = reactivate the previous version (`sf agent activate --version`).

Note: the advisor-side Resolution Plan doesn't use the data library. Its Apex already queries only the 3 support categories (`WITH DATA CATEGORY`), so it is unaffected.

---

## Talking points (the client story)

- **Data streams ingest everything:** drafts, every category, even categories deleted in Salesforce (the stale KUKA rows prove it).
- **The transform makes grounding explicit:** published + curated categories only, so less to index (lower credits) and no stale or irrelevant answers.
- **The custom retriever + data library keeps the agent side unchanged:** same Knowledge action, different, curated source.

---

## Result: after the swap (2026-10-25, Nova v3 + Guide v2 active on Nova Custom Retriever)

| | Standard Knowledge library | Curated pipeline (transform → index → retriever) |
|---|---|---|
| Chunks in index | **33** (11 versions × 3), incl. 4 Company News + 1 Draft, even with only 3 categories selected and public-only on | **6** (6 published support articles) |
| Guide: "when is the summer esports championship final?" | Answered from Company News (leak) | "Our knowledge articles do not provide the date…" |
| Guide: "Season 5 battle pass rewards?" (draft) | — | "…do not list…" |
| Guide: "gems did not arrive?" | Answered | Answered (full procedure + escalation rule) |
