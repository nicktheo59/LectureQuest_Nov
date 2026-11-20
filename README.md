# LectureQuest

Gamified lecture review: upload lecture PDFs/notes, get Claude-generated quizzes, earn XP, keep streaks,
and let spaced repetition schedule what to review next.

This repo contains two apps:

| | Path | Runs on | Auth / storage |
|---|---|---|---|
| **Web app** (React + Express) | `client/`, `server/`, `shared/` | Any Node 20 host (see [DEPLOYMENT.md](DEPLOYMENT.md)) | Sign in with Google · PostgreSQL |
| **Mac app** (SwiftUI) | [`macos/LectureQuestMac`](macos/LectureQuestMac/README.md) | macOS 14+ | Local only · JSON file + Keychain |

---

## Run the web app on your Mac

### 1. One-time setup
```bash
# Tools (Homebrew: https://brew.sh)
brew install node@20 postgresql@16
brew services start postgresql@16
createdb lecturequest

# Code
git clone https://github.com/nicktheo59/LectureQuest_Nov.git
cd LectureQuest_Nov
git checkout Opus            # or whichever branch you want to run
npm install

# Config
cp .env.example .env         # then edit .env (see below)
npm run db:push              # creates the tables
```

Minimum `.env` for local development:
```ini
PORT=3000                    # macOS uses 5000 for AirPlay
APP_URL=http://localhost:3000
DATABASE_URL=postgres://localhost:5432/lecturequest
SESSION_SECRET=<output of: openssl rand -base64 48>
ANTHROPIC_API_KEY=sk-ant-...
# Either real Google credentials…
GOOGLE_CLIENT_ID=...apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=...
# …or skip Google while developing:
DEV_AUTH_BYPASS=true
```

### 2. Start it
```bash
npm run dev
```
Open <http://localhost:3000> → **Continue with Google** (or **Dev login** if `DEV_AUTH_BYPASS=true`).

### Getting the latest changes later
```bash
git checkout Opus
git pull
npm install                  # only needed if package.json changed
npm run db:push              # only needed if shared/schema.ts changed
npm run dev
```

## Sign in with Google

Implemented in [`server/auth.ts`](server/auth.ts) (OpenID Connect with PKCE, state and nonce; sessions in Postgres).

1. Google Cloud Console → **APIs & Services → Credentials → Create OAuth client ID → Web application**
2. Authorised redirect URIs: `http://localhost:3000/api/callback` and `https://<your-domain>/api/callback`
3. Put the client ID/secret in `.env` (locally) or your host's environment variables.

Optional: `ALLOWED_EMAIL_DOMAINS=ucl.ac.uk` restricts sign-in to particular email domains.
Full walkthrough: [DEPLOYMENT.md](DEPLOYMENT.md#2-google-oauth-client).

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Dev server with hot reload (API + client on `PORT`) |
| `npm run build` | Production build → `dist/` |
| `npm start` | Run the production build |
| `npm run db:push` | Sync `shared/schema.ts` to the database |
| `npm run check` | TypeScript type-check |

## Deploy
See **[DEPLOYMENT.md](DEPLOYMENT.md)** — recommended: Render (web service) + Neon (Postgres).

## Mac app
See **[macos/LectureQuestMac/README.md](macos/LectureQuestMac/README.md)** — `cd macos/LectureQuestMac && swift run`.
