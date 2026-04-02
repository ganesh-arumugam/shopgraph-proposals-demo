// Mock product catalog for ShopGraph proposals demo
// Deliberately small and legible — customers can read the data on screen

export const PRODUCTS = [
  {
    id: "product:1",
    title: "Trail Runner Pro",
    description: "Lightweight trail running shoe with superior grip.",
    mediaUrl: "https://picsum.photos/seed/trail/400/300",
    category: "Footwear",
    variants: ["variant:1", "variant:2", "variant:3"],
  },
  {
    id: "product:2",
    title: "Summit Fleece Jacket",
    description: "Warm mid-layer fleece for alpine conditions.",
    mediaUrl: "https://picsum.photos/seed/fleece/400/300",
    category: "Outerwear",
    variants: ["variant:4", "variant:5"],
  },
  {
    id: "product:3",
    title: "Titanium Water Bottle",
    description: "32oz ultra-light titanium bottle. BPA free.",
    mediaUrl: "https://picsum.photos/seed/bottle/400/300",
    category: "Accessories",
    variants: ["variant:6"],
  },
  {
    id: "product:4",
    title: "Carbon Trekking Poles",
    description: "Collapsible carbon fibre poles. 3-section, 130g each.",
    mediaUrl: "https://picsum.photos/seed/poles/400/300",
    category: "Gear",
    variants: ["variant:7", "variant:8"],
  },
  {
    id: "product:5",
    title: "Merino Base Layer",
    description: "Temperature-regulating merino wool base layer.",
    mediaUrl: "https://picsum.photos/seed/merino/400/300",
    category: "Clothing",
    variants: ["variant:9", "variant:10"],
  },
];

export const VARIANTS = [
  { id: "variant:1", product: { id: "product:1" }, colorway: "Forest Green", price: 149.99, size: "US 9" },
  { id: "variant:2", product: { id: "product:1" }, colorway: "Slate Grey", price: 149.99, size: "US 10" },
  { id: "variant:3", product: { id: "product:1" }, colorway: "Ocean Blue", price: 154.99, size: "US 11" },
  { id: "variant:4", product: { id: "product:2" }, colorway: "Burgundy", price: 219.00, size: "M" },
  { id: "variant:5", product: { id: "product:2" }, colorway: "Charcoal", price: 219.00, size: "L" },
  { id: "variant:6", product: { id: "product:3" }, colorway: "Natural Titanium", price: 49.99, size: "32oz" },
  { id: "variant:7", product: { id: "product:4" }, colorway: "Black", price: 189.00, size: "105-135cm" },
  { id: "variant:8", product: { id: "product:4" }, colorway: "Black", price: 189.00, size: "115-145cm" },
  { id: "variant:9", product: { id: "product:5" }, colorway: "Cream", price: 89.00, size: "S" },
  { id: "variant:10", product: { id: "product:5" }, colorway: "Cream", price: 89.00, size: "XL" },
];
