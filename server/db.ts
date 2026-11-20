import { Pool as NeonPool, neonConfig } from "@neondatabase/serverless";
import { drizzle as drizzleNeon } from "drizzle-orm/neon-serverless";
import { drizzle as drizzlePg, type NodePgDatabase } from "drizzle-orm/node-postgres";
import pg from "pg";
import ws from "ws";
import * as schema from "@shared/schema";

if (!process.env.DATABASE_URL) {
  throw new Error(
    "DATABASE_URL environment variable is required (see .env.example). " +
      "Use a Neon URL in production or postgres://localhost:5432/lecturequest locally.",
  );
}

const url = process.env.DATABASE_URL;

/**
 * Neon's serverless driver talks to Neon over WebSockets and only works against Neon.
 * Any other Postgres (local Homebrew/Postgres.app, Docker, Render, Railway, Supabase…)
 * uses the standard node-postgres driver. Override with DB_DRIVER=neon|pg.
 */
const driver =
  process.env.DB_DRIVER ?? (/neon\.tech|neon\.build/.test(url) ? "neon" : "pg");

function createDb(): NodePgDatabase<typeof schema> {
  if (driver === "neon") {
    neonConfig.webSocketConstructor = ws;
    const pool = new NeonPool({ connectionString: url });
    // Both drivers expose the same query-builder API; cast to a single type for storage.ts.
    return drizzleNeon(pool, { schema }) as unknown as NodePgDatabase<typeof schema>;
  }
  const needsSsl = /sslmode=require/.test(url) || process.env.PGSSL === "true";
  const pool = new pg.Pool({
    connectionString: url,
    ssl: needsSsl ? { rejectUnauthorized: false } : undefined,
  });
  return drizzlePg(pool, { schema });
}

export const db = createDb();
export const dbDriver = driver;
