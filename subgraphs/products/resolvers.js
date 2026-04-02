import { PRODUCTS, VARIANTS } from "./data.js";

export const getProductById = (id) => PRODUCTS.find((p) => p.id === id);
export const getVariantById = (id) => VARIANTS.find((v) => v.id === id);

export const resolvers = {
  Query: {
    product: (_, { id }) => getProductById(id),
    variant: (_, { id }) => getVariantById(id),
    searchProducts(_, { searchInput }) {
      if (searchInput?.titleStartsWith) {
        return PRODUCTS.filter((p) =>
          p.title.toLowerCase().startsWith(searchInput.titleStartsWith.toLowerCase())
        );
      }
      return PRODUCTS;
    },
  },
  Product: {
    __resolveReference(ref) {
      return getProductById(ref.id);
    },
    variants(parent) {
      return parent.variants.map((id) => getVariantById(id));
    },
  },
  Variant: {
    __resolveReference(ref) {
      return getVariantById(ref.id);
    },
    product(parent) {
      const variant = getVariantById(parent.id);
      return getProductById(variant.product.id);
    },
  },
};
