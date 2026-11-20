import * as oidc from "openid-client";
import session from "express-session";
import type { Express, Request, RequestHandler } from "express";
import connectPg from "connect-pg-simple";
import { storage } from "./storage";

const sessionLifetime = 7 * 24 * 60 * 60 * 1000;
const loginLifetime = 10 * 60 * 1000;
const cookieName = "lecturequest.sid";

declare module "express-session" {
  interface SessionData {
    userId: string;
    login?: { state: string; nonce: string; verifier: string; startedAt: number };
  }
}

function sessionOperation(operation: (callback: (error?: unknown) => void) => void) {
  return new Promise<void>((resolve, reject) => {
    operation(error => error ? reject(error) : resolve());
  });
}

export function setupAuth(app: Express) {
  const clientId = process.env.GOOGLE_CLIENT_ID?.trim();
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET?.trim();
  const sessionSecret = process.env.SESSION_SECRET;
  const production = process.env.NODE_ENV === "production";
  if (!clientId || !clientSecret || !sessionSecret || sessionSecret.length < 32) {
    throw new Error("Set GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET and a SESSION_SECRET of at least 32 characters.");
  }
  if (production && !process.env.APP_ORIGIN) throw new Error("Set APP_ORIGIN to the public HTTPS URL.");
  const appUrl = new URL(process.env.APP_ORIGIN ?? `http://localhost:${process.env.PORT || "5000"}`);
  const origin = appUrl.origin;
  const loopback = appUrl.hostname === "localhost" || appUrl.hostname === "127.0.0.1";
  if (appUrl.username || appUrl.password || appUrl.pathname !== "/" || appUrl.search || appUrl.hash ||
      (appUrl.protocol !== "https:" && (production || !loopback || appUrl.protocol !== "http:"))) {
    throw new Error("APP_ORIGIN must be a bare HTTPS origin (local development may use loopback HTTP).");
  }
  const secure = appUrl.protocol === "https:";
  const callbackUrl = new URL("/api/callback", origin);
  const allowedEmails = new Set((process.env.GOOGLE_ALLOWED_EMAILS ?? "").split(",").map(email => email.trim().toLowerCase()).filter(Boolean));
  let configuration: Promise<oidc.Configuration> | undefined;
  const getConfiguration = () => configuration ??= oidc.discovery(
    new URL("https://accounts.google.com"), clientId, clientSecret,
    oidc.ClientSecretPost(clientSecret),
    { execute: [oidc.enableNonRepudiationChecks] },
  ).catch((error: unknown) => {
    configuration = undefined;
    throw error;
  });

  if (process.env.TRUST_PROXY === "1") app.set("trust proxy", 1);

  app.use("/api", (req, res, next) => {
    res.set("Cache-Control", "no-store");
    if (!["GET", "HEAD", "OPTIONS"].includes(req.method) && req.get("origin") !== origin) {
      return res.status(403).json({ message: "Open LectureQuest using its configured URL." });
    }
    next();
  });

  const PgStore = connectPg(session);
  app.use("/api", session({
    name: cookieName,
    secret: sessionSecret,
    store: new PgStore({
      conString: process.env.DATABASE_URL,
      createTableIfMissing: false,
      ttl: sessionLifetime / 1000,
      tableName: "sessions",
    }),
    resave: false,
    saveUninitialized: false,
    cookie: { httpOnly: true, secure, sameSite: "lax", maxAge: sessionLifetime },
  }));

  app.get("/api/login", async (req, res) => {
    res.set("Referrer-Policy", "no-referrer");
    // Keep the OAuth transaction and callback on the same configured origin.
    if (req.get("host") !== appUrl.host || (secure && !req.secure)) {
      return res.redirect(new URL("/api/login", origin).href);
    }
    try {
      const config = await getConfiguration();
      const login = {
        state: oidc.randomState(),
        nonce: oidc.randomNonce(),
        verifier: oidc.randomPKCECodeVerifier(),
        startedAt: Date.now(),
      };
      const redirect = oidc.buildAuthorizationUrl(config, {
        redirect_uri: callbackUrl.href,
        scope: "openid email profile",
        prompt: "select_account",
        state: login.state,
        nonce: login.nonce,
        code_challenge: await oidc.calculatePKCECodeChallenge(login.verifier),
        code_challenge_method: "S256",
      });
      req.session.login = login;
      await sessionOperation(cb => req.session.save(cb));
      res.redirect(redirect.href);
    } catch {
      console.error("Could not start Google sign-in");
      res.redirect("/?auth=unavailable");
    }
  });

  app.get("/api/callback", async (req, res) => {
    res.set("Referrer-Policy", "no-referrer");
    if (req.get("host") !== appUrl.host || (secure && !req.secure)) {
      return res.status(400).send("Open LectureQuest using its configured URL and try signing in again.");
    }
    const login = req.session.login;
    if (!login || Date.now() - login.startedAt > loginLifetime || req.query.state !== login.state) {
      return res.redirect("/?auth=retry");
    }
    try {
      delete req.session.login;
      await sessionOperation(cb => req.session.save(cb));
      if (req.query.error === "access_denied") return res.redirect("/?auth=cancelled");

      const responseUrl = new URL(callbackUrl);
      responseUrl.search = req.originalUrl.slice(req.originalUrl.indexOf("?"));
      const tokens = await oidc.authorizationCodeGrant(await getConfiguration(), responseUrl, {
        pkceCodeVerifier: login.verifier,
        expectedState: login.state,
        expectedNonce: login.nonce,
        idTokenExpected: true,
      });
      const claims = tokens.claims();
      if (!claims?.sub || typeof claims.email !== "string" || claims.email_verified !== true) {
        return res.redirect("/?auth=unverified");
      }
      const email = claims.email.toLowerCase();
      if (allowedEmails.size && !allowedEmails.has(email)) return res.redirect("/?auth=restricted");

      // Provider namespace prevents a Google subject from claiming a legacy Replit identity.
      // A duplicate email is rejected by Postgres, never used to link accounts.
      const userId = `google:${claims.sub}`;
      try {
        await storage.upsertUser({
          id: userId,
          email,
          firstName: typeof claims.given_name === "string" ? claims.given_name : null,
          lastName: typeof claims.family_name === "string" ? claims.family_name : null,
          profileImageUrl: typeof claims.picture === "string" ? claims.picture : null,
        });
      } catch (error) {
        const dbError = error as { code?: string; cause?: { code?: string } };
        if (dbError.code === "23505" || dbError.cause?.code === "23505") {
          return res.redirect("/?auth=existing-account");
        }
        throw error;
      }

      // Rotate the session ID at sign-in and store only the app's user ID, no Google tokens.
      await sessionOperation(cb => req.session.regenerate(cb));
      req.session.userId = userId;
      await sessionOperation(cb => req.session.save(cb));
      res.redirect("/");
    } catch {
      console.error("Could not complete Google sign-in");
      res.redirect("/?auth=retry");
    }
  });

  app.post("/api/logout", (req, res, next) => {
    req.session.destroy(error => {
      if (error) return next(error);
      res.clearCookie(cookieName, { path: "/", httpOnly: true, sameSite: "lax", secure });
      res.redirect(303, "/");
    });
  });
}

export const isAuthenticated: RequestHandler = (req, res, next) => {
  if (!req.session.userId) return res.status(401).json({ message: "Unauthorized" });
  next();
};

export function authenticatedUserId(req: Request): string {
  // Called only after isAuthenticated on protected routes.
  return req.session.userId!;
}
