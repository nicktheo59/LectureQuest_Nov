# Deploying LectureQuest

LectureQuest is a single Node service: Express serves the JSON API **and** the built React app
from one port. It needs three things to run in production:

| Need | What we use | Why |
|---|---|---|
| A long-running Node 20 server | **Render** Web Service (recommended), or Railway / Fly.io via the `Dockerfile` | Quiz generation calls Claude for 10–30 s and uploads go up to 50 MB — a normal server handles this; serverless functions (e.g. Vercel) would time out and need a rewrite |
| PostgreSQL | **Neon** (serverless Postgres, free tier) | The app already ships the Neon driver; `server/db.ts` auto-detects Neon vs. ordinary Postgres |
| Google OAuth client | Google Cloud Console | "Sign in with Google" (see `server/auth.ts`) |

Rough cost: Neon free + Render Starter ($7/mo, always-on). Render's free plan also works but sleeps after
15 minutes idle (first request then takes ~30–60 s).

---

## 1. Database — Neon

1. Create a project at <https://neon.tech> (pick the region nearest your users, e.g. `eu-west-2` London).
2. Copy the **pooled** connection string — it looks like
   `postgresql://user:pass@ep-xxxx-pooler.eu-west-2.aws.neon.tech/neondb?sslmode=require`.
3. Create the tables once, from your machine:

   ```bash
   DATABASE_URL='postgresql://…neon.tech/neondb?sslmode=require' npm run db:push
   ```

   Re-run this whenever `shared/schema.ts` changes.

> Migrating from Replit? Replit's built-in Postgres is a Neon database, so you can point `DATABASE_URL`
> at it directly or `pg_dump`/`pg_restore` into a new Neon project. Existing users keep their data:
> on first Google sign-in, an account with the same verified email is reused (see `upsertGoogleUser`).

## 2. Google OAuth client

1. <https://console.cloud.google.com/> → create/select a project.
2. **APIs & Services → OAuth consent screen**: User type *External*, app name "LectureQuest",
   support email, scopes `openid`, `email`, `profile`. While in *Testing* mode only listed test users
   can sign in — click **Publish app** when you're ready for everyone (no verification is needed for
   these basic scopes).
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**
   - Application type: **Web application**
   - Authorised JavaScript origins: `http://localhost:3000`, `https://<your-app>.onrender.com`
   - Authorised redirect URIs (must match exactly):
     - `http://localhost:3000/api/callback`
     - `https://<your-app>.onrender.com/api/callback`
     - (plus `https://your-custom-domain/api/callback` if you add one)
4. Copy the **Client ID** and **Client secret**.

## 3. Web service — Render

**Option A — Blueprint (one click):** Render Dashboard → **New → Blueprint** → pick this repo.
`render.yaml` defines the service; Render asks for the secret values below. (It deploys `main`;
change `branch:` in `render.yaml` or in the dashboard to preview another branch, e.g. `Opus`.)

**Option B — manual:** New → Web Service → this repo, then:

| Setting | Value |
|---|---|
| Runtime | Node |
| Build command | `npm ci --include=dev && npm run build` |
| Start command | `npm start` |
| Health check path | `/api/health` |

Environment variables:

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `NODE_VERSION` | `20` |
| `DATABASE_URL` | Neon connection string |
| `SESSION_SECRET` | long random string (`openssl rand -base64 48`) |
| `APP_URL` | `https://<your-app>.onrender.com` (no trailing slash) |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | from step 2 |
| `ANTHROPIC_API_KEY` | from console.anthropic.com |
| `ALLOWED_EMAIL_DOMAINS` | *(optional)* e.g. `ucl.ac.uk` to restrict sign-ups |

Render sets `PORT` itself. After the first deploy, visit the URL → **Continue with Google**.

### Custom domain
Render → Settings → Custom Domains → add `lecturequest.yourdomain.com`, create the CNAME it shows,
then update `APP_URL` and add the new `/api/callback` URI in Google Cloud.

## Alternatives

- **Railway / Fly.io / any Docker host** — use the included `Dockerfile` (listens on `8080`), set the
  same env vars. Fly: `fly launch` → `fly secrets set KEY=value …` → `fly deploy`.
- **Keep it on Replit** — still works: add the Google env vars as Replit Secrets and set
  `APP_URL` to your `.replit.app` domain. Replit Auth is no longer used.

## Production checklist

- [ ] `npm run db:push` against the production database
- [ ] Google consent screen published (or your testers added)
- [ ] Redirect URI in Google exactly equals `APP_URL + /api/callback`
- [ ] `SESSION_SECRET` set to a strong random value (sessions are stored in the `sessions` table)
- [ ] `DEV_AUTH_BYPASS` **not** set (it's ignored when `NODE_ENV=production` anyway)
