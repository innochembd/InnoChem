# Inno Chem Bangladesh ERP — Deployment Guide

This covers deploying the ERP to **Supabase** (database) + **GitHub** (source control) +
**Vercel** (hosting). Read the "Before you deploy" section first — it affects whether
the app will actually work once it's live.

---

## Before you deploy — 2 things that matter

### 1. The app's storage layer needs to be rewritten

The current build saves and loads all data through `window.storage`, an API that
**only exists inside Claude.ai**. Deployed on Vercel as a plain static file, every
`window.storage.get(...)` / `.set(...)` call will fail silently — the app will load,
but nothing will save, and existing data won't appear.

To go live, every one of those calls needs to be replaced with a call to the
[Supabase JS client](https://supabase.com/docs/reference/javascript/introduction)
(`supabase.from('companies').select()`, `.insert()`, `.update()`, `.delete()`, etc.),
matching the tables in `schema.sql`. This is real code work — roughly 40–50 call
sites across companies, products, purchases, sales, sale items, payments, users,
and the business profile.

**I can do this rewrite for you** — it's a natural "Step 14" in the same style as
the rest of the build. Just say so and I'll go through it module by module like before.
This README and schema are ready either way.

### 2. Passwords and permissions currently live in the browser only

Today, login checks and view/edit permissions are enforced entirely in JavaScript
running in the user's browser. That's fine inside Claude.ai's sandboxed artifact,
but on the open web:

- Anyone can open dev tools, read the Supabase **anon key** out of your deployed
  JS bundle (it's public by design — that's how Supabase's client-side model works),
  and call the database directly, bypassing your login screen and permission checks
  entirely.
- The current app also stores passwords in plain text.

`schema.sql` enables **Row Level Security (RLS)** and locks every table to
`auth.role() = 'authenticated'`, and locks `app_users` out of direct client access
entirely. That means the schema is safe by default — but it only works end-to-end
once the app actually uses **Supabase Auth** for login (not the current custom
username/password check). Options, roughly in order of effort:

| Option | Effort | Result |
|---|---|---|
| A. Migrate login to Supabase Auth (email/password) | Medium | Proper security, closest to current UX |
| B. Add a small Vercel serverless function that holds the service-role key and checks permissions server-side before touching the DB | Medium-high | Keeps custom username/password login, real security |
| C. Deploy as-is with RLS locked down, accept it's an internal/trusted-network tool only | Low | Fast, but don't expose the URL publicly |

If you want, tell me which option and I'll build it as part of the same rewrite.

---

## Part 1 — Supabase setup

1. Go to [supabase.com](https://supabase.com) → **New project**. Pick a name, a
   database password (save it somewhere safe), and a region close to Bangladesh
   (Singapore is usually the closest option).
2. Once the project is ready, open **SQL Editor** → **New query**, paste the
   entire contents of `schema.sql`, and click **Run**. This creates all tables,
   indexes, and security policies in one go.
3. Go to **Project Settings → API**. You'll need two values later:
   - **Project URL** (e.g. `https://xxxxx.supabase.co`)
   - **anon public key** (safe to expose in frontend code — that's what it's for)
   - *Do not* put the **service_role key** in any frontend code — it bypasses RLS
     entirely and must only ever run on a server.
4. If you're going with Option A above: go to **Authentication → Providers** and
   make sure **Email** sign-in is enabled, then create your first admin user
   under **Authentication → Users → Add user**.

---

## Part 2 — GitHub setup

1. Create a new repository (e.g. `innochem-erp`), private is recommended since
   this handles real business data.
2. Suggested structure once the Supabase rewrite is done:
   ```
   innochem-erp/
   ├── index.html          ← the ERP app itself
   ├── schema.sql          ← keep for reference / re-running on a fresh project
   ├── README.md
   └── .env.example        ← documents which env vars are needed, no real values
   ```
3. **Never commit real Supabase keys to the repo.** Use environment variables
   (see Vercel section) even though the anon key is technically safe to expose —
   it's still better practice to keep it out of git history.
4. Push:
   ```bash
   git init
   git add .
   git commit -m "Initial commit — InnoChem ERP"
   git branch -M main
   git remote add origin https://github.com/<your-username>/innochem-erp.git
   git push -u origin main
   ```

---

## Part 3 — Vercel setup

1. Go to [vercel.com](https://vercel.com) → **Add New → Project** → import the
   GitHub repo you just created.
2. Since this is a static HTML file (no build step), set:
   - **Framework Preset:** Other
   - **Build Command:** (leave empty)
   - **Output Directory:** `.` (root)
3. Add environment variables under **Settings → Environment Variables**:
   | Name | Value |
   |---|---|
   | `SUPABASE_URL` | your Project URL from Part 1 |
   | `SUPABASE_ANON_KEY` | your anon public key from Part 1 |

   Note: a single static `index.html` can't read Vercel env vars at runtime the
   way a framework app can — during the Supabase rewrite, I'll either inject
   these at build time via a tiny build script, or use a lightweight framework
   (e.g. Vite) so `import.meta.env` works normally. Worth deciding this together
   before the rewrite starts.
4. Click **Deploy**. Vercel gives you a `*.vercel.app` URL immediately; you can
   attach a custom domain afterward under **Settings → Domains**.

---

## Part 4 — After deploying

- Log in and add a couple of real companies/products to confirm data is actually
  persisting in Supabase (check **Table Editor** in the Supabase dashboard —
  you should see rows appear as you use the app).
- Set up a recurring backup habit: Supabase → **Database → Backups** has
  automatic daily backups on paid plans; on the free tier, use the app's own
  **Download full backup (JSON)** button regularly as a manual safety net.
- If multiple people will use this, decide on Option A/B/C from above before
  sharing the URL outside your immediate team.

---

## Schema reference

See `schema.sql` for full detail. Summary of tables:

| Table | Purpose |
|---|---|
| `business_profile` | Single row — your business info shown on receipts |
| `app_users` | Staff logins + per-page permissions (service-role access only) |
| `companies` | Suppliers / buyers / both |
| `products` | Chemical catalogue |
| `purchases` | One row per purchase line (supplier-facing) |
| `sales` | One row per invoice header |
| `sale_items` | Line items belonging to a sale — this is what makes multi-product invoices work |
| `payments` | Money received/paid, optionally linked to one sale or purchase |
| `inventory_live` | A view, not a table — computes current stock live from the tables above |

Indexes are placed on every foreign key, every date column (for date-range
reports), and on `due` columns (for quickly finding outstanding balances) —
these are the columns the app's Dashboard, Tally Book, and Reports pages filter
and sort by most often.

---

## Questions to decide before I do the code rewrite

1. Which security option (A/B/C above)?
2. Keep it a single static HTML file, or move to a small framework (Vite/plain
   JS) so environment variables and Supabase Auth work more cleanly?
3. Do you want the existing local data (if any) migrated into Supabase, or
   starting fresh?

Let me know and I'll build it step by step, same as before.
