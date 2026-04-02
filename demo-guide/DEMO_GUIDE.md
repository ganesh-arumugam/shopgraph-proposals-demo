# ShopGraph — Schema Proposals Live Demo Guide

**Duration:** 7–10 minutes
**Audience:** Engineering leads, platform/API governance teams, architects
**Goal:** Show how Apollo GraphOS Schema Proposals governs schema changes end-to-end — from proposal creation through CI gate to published implementation — with schema-native ownership via `@contact`.

---

## Before the Demo (SE Setup Checklist)

- [ ] Subgraphs running: `npm run dev:subgraphs` (port 4001)
- [ ] Router running: `npm run router:start` (port 4000)
- [ ] GraphOS Studio open to the **ShopGraph** graph, **Proposals** tab
- [ ] Explorer open, base URL pointed at `http://localhost:4000`
- [ ] A PR open in GitHub with `estimatedDelivery` added to `orders/schema.graphql`
      (branch: `feature/add-estimated-delivery`)
- [ ] Proposals check severity = **Error** configured in Studio (see `studio-settings.md`)
- [ ] GitHub PR showing the ❌ failed schema check (Proposals task failing)

**Reset between demos:** Checkout the `main` branch (no `estimatedDelivery`), close any open proposals.

---

## Act 1 — The Problem (60 sec)

> *"Let me start with a scenario you've probably lived through. A backend engineer adds a new field to a shared GraphQL schema. They mention it in Slack, maybe update a wiki page. Three weeks later, a client team tries to use the field and finds it was renamed, or the resolver isn't done yet, or worse — they find out about the field by introspecting prod. Sound familiar?"*

**Action:** Open Explorer, run `GetAllOrders` — show the Order type with no `estimatedDelivery`.

> *"This is our Orders subgraph. A customer is asking: when does my order arrive? The field doesn't exist yet. Let's walk through what it looks like to add it the right way."*

---

## Act 2 — Schema Ownership via `@contact` (90 sec)

**Action:** In Studio → Schema → SDL tab, click on the `orders` subgraph.

> *"Notice this metadata card. It shows that the Commerce Team owns this subgraph — their Slack channel is linked, their oncall is linked. That information doesn't live in a wiki or a README that goes stale. It lives **in the schema itself**, as a `@contact` directive."*

**Show in Studio:** The contact hover card on the `orders` subgraph name.

**Then open `subgraphs/orders/schema.graphql` in VS Code:**

```graphql
extend schema
  @contact(
    name: "Commerce Team"
    url: "https://yourorg.slack.com/archives/C_COMMERCE"
    description: "Owns order lifecycle, fulfillment, and delivery data."
  )
```

> *"And here's where it gets interesting. We have a script — triggered whenever the schema changes — that reads these `@contact` directives and automatically configures the Commerce Team as default reviewers on any Proposal. The schema becomes the source of truth for governance, not a separate spreadsheet."*

**Talking point if questioned:** "Yes, there's a mapping file that translates team names to org member emails — `.github/contact-reviewer-map.json`. It's a one-time setup, and it lives in the repo alongside the schema."

---

## Act 3 — Creating the Proposal (2 min)

**Action:** In Studio → Proposals → click **Propose Changes**

> *"Let's create the proposal. I'm calling it: 'Add estimatedDelivery to Order'."*

Fill in:
- **Title:** Add estimatedDelivery to Order
- **Description:** (use the template or type):
  > "The Commerce team is adding delivery date estimation. Clients need `estimatedDelivery: String` on the `Order` type to surface expected arrival in the UI."

Click **Create Proposal** → You land in the Editor tab.

> *"The editor is a full GraphQL-aware SDL editor. I can edit the orders subgraph schema directly here, with autocomplete, composition validation, and linting built in."*

**Action:** Add the field in the editor:
```graphql
"""
Estimated delivery date for this order (ISO 8601).
Null for orders not yet shipped.
"""
estimatedDelivery: String
```

Click **Save Revision** → Composition runs → Checks appear in the Checks tab.

> *"Every time I save a revision, schema checks run automatically — just like they would in CI. I can see right now whether this change would break any existing operations or composition."*

**Status is: DRAFT**

---

## Act 4 — Review & The CI Gate (2 min)

**Action:** Click **Edit Status → Open for Feedback**

> *"The proposal is ready for review. When the status changes to 'Open for Feedback', the Commerce Team members are automatically assigned as reviewers — that's our `@contact` automation at work. They get an email notification."*

**Show:** The reviewers panel — Commerce Team members appear automatically.

**Action:** Add a comment on the `estimatedDelivery` field:
> *"Here I can have a real design conversation inline: 'Should this be nullable for backorders?' — I'll approve but note this for v2."*

**Then switch to GitHub** — show the open PR with the `estimatedDelivery` code change.

> *"Meanwhile, the developer has implemented the resolver and opened a PR. Watch what happens when CI runs."*

**Show:** The GitHub PR with the ❌ schema-check failing.

Click into the check details:
```
❌ Proposals: 1 change (estimatedDelivery: String on Order) not included in an approved proposal
```

> *"The CI gate. The `rover subgraph check` command includes a Proposals task. Because we've set its severity to Error in Studio, CI physically cannot pass — and the PR cannot merge — until this change is backed by an approved Proposal. No rogue schema changes. No surprise fields in production."*

---

## Act 5 — Approval Unlocks CI (60 sec)

**Action:** Back in Studio — approve the Proposal (click **Approve**).
Status transitions to: **✅ APPROVED**

> *"The minimum approvals are met. Status is now Approved. Let's see what happens to the PR."*

**Action:** In GitHub, trigger a re-run of the schema check (or push a trivial commit).

**Show:** The check turns ✅ green:
```
✅ Proposals: All changes included in approved proposals
✅ Composition: No errors
✅ Operations: No breaking changes
```

> *"The CI gate opens. Now the team can merge."*

---

## Act 6 — Publish & Implemented (60 sec)

**Action:** Merge the PR in GitHub → Watch the `publish.yml` workflow run.

> *"On merge to main, our publish workflow runs `rover subgraph publish`. GraphOS receives the new schema, composes the supergraph, and — because all the changes in the proposal are now published — automatically marks the proposal as Implemented."*

**Show in Studio:** Proposal status → **✅ IMPLEMENTED**

> *"Full audit trail. Who proposed it, every revision, who commented, who approved, when it was published. Six months from now when someone asks 'why does Order have estimatedDelivery?' — this is the answer."*

---

## Act 7 — The Live Proof (30 sec)

**Action:** Back in Explorer — run `GetOrderWithDelivery`:
```graphql
query {
  order(id: "order:1") {
    id
    status
    placedAt
    estimatedDelivery  # ← this field now exists
  }
}
```

> *"The field is live. Governed, audited, traceable."*

---

## Objection Handling

**"We already do this with PRs and CODEOWNERS."**
> "CODEOWNERS blocks the PR — but it doesn't understand GraphQL. Proposals knows that `estimatedDelivery: String` is a new field addition, not just a text change. It can run composition, check breaking changes against live operations, and link the change to an approval — all natively. You'd need a custom tool chain to replicate this with CODEOWNERS alone."

**"What if a team publishes without a proposal?"**
> "That's what the CI gate prevents. As long as `rover subgraph check` runs in your pipeline with Proposals severity set to Error, an unapproved change cannot pass CI. You can optionally also block direct pushes to main via branch protection."

**"Can we require specific teams to approve?"**
> "Yes — with the 'Require at least one default reviewer' setting, an approval from a non-default reviewer doesn't count. Combined with our `@contact` automation, that means the subgraph owner's approval is required for every proposal touching their subgraph."

---

## Key Studio Settings to Configure (show customer)

1. **Proposals check severity** → Graph Settings → Schema Checks → Proposals task → **Error**
2. **Required approvals** → Graph Settings → Proposals → Required Approvals → **2** (or match their PR review requirements)
3. **Require default reviewer approval** → enable "Require at least one default reviewer"
4. **Require reapprovals on revision** → enable "Withdraw previous approvals on new revisions"
