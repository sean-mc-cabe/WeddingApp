# AI Builder Prompt & Power Automate Parsing Guide (No FAQs)

---

## 1. AI Builder Prompt

### Input

| Input Name | Type |
|-----------|------|
| `PolicyText` | Text |

### Prompt Text

```
You are a policy analyst. Analyze the policy document below and extract structured information. Return ONLY a valid JSON object with no markdown, no backticks, no preamble, and no explanation.

POLICY DOCUMENT:
{{PolicyText}}

Return this exact JSON structure. For any field where the information cannot be found in the document, use the string "Not present in source document." — never leave a field empty or null.

{
  "ContactEmail": "The contact email address for questions about this policy. Look for email addresses in headers, footers, contact sections, and the body text. If multiple emails exist, return the most relevant policy contact.",
  "Purpose": "2-3 sentences in plain English explaining why this policy exists and what it aims to achieve. Write in a professional but accessible tone.",
  "AppliesTo": "A clear statement of every group this policy covers: full-time employees, part-time employees, contractors, temporary staff, specific departments, specific roles, third-party vendors. Be exhaustive — check every section of the document, not just the scope section.",
  "DoesNotApplyTo": "Any explicit exclusions from scope. If none are stated, return: Not present in source document.",
  "KeyTopics": ["An array of 5-10 short topic labels that describe what this policy covers. Each label should be 2-5 words. Example: Expense Approval Limits, Travel Booking Process, Receipt Requirements"],
  "Summary": "A 2-4 paragraph plain English summary of the entire policy. Write in second person (you must, you should). Explain the policy as you would to a new employee. Cover: what the policy requires, the key obligations, and the most important things to remember day-to-day.",
  "KeyRulesNumbersThresholds": ["An array of strings. Extract EVERY specific number, date, monetary amount, percentage, time limit, and measurable threshold from the policy. Each item must contain a specific number and enough context to be understood standalone. Example: Expense reports must be submitted within 30 calendar days of the expense date."],
  "ProceduresAndRequiredSteps": ["An array of strings, each describing one step in the primary procedure(s) defined by the policy. If multiple procedures exist, combine into a single ordered list with clear labels. Example: Step 1 (Submitting a Claim): Log in to the expense portal at expenses.company.com. If no procedures are defined, return a single-item array: Not present in source document."],
  "Exceptions": ["An array of strings describing each exception, exemption, or edge case. Include: who can grant the exception, under what circumstances, and what process to follow. If no exceptions exist, return a single-item array: Not present in source document."],
  "NonComplianceConsequences": "A paragraph describing what happens when someone violates this policy. Include: disciplinary actions, escalation paths, reporting obligations, financial penalties, and impact on performance reviews. If not described, return: Not present in source document.",
  "RelatedDocuments": ["An array of strings. List every other policy, regulation, law, standard, form, or document referenced anywhere in this policy. Format: Document Name — one sentence on how it relates. If none are referenced, return a single-item array: Not present in source document."]
}

CRITICAL RULES:
1. Return ONLY the JSON object. No markdown code fences. No text before or after the JSON.
2. All string values must be properly escaped for JSON (escape quotes, newlines, backslashes).
3. Every field must be present in the output. Never omit a field.
4. KeyTopics must contain 5-10 items.
5. Use plain conversational English throughout. Do not copy dense legal language verbatim.
6. For array fields, each item should be self-contained and understandable without reading the others.
```

---

## 2. Power Automate Parsing

### Word Template Content Control Tags

| Content Control Tag | Type | Maps to JSON field |
|--------------------|------|--------------------|
| `ContactEmail` | Plain Text | `ContactEmail` |
| `Purpose` | Rich Text | `Purpose` |
| `AppliesTo` | Rich Text | `AppliesTo` |
| `DoesNotApplyTo` | Rich Text | `DoesNotApplyTo` |
| `KeyTopics` | Rich Text | `KeyTopics` (joined) |
| `Summary` | Rich Text | `Summary` |
| `KeyRules` | Rich Text | `KeyRulesNumbersThresholds` (joined) |
| `Procedures` | Rich Text | `ProceduresAndRequiredSteps` (joined) |
| `Exceptions` | Rich Text | `Exceptions` (joined) |
| `NonCompliance` | Rich Text | `NonComplianceConsequences` |
| `RelatedDocuments` | Rich Text | `RelatedDocuments` (joined) |

### Flow Actions (7 total, zero loops)

```
AFTER AI Builder prompt returns response...
│
├─ 1. Compose — "Clean JSON Response"
│      trim(
│        replace(
│          replace(
│            outputs('Run_AI_Builder_Prompt')?['responsev2/predictionOutput/text'],
│            '```json',
│            ''
│          ),
│          '```',
│          ''
│        )
│      )
│
├─ 2. Parse JSON — "Parse Policy JSON"
│      Content: outputs('Clean_JSON_Response')
│      Schema: (see below)
│
├─ 3. Compose — "Format Key Topics"
│      join(body('Parse_Policy_JSON')?['KeyTopics'], decodeUriComponent('%0A'))
│
├─ 4. Compose — "Format Key Rules"
│      join(body('Parse_Policy_JSON')?['KeyRulesNumbersThresholds'], decodeUriComponent('%0A'))
│
├─ 5. Compose — "Format Procedures"
│      join(body('Parse_Policy_JSON')?['ProceduresAndRequiredSteps'], decodeUriComponent('%0A'))
│
├─ 6. Compose — "Format Exceptions"
│      join(body('Parse_Policy_JSON')?['Exceptions'], decodeUriComponent('%0A'))
│
├─ 7. Compose — "Format Related Documents"
│      join(body('Parse_Policy_JSON')?['RelatedDocuments'], decodeUriComponent('%0A'))
│
├─ 8. Word Online — "Populate a Microsoft Word Template"
│      ┌──────────────────┬──────────────────────────────────────────────────────────────┐
│      │ Template Tag      │ Expression                                                   │
│      ├──────────────────┼──────────────────────────────────────────────────────────────┤
│      │ ContactEmail      │ coalesce(body('Parse_Policy_JSON')?['ContactEmail'],          │
│      │                   │   'Not present in source document.')                          │
│      │ Purpose           │ coalesce(body('Parse_Policy_JSON')?['Purpose'],               │
│      │                   │   'Not present in source document.')                          │
│      │ AppliesTo         │ coalesce(body('Parse_Policy_JSON')?['AppliesTo'],             │
│      │                   │   'Not present in source document.')                          │
│      │ DoesNotApplyTo    │ coalesce(body('Parse_Policy_JSON')?['DoesNotApplyTo'],        │
│      │                   │   'Not present in source document.')                          │
│      │ KeyTopics         │ coalesce(outputs('Format_Key_Topics'),                        │
│      │                   │   'Not present in source document.')                          │
│      │ Summary           │ coalesce(body('Parse_Policy_JSON')?['Summary'],               │
│      │                   │   'Not present in source document.')                          │
│      │ KeyRules          │ coalesce(outputs('Format_Key_Rules'),                         │
│      │                   │   'Not present in source document.')                          │
│      │ Procedures        │ coalesce(outputs('Format_Procedures'),                        │
│      │                   │   'Not present in source document.')                          │
│      │ Exceptions        │ coalesce(outputs('Format_Exceptions'),                        │
│      │                   │   'Not present in source document.')                          │
│      │ NonCompliance     │ coalesce(body('Parse_Policy_JSON')?['NonComplianceConse...'], │
│      │                   │   'Not present in source document.')                          │
│      │ RelatedDocuments  │ coalesce(outputs('Format_Related_Documents'),                 │
│      │                   │   'Not present in source document.')                          │
│      └──────────────────┴──────────────────────────────────────────────────────────────┘
│
├─ 9. Create File — SharePoint
│      Folder: KnowledgeSource Drafts
│      File Content: output of Word Online action
│
└─ Continue to Dataverse update...
```

### Parse JSON Schema

```json
{
  "type": "object",
  "required": [
    "ContactEmail",
    "Purpose",
    "AppliesTo",
    "DoesNotApplyTo",
    "KeyTopics",
    "Summary",
    "KeyRulesNumbersThresholds",
    "ProceduresAndRequiredSteps",
    "Exceptions",
    "NonComplianceConsequences",
    "RelatedDocuments"
  ],
  "properties": {
    "ContactEmail": { "type": "string" },
    "Purpose": { "type": "string" },
    "AppliesTo": { "type": "string" },
    "DoesNotApplyTo": { "type": "string" },
    "KeyTopics": {
      "type": "array",
      "items": { "type": "string" }
    },
    "Summary": { "type": "string" },
    "KeyRulesNumbersThresholds": {
      "type": "array",
      "items": { "type": "string" }
    },
    "ProceduresAndRequiredSteps": {
      "type": "array",
      "items": { "type": "string" }
    },
    "Exceptions": {
      "type": "array",
      "items": { "type": "string" }
    },
    "NonComplianceConsequences": { "type": "string" },
    "RelatedDocuments": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
```

---

## 3. FAQ Flow Integration Point

When you build the separate FAQ generation flow, it will need to:

1. **Trigger**: After the main summary document reaches a target status in Dataverse (e.g., "Draft Ready" or "Live" depending on when you want FAQs added)
2. **Input**: Either the source PDF text or the already-generated summary fields — the summary is often better input for FAQ generation because the language is already simplified
3. **Output**: Append FAQs to the existing Word document in the KnowledgeSource Drafts or Knowledge Source folder

The cleanest integration approach is to leave a `FAQs` Rich Text content control in your Word template as an empty placeholder. Your FAQ flow then:
- Generates the FAQ content
- Opens the existing summary DOCX from SharePoint
- Uses the Word Online connector's "Populate a Microsoft Word Template" to fill just the FAQs tag
- Overwrites the file in place

Alternatively, if you want to avoid reopening the Word file, store the FAQ content in a Dataverse column on the Policy Knowledge Pipeline table and populate the FAQs tag during the initial Word template population — but leave it blank until the FAQ flow fills the Dataverse column and re-triggers population.

---

## 4. Pitfall Reference

Same guards from the previous version still apply:

- **Markdown fences**: The Clean JSON Compose strips them
- **Null values**: Every field mapping uses `coalesce()` with a fallback string
- **Unescaped characters**: If Parse JSON fails, add a sanitisation Compose between Clean and Parse that strips tabs and null bytes:
  ```
  replace(replace(outputs('Clean_JSON_Response'), decodeUriComponent('%09'), ' '), decodeUriComponent('%00'), '')
  ```
- **Line breaks in Word**: If `decodeUriComponent('%0A')` doesn't create line breaks in the populated document, switch to `decodeUriComponent('%0D%0A')`
