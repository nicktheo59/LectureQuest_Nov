/**
 * Google Sign-In (OpenID Connect) for LectureQuest.
 *
 * Replaces the old Replit Auth integration. Flow:
 *   GET /api/login     -> redirect to Google's consent screen (PKCE + state + nonce)
 *   GET /api/callback  -> exchange code, verify ID token, upsert user, start session
 *   GET /api/logout    -> destroy session, redirect home
 *   GET /api/auth/config -> tells the client which login options are enabled
 *
 * The session user object keeps the same shape the routes already rely on
 * (`req.user.claims.sub`), so no route handlers needed to change.
 *
 * Required env vars:
 *   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, SESSION_SECRET, DATABASE_URL
 * Optional:
 *   APP_URL            Public base URL, e.g. https://lecturequest.onrender.com
 *                      (used to build the redirect URI; falls back to the request host)
 *   ALLOWED_EMAIL_DOMAINS  Comma-separated list, e.g. "ucl.ac.uk,gmail.com"
 *   DEV_AUTH_BYPASS=true   (development only) adds a one-click "dev login"
 */
import * as client from "openid-client";
import passport from "passport";
import session from "express-session";
import connectPg from "connect-pg-simple";
import type { Express, Request, RequestHandler } from "express";
import { storage } from "./storage";

const GOOGLE_ISSUER = new URL("https://accounts.google.com");
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 1 week
const isProduction = process.env.NODE_ENV === "production";

export interface SessionUser {
  claims: {
    sub: string;
    email?: string;
    name?: string;
    picture?: string;
  };
  provider: "google" | "dev";
}

declare module "express-session" {
  interface SessionData {
    oauth?: { codeVerifier: string; state: string; nonce: string; redirectUri: string };
    returnTo?: string;
  }
}

let googleConfigPromise: Promise<client.Configuration> | null = null;

export function isGoogleConfigured() {
  return Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET);
}

export function isDevBypassEnabled() {
  return !isProduction && process.env.DEV_AUTH_BYPASS === "true";
}

function getGoogleConfig() {
  if (!googleConfigPromise) {
    googleConfigPromise = client
      .discovery(GOOGLE_ISSUER, process.env.GOOGLE_CLIENT_ID!, process.env.GOOGLE_CLIENT_SECRET!)
      .catch((err) => {
        googleConfigPromise = null; // allow retry on next request
        throw err;
      });
  }
  return googleConfigPromise;
}

function baseUrl(req: Request) {
  if (process.env.APP_URL) return process.env.APP_URL.replace(/\/+$/, "");
  return `${req.protocol}://${req.get("host")}`;
}

export function getSession() {
  if (!process.env.SESSION_SECRET) {
    throw new Error("SESSION_SECRET environment variable is required");
  }
  const PgStore = connectPg(session);
  const sessionStore = new PgStore({
    conString: process.env.DATABASE_URL,
    // The "sessions" table is part of shared/schema.ts (created by `npm run db:push`),
    // but create it automatically too so first boot never fails.
    createTableIfMissing: true,
    ttl: SESSION_TTL_MS / 1000,
    tableName: "sessions",
  });
  return session({
    secret: process.env.SESSION_SECRET,
    store: sessionStore,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      // Secure cookies need HTTPS; local `npm run dev` runs on plain http.
      secure: isProduction,
      sameSite: "lax", // must be lax (not strict) so the cookie survives Google's redirect back
      maxAge: SESSION_TTL_MS,
    },
  });
}

function emailAllowed(email: string | undefined) {
  const domains = (process.env.ALLOWED_EMAIL_DOMAINS || "")
    .split(",")
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean);
  if (domains.length === 0) return true;
  if (!email) return false;
  const domain = email.split("@")[1]?.toLowerCase();
  return !!domain && domains.includes(domain);
}

/**
 * Insert/update the user. If a user with the same (Google-verified) email already
 * exists — e.g. rows created by the previous Replit Auth — reuse that account's id
 * so existing lectures/XP carry over instead of hitting the unique(email) constraint.
 */
async function upsertGoogleUser(claims: Record<string, any>): Promise<string> {
  const email: string | undefined = claims.email;
  let userId = `google:${claims.sub}`;

  if (email && claims.email_verified) {
    const existing = await storage.getUserByEmail(email);
    if (existing) userId = existing.id;
  }

  await storage.upsertUser({
    id: userId,
    email: email ?? null,
    firstName: claims.given_name ?? null,
    lastName: claims.family_name ?? null,
    profileImageUrl: claims.picture ?? null,
  });
  return userId;
}

function safeReturnTo(value: unknown): string {
  // Only allow same-site relative paths to avoid open redirects.
  if (typeof value === "string" && value.startsWith("/") && !value.startsWith("//")) return value;
  return "/";
}

export async function setupAuth(app: Express) {
  app.set("trust proxy", 1); // honour X-Forwarded-Proto behind Render/Fly/Railway proxies
  app.use(getSession());
  app.use(passport.initialize());
  app.use(passport.session());

  passport.serializeUser((user: Express.User, cb) => cb(null, user));
  passport.deserializeUser((user: Express.User, cb) => cb(null, user));

  if (!isGoogleConfigured()) {
    console.warn(
      "[auth] GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET not set — Google login is disabled." +
        (isDevBypassEnabled() ? " DEV_AUTH_BYPASS is on: use /api/login/dev." : ""),
    );
  }

  app.get("/api/auth/config", (_req, res) => {
    res.json({ google: isGoogleConfigured(), devBypass: isDevBypassEnabled() });
  });

  app.get("/api/login", async (req, res, next) => {
    try {
      if (!isGoogleConfigured()) {
        if (isDevBypassEnabled()) return res.redirect("/api/login/dev");
        return res
          .status(503)
          .send("Google login is not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET.");
      }
      const config = await getGoogleConfig();
      const codeVerifier = client.randomPKCECodeVerifier();
      const codeChallenge = await client.calculatePKCECodeChallenge(codeVerifier);
      const state = client.randomState();
      const nonce = client.randomNonce();
      const redirectUri = `${baseUrl(req)}/api/callback`;

      req.session.oauth = { codeVerifier, state, nonce, redirectUri };
      req.session.returnTo = safeReturnTo(req.query.returnTo);

      const url = client.buildAuthorizationUrl(config, {
        redirect_uri: redirectUri,
        scope: "openid email profile",
        code_challenge: codeChallenge,
        code_challenge_method: "S256",
        state,
        nonce,
        prompt: "select_account",
      });
      req.session.save((err) => (err ? next(err) : res.redirect(url.href)));
    } catch (err) {
      next(err);
    }
  });

  app.get("/api/callback", async (req, res) => {
    const pending = req.session.oauth;
    const returnTo = safeReturnTo(req.session.returnTo);
    delete req.session.oauth;
    delete req.session.returnTo;

    if (!pending) return res.redirect("/?auth_error=session_expired");
    if (req.query.error) return res.redirect(`/?auth_error=${encodeURIComponent(String(req.query.error))}`);

    try {
      const config = await getGoogleConfig();
      const currentUrl = new URL(req.originalUrl, pending.redirectUri);
      const tokens = await client.authorizationCodeGrant(config, currentUrl, {
        pkceCodeVerifier: pending.codeVerifier,
        expectedState: pending.state,
        expectedNonce: pending.nonce,
      });
      const claims = tokens.claims();
      if (!claims) throw new Error("No ID token returned by Google");
      if (!emailAllowed(claims.email as string | undefined)) {
        return res.redirect("/?auth_error=domain_not_allowed");
      }

      const userId = await upsertGoogleUser(claims);
      const user: SessionUser = {
        provider: "google",
        claims: {
          sub: userId,
          email: claims.email as string | undefined,
          name: claims.name as string | undefined,
          picture: claims.picture as string | undefined,
        },
      };

      // Regenerate the session on login to prevent session fixation.
      req.session.regenerate((regenErr) => {
        if (regenErr) return res.redirect("/?auth_error=session");
        req.login(user, (loginErr) => {
          if (loginErr) return res.redirect("/?auth_error=login");
          req.session.save(() => res.redirect(returnTo));
        });
      });
    } catch (err) {
      console.error("[auth] Google callback failed:", err);
      res.redirect("/?auth_error=callback_failed");
    }
  });

  if (isDevBypassEnabled()) {
    // Local development only: sign in as a fixed test user without Google.
    app.get("/api/login/dev", async (req, res, next) => {
      try {
        const id = "dev:local-user";
        await storage.upsertUser({
          id,
          email: "dev@lecturequest.local",
          firstName: "Dev",
          lastName: "User",
          profileImageUrl: null,
        });
        const user: SessionUser = {
          provider: "dev",
          claims: { sub: id, email: "dev@lecturequest.local", name: "Dev User" },
        };
        req.login(user, (err) => (err ? next(err) : res.redirect("/")));
      } catch (err) {
        next(err);
      }
    });
  }

  const logout: RequestHandler = (req, res) => {
    req.logout(() => {
      req.session.destroy(() => {
        res.clearCookie("connect.sid");
        if (req.method === "GET") return res.redirect("/");
        res.json({ ok: true });
      });
    });
  };
  app.get("/api/logout", logout);
  app.post("/api/logout", logout);
}

export const isAuthenticated: RequestHandler = (req, res, next) => {
  const user = req.user as SessionUser | undefined;
  if (!req.isAuthenticated() || !user?.claims?.sub) {
    return res.status(401).json({ message: "Unauthorized" });
  }
  next();
};
