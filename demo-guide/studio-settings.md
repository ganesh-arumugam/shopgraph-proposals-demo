# Required GraphOS Studio Settings

Configure these before running the demo. All settings are per-graph.

## Proposals Check Severity (the CI gate setting)

This is the most important setting for the demo.

1. Go to **Studio → Your Graph → Graph Settings → Checks**
2. Find the **Proposals** task in the Checks Tasks table
3. Set severity to **Error**

Effect: `rover subgraph check` will fail if the schema changes are not part of an approved Proposal. This is what creates the CI gate shown in the demo.

| Severity | Effect |
|----------|--------|
| Off (default) | Proposals task not included in checks |
| Warning | Check passes but shows a warning |
| **Error** | **Check fails if changes lack an approved Proposal** ← set this |

## Proposals Configuration

Go to **Studio → Your Graph → Graph Settings → Proposals**:

| Setting | Recommended for demo | Why |
|---------|---------------------|-----|
| Required approvals | 1 or 2 | Lower = faster demo; 2 mirrors a real PR review policy |
| Require default reviewer approval | ✅ Enable | Shows that owner-team approval is required, not just anyone |
| Require reapprovals on revisions | ✅ Enable | Great to mention — prevents approval laundering |
| Description template | Optional | Add a template to show structured proposals |

## Default Reviewers

Default reviewers are set automatically by the `sync-reviewers` workflow once
`.github/contact-reviewer-map.json` is populated with real emails.

To set them manually (for demo prep without running the workflow):

1. Go to **Graph Settings → Proposals → Default Reviewers**
2. Click **Manage default reviewers**
3. Add the team members who should review all proposals on this graph

Once set, they are automatically assigned when a proposal moves to **Open for Feedback**.
