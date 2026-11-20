# LectureQuest

Turn lecture notes and PDFs into study material. The web app runs a React/Vite frontend and an Express server on one origin, with Neon PostgreSQL for user data and sessions. It uses Anthropic for AI-generated quizzes. The separate [native macOS edition](macos/README.md) is a local-first study app, not a wrapper around the web UI.

## Get the `Sol` development branch

If this is your first checkout:

```sh
git clone --branch Sol https://github.com/nicktheo59/LectureQuest_Nov.git
cd LectureQuest_Nov
```

If you already cloned the repository:

```sh
cd /path/to/LectureQuest_Nov
git status --short
git fetch origin
git switch Sol                         # Git normally sets up tracking on the first switch
# If Git can't infer tracking, use: git switch --track origin/Sol
git pull --ff-only origin Sol
```

Before switching, commit or stash any local work you want to keep. Subsequent updates only need `git switch Sol` and `git pull --ff-only origin Sol`.

## Run the web app on your Mac

1. Install **Node.js 22** (use the latest 22.x patch; `node -v` should start with `v22`). Run `npm ci` and `cp .env.example .env` once from the repo root. Do not overwrite an existing `.env`.
2. Create a **separate development Neon database/branch** and copy the PostgreSQL connection string from its **Connect** dialog into `DATABASE_URL` in `.env`. Use a direct connection when applying the initial schema. The web runtime's current database driver expects Neon; this is not a fully offline web setup.
3. In [Google Auth Platform](https://console.cloud.google.com/auth/clients), configure Branding/Audience and create a **Web application** OAuth client. Add `http://localhost:5000/api/callback` under **Authorized redirect URIs**. Add your Google account as a test user if your project's audience settings require it. Put the client ID and secret in `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`.
4. Run `openssl rand -hex 32` and put its output in `SESSION_SECRET`. Optionally set `ANTHROPIC_API_KEY` to enable AI quizzes. Keep these values out of Git, chat, and screenshots.
5. From the repo root:

   ```sh
   npm run db:push      # review the schema change; use only your dev database here
   npm run dev
   ```

   Open **http://localhost:5000** and select **Sign in with Google**. Use `localhost` as written, not a different hostname. If you change the port, update both `APP_ORIGIN` and Google's redirect URI. Node's dev server runs on your Mac and connects to Neon and Google over the network.

## Host the web app: Render + Neon

Use a **Render Web Service**, not GitHub Pages or a static site; login, data, and quizzes need the Node server. The repo does not provision a paid service or publish automatically.

1. Create a fresh Neon database for staging. Initialize it from this checkout by setting `DATABASE_URL` to its **direct** connection string in your shell or in an untracked `.env`, then run `npm run db:push`. Carefully verify the target database first; do not run this on an existing database without reviewing the diff and backing up its data. Use the Neon pooled connection string for the running service if desired.
2. Create a [Render Web Service](https://render.com/docs/deploy-node-express-app) from this GitHub repo. For staging select branch **`Sol`**. Use the **Node** runtime, the repository root, build command **`npm ci --include=dev && npm run build`**, start command **`npm start`**, and [HTTP health check](https://render.com/docs/health-checks) path **`/api/health`**. This endpoint checks that Express is serving; it doesn't verify DB connectivity. Render supplies `PORT`. Keep auto-deploy off until the staging smoke test passes.
3. In Render's Environment settings set `APP_ORIGIN` to the actual public HTTPS origin (no path), `TRUST_PROXY=1` for Render's single direct reverse proxy, `DATABASE_URL`, `SESSION_SECRET`, and the Google OAuth ID and secret. Set `ANTHROPIC_API_KEY` if AI quizzes are enabled. Use an independent random session secret and preferably a separate Google OAuth client from local development. Set `GOOGLE_ALLOWED_EMAILS` to a comma-separated list of your testers for a private beta; otherwise any eligible Google account can sign up. Omit it only when open sign-up is intentional.
4. In Google, register the exact authorized redirect URI: **your Render HTTPS origin + `/api/callback`**. Start with the Render URL; if you switch to a custom domain, change both the Google URI and `APP_ORIGIN`. See the [Google OAuth redirect requirements](https://developers.google.com/identity/protocols/oauth2/web-server) and [Neon connection guide](https://neon.com/docs/connect/connect-from-any-app).
5. Smoke-test with throwaway data: confirm the homepage and health endpoint load; sign in, upload a small non-sensitive lecture, generate a quiz (if enabled), sign out, and confirm the protected API returns 401. Repeat with a second allowed Google account and verify it cannot see the first account's lectures. Before opening sign-ups, add usage/rate controls around AI calls and review data disclosure for third-party quiz generation.

### Existing Replit accounts

New Google identities are keyed by the stable Google subject, not by email. The app does **not** link or migrate old Replit accounts automatically. If the old database has an account with the same email, sign-in displays an account-migration message instead of granting access. Keep a backup; existing lecture/progress ownership must be migrated separately after verifying both identities.

## Run the native macOS edition

After updating `Sol`, with Xcode installed and its toolchain selected:

```sh
cd macos
swift run LectureQuest
```

See [macos/README.md](macos/README.md) for supported features, version requirements, and local data storage.

## Web checks

```sh
npm run check
npm run build
```

For the basic unauthenticated checks, start the dev server and run `node script/smoke-auth.mjs` in another terminal. A real Google account and a configured test database are needed to verify the full round trip.
