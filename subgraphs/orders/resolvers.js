import { ORDERS } from "./data.js";

const getOrderById = (id) => ORDERS.find((o) => o.id === id);

export const resolvers = {
  Query: {
    order: (_, { id }) => getOrderById(id),
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
