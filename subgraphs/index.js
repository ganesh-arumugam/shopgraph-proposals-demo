/**
 * ShopGraph Proposals Demo — Subgraph Server
 *
 * Runs both subgraphs (products, orders) on a single Express server,
 * each at its own path. Mirrors the pattern from the existing feature template.
 */

import { expressMiddleware } from "@apollo/server/express4";
import { ApolloServer } from "@apollo/server";
import { ApolloServerPluginDrainHttpServer } from "@apollo/server/plugin/drainHttpServer";
import express from "express";
import http from "http";
import cors from "cors";
import bodyParser from "body-parser";
import { getProductsSchema } from "./products/subgraph.js";
import { getOrdersSchema } from "./orders/subgraph.js";

const SUBGRAPHS = [
  { name: "products", getSchema: getProductsSchema },
  { name: "orders", getSchema: getOrdersSchema },
];

export const startSubgraphs = async (port = 4001) => {
  const app = express();
  const httpServer = http.createServer(app);
  const serverPort = process.env.PORT ?? port;

  for (const subgraph of SUBGRAPHS) {
    const schema = subgraph.getSchema();
    const server = new ApolloServer({
      schema,
      introspection: true, // enabled for demo purposes
      plugins: [ApolloServerPluginDrainHttpServer({ httpServer })],
    });

    await server.start();

    const path = `/${subgraph.name}/graphql`;
    app.use(
      path,
      cors(),
      bodyParser.json(),
      expressMiddleware(server, {
        context: async ({ req }) => ({ headers: req.headers }),
      })
    );

    console.log(`  ✓ [${subgraph.name}] → http://localhost:${serverPort}${path}`);
  }

  await new Promise((resolve) => httpServer.listen({ port: serverPort }, resolve));
  console.log(`\n🚀 All subgraphs running on port ${serverPort}`);
};

// Start when run directly
startSubgraphs();
