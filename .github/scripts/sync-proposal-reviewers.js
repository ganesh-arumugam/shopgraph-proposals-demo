#!/usr/bin/env node
/**
 * sync-proposal-reviewers.js
 *
 * Reads @contact directives from subgraph SDL files, maps team names to
 * GraphOS org member user IDs (via contact-reviewer-map.json), then calls
 * the GraphOS Platform API to set those members as default reviewers on
 * the graph's Proposal configuration.
 *
 * This makes the schema the source of truth for proposal governance:
 *   @contact(name: "Commerce Team") → Commerce Team members auto-added as reviewers
 *
 * Usage:
 *   APOLLO_KEY=<key> APOLLO_GRAPH_ID=<id> node sync-proposal-reviewers.js
 *
 * Required env vars:
 *   APOLLO_KEY      — a Personal API key (service keys cannot list org members)
 *   APOLLO_GRAPH_ID — the GraphOS graph ID (not the graph ref)
 *
 * Required file:
 *   .github/contact-reviewer-map.json — maps @contact.name → array of user emails
 */

import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "../..");

// ─── Config ────────────────────────────────────────────────────────────────

const APOLLO_KEY = process.env.APOLLO_KEY;
const APOLLO_GRAPH_ID = process.env.APOLLO_GRAPH_ID;
const PLATFORM_API = "https://graphql.api.apollographql.com/api/graphql";

if (!APOLLO_KEY || !APOLLO_GRAPH_ID) {
  console.error("ERROR: APOLLO_KEY and APOLLO_GRAPH_ID must be set.");
  process.exit(1);
}

// ─── Step 1: Parse @contact directives from SDL files ──────────────────────

const SUBGRAPH_SCHEMAS = [
  resolve(REPO_ROOT, "subgraphs/products/schema.graphql"),
  resolve(REPO_ROOT, "subgraphs/orders/schema.graphql"),
];

/**
 * Extracts the @contact name from a SDL string.
 * Matches: @contact( ... name: "Team Name" ... )
 */
function extractContactName(sdl) {
  const match = sdl.match(/@contact\s*\([^)]*name:\s*"([^"]+)"/);
  return match ? match[1] : null;
}

const contactNames = new Set();
for (const schemaPath of SUBGRAPH_SCHEMAS) {
  const sdl = readFileSync(schemaPath, "utf8");
  const name = extractContactName(sdl);
  if (name) {
    console.log(`  Found @contact: "${name}" in ${schemaPath.split("/").slice(-2).join("/")}`);
    contactNames.add(name);
  } else {
    console.warn(`  WARNING: No @contact found in ${schemaPath.split("/").slice(-2).join("/")}`);
  }
}

if (contactNames.size === 0) {
  console.log("No @contact directives found. Nothing to sync.");
  process.exit(0);
}

// ─── Step 2: Load contact → reviewer email mapping ─────────────────────────

const mapPath = resolve(__dirname, "../contact-reviewer-map.json");
let contactMap;
try {
  contactMap = JSON.parse(readFileSync(mapPath, "utf8"));
} catch (e) {
  console.error(`ERROR: Could not read contact-reviewer-map.json at ${mapPath}`);
  console.error("Create the file with the format shown in .github/contact-reviewer-map.example.json");
  process.exit(1);
}

// Collect all reviewer emails from matched contact names
const reviewerEmails = new Set();
for (const name of contactNames) {
  const emails = contactMap[name];
  if (!emails || emails.length === 0) {
    console.warn(`  WARNING: No reviewer mapping found for contact "${name}". Add it to contact-reviewer-map.json.`);
    continue;
  }
  for (const email of emails) {
    reviewerEmails.add(email);
    console.log(`  Mapped "${name}" → ${email}`);
  }
}

if (reviewerEmails.size === 0) {
  console.log("No reviewers to sync after mapping. Check contact-reviewer-map.json.");
  process.exit(0);
}

// ─── Step 3: Resolve emails → GraphOS user IDs via Platform API ────────────

async function gql(query, variables = {}) {
  const res = await fetch(PLATFORM_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": APOLLO_KEY,
    },
    body: JSON.stringify({ query, variables }),
  });

  if (!res.ok) {
    throw new Error(`Platform API HTTP ${res.status}: ${await res.text()}`);
  }

  const json = await res.json();
  if (json.errors) {
    throw new Error(`Platform API errors: ${JSON.stringify(json.errors, null, 2)}`);
  }
  return json.data;
}

// Fetch org members to resolve emails → user IDs
const orgData = await gql(`
  query GetOrgMembers($graphId: ID!) {
    graph(id: $graphId) {
      id
      account {
        members {
          user {
            id
            email
          }
        }
      }
    }
  }
`, { graphId: APOLLO_GRAPH_ID });

const members = orgData?.graph?.account?.members ?? [];
const emailToUserId = new Map(
  members.map((m) => [m.user.email, m.user.id])
);

const reviewerUserIds = [];
for (const email of reviewerEmails) {
  const userId = emailToUserId.get(email);
  if (!userId) {
    console.warn(`  WARNING: Email "${email}" not found in GraphOS org. Skipping.`);
  } else {
    reviewerUserIds.push(userId);
    console.log(`  Resolved ${email} → userId: ${userId}`);
  }
}

if (reviewerUserIds.length === 0) {
  console.log("No valid reviewer user IDs resolved. Check that emails are org members.");
  process.exit(1);
}

// ─── Step 4: Update default reviewers via Platform API ─────────────────────

console.log(`\nUpdating default reviewers for graph: ${APOLLO_GRAPH_ID}`);
console.log(`  Setting ${reviewerUserIds.length} default reviewer(s)...`);

const updateData = await gql(`
  mutation UpdateProposalDefaultReviewers($graphId: ID!, $reviewerUserIds: [ID!]!) {
    graph(id: $graphId) {
      updateProposalLifecycleSubscriptions(input: {
        defaultReviewerUserIds: $reviewerUserIds
      }) {
        ... on GraphVariant {
          id
        }
        ... on PermissionError {
          message
        }
        ... on ValidationError {
          message
        }
      }
    }
  }
`, { graphId: APOLLO_GRAPH_ID, reviewerUserIds });

console.log("\n✅ Default reviewers synced successfully.");
console.log("   Verify in GraphOS Studio → Graph Settings → Proposals → Default Reviewers");
console.log("\nReview result:", JSON.stringify(updateData, null, 2));
