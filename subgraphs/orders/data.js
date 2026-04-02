// Mock order data for ShopGraph proposals demo.
// estimatedDelivery is intentionally absent — it will be added via a Proposal.

const now = new Date();
const daysAgo = (n) => new Date(now - n * 86_400_000).toISOString();

export const ORDERS = [
  {
    id: "order:1",
    buyerId: "user:1",
    status: "DELIVERED",
    placedAt: daysAgo(14),
    items: [
      { variantId: "variant:1", quantity: 1, unitPrice: 149.99 },
      { variantId: "variant:6", quantity: 2, unitPrice: 49.99 },
    ],
  },
  {
    id: "order:2",
    buyerId: "user:1",
    status: "SHIPPED",
    placedAt: daysAgo(3),
    items: [
      { variantId: "variant:4", quantity: 1, unitPrice: 219.00 },
    ],
  },
  {
    id: "order:3",
    buyerId: "user:2",
    status: "PROCESSING",
    placedAt: daysAgo(1),
    items: [
      { variantId: "variant:7", quantity: 1, unitPrice: 189.00 },
      { variantId: "variant:9", quantity: 1, unitPrice: 89.00 },
    ],
  },
  {
    id: "order:4",
    buyerId: "user:3",
    status: "PLACED",
    placedAt: daysAgo(0),
    items: [
      { variantId: "variant:2", quantity: 1, unitPrice: 149.99 },
      { variantId: "variant:5", quantity: 1, unitPrice: 219.00 },
      { variantId: "variant:10", quantity: 2, unitPrice: 89.00 },
    ],
  },
];
