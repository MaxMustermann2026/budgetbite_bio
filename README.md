# BudgetBite Bio

Budget-aware bio meal planning app built with Flutter & Supabase.

## MVP Features
- Weekly meal planning (recipes + servings scaling)
- Shopping list with prices (BIO / KONV)
- Budget overview & bio share (%)
- Pantry (local) with leftovers
- Week close flow (consume pantry + add leftovers)
- Sorting (expensive first / A–Z / bio first)
- Copy shopping list to clipboard

## Tech Stack
- Flutter (Dart)
- Supabase (Postgres)
- SharedPreferences (local pantry & UI state)

## Supabase setup (MVP)

### 1) Create project + get keys
- Create a Supabase project
- Copy:
  - Project URL
  - anon public key

### 2) Add Flutter env/config
You need these values in your Flutter app:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

(Implementation depends on how you load envs: `.env`, `--dart-define`, etc.)

### 3) Database tables (minimal)
This MVP uses these tables in schema `public`:

**ingredients**
- `id uuid` (PK)
- `name text`
- `unit text` (e.g. `g`, `ml`, `pcs`)
- `unit_quantity numeric` (pack size)
- `bio_available boolean`
- `price_conv_cents int4` (fallback)
- `price_bio_cents int4` (fallback)
- `created_at timestamptz`

**ingredient_prices**
- `id uuid` (PK)
- `ingredient_id uuid` (FK -> ingredients.id)
- `country text` (e.g. `DE`)
- `store text` (nullable)
- `price_conv_cents int4`
- `price_bio_cents int4` (nullable)
- `unit_quantity numeric`
- `unit text`
- `created_at timestamptz`

**recipes**
- `id uuid` (PK)
- `title text`
- `servings int4`
- `instructions text`
- `ingredients jsonb` (contains `ingredient_id`, `amount`, `use_bio`)
- `diet text`
- `meal_type text`
- `prep_level text`
- `created_at timestamptz`

**weekly_plan**
- `id uuid` (PK)
- `week_start date`
- `settings jsonb`
- `days jsonb`
- `created_at timestamptz`

Optional:
- `ingredient_prices_view` (view for convenience)

### 4) RLS (MVP note)
For MVP/dev you can keep RLS disabled.  
For production: enable RLS and add proper policies (read/write only for authenticated users).

## Roadmap (next)
- Enable Auth (email/password) + user profiles
- Enable RLS + policies per user
- Multi-country pricing (country selector instead of fixed `DE`)
- Store-specific prices (choose preferred store)
- Pantry moved from local (SharedPreferences) to Supabase per user
- Better recipe ingredient structure (typed table instead of jsonb)
- Release builds (Android/iOS) + basic CI

## Run locally
```bash
flutter pub get
flutter run