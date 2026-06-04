import { ORDERS } from "./data.js";

const getOrderById = (id) => ORDERS.find((o) => o.id === id);

// ─── Observability demo hook (reversible) ───────────────────────────────
// Adds artificial latency to the `order` query ONLY when DEMO_SLOW_ORDERS_MS
// is set, so the committed code stays correct. Used by the latency use case
// in observability/DEMO.md:  DEMO_SLOW_ORDERS_MS=800 npm run start:subgraphs
const slowMs = Number(process.env.DEMO_SLOW_ORDERS_MS) || 0;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// ────────────────────────────────────────────────────────────────────────

export const resolvers = {
  Query: {
    order: async (_, { id }) => {
      if (slowMs > 0) await sleep(slowMs);
      return getOrderById(id);
    },
    orders: () => ORDERS,
  },
  Order: {
    __resolveReference(ref) {
      return getOrderById(ref.id);
    },
    items(parent) {
      return parent.items.map((item) => ({
        variant: { id: item.variantId },
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      }));
    },
  },
};
