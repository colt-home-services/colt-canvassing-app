# Colt Canvassing App (Flutter + Supabase)

Internal canvassing companion app for Colt Home Services.

This project was migrated from an older FlutterFlow app into a clean Flutter
codebase, with Supabase as the backend. It is intended for internal use by
canvassers and managers and is currently deployed as a Flutter Web app.

---

## Live Deployment

- **Platform:** GitHub Pages (Flutter Web)
- **URL:** https://colt-home-services.github.io/colt-canvassing-app/
- **Deployment method:** GitHub Actions (auto-build & deploy on push to `main`)
- **Base path:** `/colt-canvassing-app/`
- **Workflow:**
  - Town → Street → House flows load correctly
  - Search is responsive
  - Auth persists across refresh
  - Manager and Canvasser Dashboard

---

## 1. Overview

### Main Features

- Email + password sign-in / sign-up using Supabase Auth
- CHS access code gate on sign-up (prevents unauthorized accounts)
  - Current code: `chs2025`
  - Location: `lib/features/auth/sign_in_page.dart`
- Role-based access:
  - Canvasser
  - Manager
- Town → Street → House navigation driven from Supabase data
- Per-house detail screen actions:
  - Mark Knocked
  - Mark Answered
  - Mark Signed Up
- Each status update:
  - Updates snapshot fields on the `houses` table
  - Inserts a historical record into `house_events`
- Dashboards:
  - Canvasser dashboard (personal stats and paid time)
  - Manager dashboard (team stats and drilldowns)

### Tech Stack

- Flutter (Dart, web-first)
- Supabase (Postgres, Auth, RLS, RPCs, Views)
- GitHub Pages + GitHub Actions (deployment)

---

## 2. Project Structure

Relevant folders under `lib/`:

- `core/`
  - `theme/chs_colors.dart` – Colt brand colors
  - `utils/address_format.dart` – ZIP formatting and address helpers
- `features/auth/`
  - `sign_in_page.dart` – Sign in / sign up UI + CHS code gate
  - `role_gate_page.dart` – Determines manager vs canvasser routing
- `features/canvassing/`
  - `towns_page.dart` – Loads list of towns (searchable)
  - `streets_page.dart` – Streets within a town
  - `houses_page.dart` – Houses for a street
  - `house_details_page.dart` – Status buttons + event history
- `features/stats/`
  - `canvasser/canvasser_dashboard_page.dart`
  - `manager/manager_dashboard_page.dart`
  - `manager/bucket_drilldown_page.dart`
- `main.dart`
  - Supabase initialization
  - App theme
  - Root `MaterialApp`

**Navigation:** uses `Navigator.push` (no GoRouter, no named routes).

---

## 3. Supabase Setup

### Tables

#### `houses`

- `address` (text, unique identifier)
- `town` (text)
- `street` (text)
- `zip` (text; stored as text to preserve leading zeros)
- Snapshot status fields:
  - `knocked` (bool)
  - `knocked_time` (timestamptz)
  - `knocked_user` (text)
  - `answered` (bool)
  - `answered_time` (timestamptz)
  - `answered_user` (text)
  - `signed_up` (bool)
  - `signed_up_time` (timestamptz)
  - `signed_up_user` (text)

#### `house_events`

- `id` (bigint, primary key)
- `address` (text)
- `created_at` (timestamptz)
- `user_id` (uuid, Supabase auth user)
- `user_email` (text)
- `event_type` (text: `knocked`, `answered`, `signed_up`)
- `notes` (text, nullable)

#### `profiles`

- `user_id` (uuid)
- `role` (text: `canvasser` or `manager`)

---

### Views (Used by Dashboards)

- `v_payroll_daily`
- `v_performance_daily`
- `v_manager_daily_summary`

Business logic for payroll and metrics lives in SQL views to keep Flutter UI simple.

---

### RPCs in Use

- `get_unique_towns`
  - Used by Towns page
  - Loads all towns once after login (client-side search/filtering)
- `get_houses_for_street`
  - Used by Houses page
  - Loads houses for selected street

---

### Security (RLS)

- Row Level Security enabled on all tables
- Access restricted to authenticated users
- Role-based behavior enforced in the UI via RoleGate

---

## 4. Authentication and Role Handling

### Sign-Up Flow

- User signs up with email + password
- Must enter valid CHS access code
- Supabase account is created
- A matching row must exist in `profiles`

### RoleGate

Role routing is handled by:

- `lib/features/auth/role_gate_page.dart`

Behavior:
- Reads `profiles.role` for the logged-in user
- Routes user to:
  - `CanvasserDashboardPage` if role = `canvasser`
  - `ManagerDashboardPage` if role = `manager`

RoleGate is the single source of truth for role routing.

---

## 5. Dashboards and Metrics

### Canvasser Dashboard

Shows personal stats over a selected date range:

- Paid Time (hours)
- Doors Knocked
- People Answered
- Sign-ups
- Answer Rate
- Conversion Rate

**Metric definitions**

- Answer Rate = `answers / knocks`
- Conversion Rate = `sign-ups / answers`
- Paid Time = `valid 15-minute buckets × 0.25`

Percentages are computed from summed totals (not averaged).

---

### Manager Dashboard

Shows team-wide daily summaries:

- Paid Time
- Valid 15-minute buckets
- Doors knocked
- Answer and conversion rates
- Knocks per paid hour

Clicking a row opens a bucket-level drilldown for auditing payroll logic.

---

## 6. Geotagging (Current Implementation)

Geotagging is implemented in a non-blocking, observational manner.

- Houses are pre-mapped to latitude and longitude using Python script `geocode_houses.py`
- Coordinates are stored in the `houses` table
- At the time of a knock:
  - the app captures the canvasser GPS location
  - computes distance between canvasser and house (Haversine)
  - displays/logs the distance difference

Geotagging currently does **not**:
- block knock events
- enforce distance thresholds
- apply penalties

---

## 7. Running the App Locally

### Prerequisites

- Flutter SDK installed
- Supabase project configured
- Supabase URL and anon key available

### Configuration

Set Supabase credentials in `main.dart`:

```dart
await Supabase.initialize(
  url: 'https://<project>.supabase.co',
  anonKey: '<public-anon-key>',
);
Run
bash
Copy code
flutter pub get
flutter run -d chrome

8. Deployment (Flutter Web)
Hosted on GitHub Pages

Built via GitHub Actions on push to main

build/ directory is gitignored

No build artifacts committed

Live URL: https://colt-home-services.github.io/colt-canvassing-app/

9. Operational Guide (Managers & Future Interns)
Sign-Up Access Code (CHS Code Gate)
Current code: chs2025

Update in: lib/features/auth/sign_in_page.dart

Changing a User Role
Run in Supabase SQL Editor:

sql
Copy code
update profiles
set role = 'manager'
where user_id = '<USER_UUID>';
Valid roles:

canvasser

manager

Password Reset (Forgot Password) — Supabase URL Settings
Supabase Dashboard → Authentication → URL Configuration

Set:

Site URL

arduino
Copy code
https://colt-home-services.github.io/colt-canvassing-app/
Add under Redirect URLs

arduino
Copy code
https://colt-home-services.github.io/colt-canvassing-app/
(Optional for local dev)

arduino
Copy code
http://localhost:<PORT>/
If Redirect URLs are missing, reset links can drop recovery tokens and appear to “hang”.

Changing Passwords (Manual/Admin)
If forgot password is disabled in the UI, an admin can:

Supabase Dashboard → Authentication → Users → send reset password email

10. Known Issues and Risks
Rare initial town load timeout (retry resolves it)

Streets/houses are not paginated (scalability risk with very large datasets)

Possible divergence between house_events history and houses snapshot fields

11. Future Work
Enforced geotagging rules

Pagination for houses

Exportable reports

Mobile (iOS/Android) builds

Offline-first support

