import { PRODUCTS, VARIANTS } from "./data.js";

export const getProductById = (id) => PRODUCTS.find((p) => p.id === id);
export const getVariantById = (id) => VARIANTS.find((v) => v.id === id);

// ─── Observability demo hook (reversible) ───────────────────────────────
// Makes the `product` query throw ONLY for the id in DEMO_FAIL_PRODUCT_ID,
// so the committed code stays correct. Used by the error-correlation use
// case in observability/DEMO.md:
//   DEMO_FAIL_PRODUCT_ID=product:boom npm run start:subgraphs
const failProductId = process.env.DEMO_FAIL_PRODUCT_ID || "";
// ────────────────────────────────────────────────────────────────────────

export const resolvers = {
  Query: {
    product: (_, { id }) => {
      if (failProductId && id === failProductId) {
        throw new Error("Catalog lookup failed: downstream inventory timeout");
      }
      return getProductById(id);
    },
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
