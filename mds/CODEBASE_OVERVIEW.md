# Census Frontend - Complete Codebase Overview

## What Is This Project?

**Census Frontend** (`tha/census`) is a **back-office admin panel** for managing public transport cards and customers, built for cities in Kazakhstan (primarily Almaty/Aqtau). It's a **Laravel 5.5** application that acts as a **Backend-For-Frontend (BFF)** -- it does NOT store business data locally. Instead, it communicates with external microservices via HTTP APIs.

**Think of it as:** A web dashboard where operators manage customer accounts, transport cards, concessions (discounts), printing queues, and reports. All real data lives in external APIs; this app just provides the UI and proxies requests.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Laravel 5.5 (PHP >= 7.0) |
| CSS Framework | Semantic UI (via Gulp build) |
| Auth | JWT cookies (`tymon/jwt-auth` 0.5.x) |
| HTTP Client | GuzzleHttp 6.x (for API calls) |
| PDF Generation | DOMPDF 0.8 + TCPDF 6.2 |
| Barcodes | `picqer/php-barcode-generator` |
| Caching | Redis (`predis/predis`) |
| CI/CD | GitLab CI |
| Deployment | Docker Compose (Nginx + PHP-FPM) + rsync to 3 production hosts |
| Frontend Build | Gulp + npm (Semantic UI theming) |
| Languages | Russian (primary), Kazakh, English |

---

## Directory Structure

```
├── app/
│   ├── ApiClient/          # Modular API client (Admin, Api, Billing, Pub, Report, newApi)
│   ├── Census/             # Core library: main API client, helpers, city service, PDF, auth
│   │   ├── API.php         # ★ THE main API client (~1800 lines) - all external API calls
│   │   ├── census.functions.php  # Global helper functions
│   │   ├── City.php        # City service (city resolution, institution mapping)
│   │   ├── CPDF.php        # PDF generation utility
│   │   ├── FrontendAuthUser.php  # Auth user wrapper
│   │   ├── Facades/AuthUser.php  # AuthUser facade
│   │   └── deployment/     # Deployment scripts
│   ├── Console/            # No custom artisan commands
│   ├── Exceptions/         # Custom exception handler
│   ├── Http/
│   │   ├── Controllers/    # 26+ controllers (see breakdown below)
│   │   │   ├── Ajax/       # AJAX controllers (Customer, Claim, Report, System, Scheduler)
│   │   │   ├── API/        # External API endpoints (login, user, regform)
│   │   │   ├── Customer/   # Moderation + Ticket pages
│   │   │   └── PSS/        # Public Self-Service (IP-restricted card lookup)
│   │   ├── Middleware/     # Custom middleware (auth, guest, PSS IP check, city, task)
│   │   ├── Requests/       # Form requests (RegistrationRequest, LoginRequest)
│   │   └── View/Composers/ # View composers for city data
│   ├── Policies/           # 5 policies: Info, Card, Concession, Document, Number
│   ├── Providers/          # 9 service providers (API singletons, city, auth, facades)
│   ├── Traits/             # PolicyTrait (city/institution/permission helpers)
│   ├── City.php            # City constants (INSTITUTION_ALL=0, CITY_KGD=2)
│   ├── Task.php            # Task formatting (card blocking scheduler)
│   └── User.php            # Custom User model (NOT Authenticatable - API-populated)
├── config/
│   ├── cardoperations.php  # Card status codes (Russian labels)
│   ├── institutions.php    # Institution type IDs
│   ├── owners.php          # Card owner/type definitions
│   ├── tokens.php          # API tokens
│   ├── report.php          # Report service URLs
│   └── jwt.php             # JWT config (60min TTL)
├── database/
│   ├── migrations/         # Only 2 default Laravel tables (users, password_resets)
│   └── seeds/              # Empty seeder
├── public/                 # Web root (index.php, static assets, images, fonts)
├── resources/
│   ├── assets/             # JS (app.js, bootstrap.js) + SASS
│   ├── lang/               # 3 languages: en/, ru/, kk/
│   └── views/              # Blade templates (29 directories)
├── routes/
│   ├── web.php             # ★ Main routes (~900 lines) - customer, cards, reports, AJAX
│   ├── guest.php           # Login/password reset (unauthenticated)
│   ├── pss.php             # Public Self-Service routes (IP-restricted)
│   ├── api.php             # REST API v1 (login, user, regform)
│   └── console.php         # Only default `inspire` command
├── static/                 # Frontend build system (Gulp + Semantic UI)
│   ├── gulpfile.js         # Gulp tasks
│   ├── semantic/           # Semantic UI source
│   └── application/        # App-specific frontend code
├── tests/                  # Only 1 example test (minimal testing)
├── docker-compose.yml      # Docker: laravel (PHP-FPM) + nginx
├── .gitlab-ci.yml          # CI/CD pipeline
└── composer.json           # PHP dependencies
```

---

## How Authentication Works

This is the most important thing to understand first:

1. **User visits `/login`** → `LoginController@getLoginForm` shows the form
2. **User submits credentials** → `LoginController@postLoginForm` calls external API (`POST /user/login`)
3. **API returns a JWT token** → Stored in encrypted `census` cookie
4. **Every subsequent request** → `UserAuthCheck` middleware:
   - Decrypts the `census` cookie to get the token
   - Calls external API `GET /user/ping` with the token
   - API returns user data (roles, permissions, institutions, card types)
   - Populates `User` model and `AuthUser` facade in memory
5. **Authorization** → Custom RBAC via `User::can()` method + Laravel Gates (16 rules) + 5 Policies

**Key insight:** The local `users` table is essentially unused. The `User` model extends `Model` (not `Authenticatable`) and is populated entirely from API responses.

---

## Core Architecture Patterns

### 1. API-Driven (BFF Pattern)
All business data (customers, cards, documents, concessions, institutions) lives in external microservices. The Laravel app:
- Receives web requests from operators
- Calls external APIs via GuzzleHttp
- Renders Blade templates with the data
- Returns HTML responses

### 2. Three API Client Layers
| Client | Location | Purpose |
|--------|----------|---------|
| `Census\API` | `app/Census/API.php` | ★ Main legacy client (~1800 lines). Handles customers, cards, documents, images, billing, funds, concessions. Heavy caching. |
| `ApiClient\Client` | `app/ApiClient/Client.php` | Modular client with dynamic modules: Admin, Api, Billing, Pub, Report, newApi |
| Reporter API | `reporter/api-client` (package) | Separate private package for reporting |

### 3. Controller Hierarchy
```
Controller (base)
├── LoggedinController (adds API client initialization with user token)
│   ├── CustomerController
│   ├── RegistrationController
│   ├── ReportController
│   ├── All Ajax\* controllers
│   └── Most other controllers
└── HomeController, LoginController, AuthHistoryController (no user token needed)
```

### 4. Authorization Flow
```
User::can('permission_name')
  → checks $customRules array (16 specific permissions)
  → delegates to Gate::forUser($this)->allows($permission, $data)
    → routes to appropriate Policy class
      → uses PolicyTrait helpers (city/institution checks)
```

---

## Route Map (Simplified)

### Public Routes (`guest` middleware)
| URL | Purpose |
|-----|---------|
| `GET /` | Redirect to login |
| `GET /login` | Login form |
| `POST /login` | Process login |
| `PUT /reset-password` | Password reset |

### Authenticated Routes (`auth` middleware)
| URL Pattern | Purpose |
|-------------|---------|
| `GET /` | Dashboard (role-based redirect) |
| `GET /logout` | Logout |
| `GET /customer/list` | Customer list (paginated) |
| `GET /customer/new` | Registration form |
| `GET /customer/{id}` | Customer detail view |
| `GET /customer/{id}/cards` | Customer cards tab |
| `GET /customer/{id}/documents` | Customer documents tab |
| `GET /customer/{id}/concessions` | Customer concessions tab |
| `GET /customer/{id}/funds` | Customer funds tab |
| `GET /customer/{id}/comments` | Customer comments tab |
| `GET /customer/{id}/history` | Customer change history |
| `GET /customer/moderation` | Pre-moderation queue |
| `GET /search/results` | Search (by IIN, name, card PAN, phone) |
| `GET /report/printed/*` | Various printed card reports |
| `GET /report/concessions` | Concession statistics |
| `GET /scheduler/blockCards` | Card blocking scheduler |
| `GET /system/institutions` | Manage institutions |
| `GET /system/institutionGroups` | Manage institution groups |

### AJAX Routes (`/ajax/*` prefix, `ajax` middleware)
| URL Pattern | Purpose |
|-------------|---------|
| `POST /ajax/customer/save` | Register new customer |
| `POST /ajax/customer/{id}/card/add/{pan}` | Add card to customer |
| `POST /ajax/customer/{id}/card/setStatus` | Block/unblock card |
| `POST /ajax/customer/{id}/comment/add` | Add comment |
| `POST /ajax/customer/{id}/update` | Update customer field |
| `POST /ajax/customer/{id}/moderation/approve` | Approve moderation |
| `POST /ajax/report/printed/*` | AJAX report data |
| `POST /ajax/scheduler` | Create scheduled task |
| `DELETE /ajax/scheduler/{id}` | Cancel scheduled task |

### PSS Routes (`/pss/*`, IP-restricted)
| URL | Purpose |
|-----|---------|
| `GET /pss` | Public Self-Service index |
| `POST /pss/ajax/searchxfer` | Search for card transfer |
| `POST /pss/ajax/confirmxfer` | Confirm card transfer |

---

## Key Files to Know

| File | Why It Matters |
|------|---------------|
| `app/Census/API.php` | ★ The heart of the app. Every API call goes through here. ~1800 lines. |
| `app/Census/census.functions.php` | Global helpers: `jq()`, `combinedLog()`, `get_cities()`, `is_concession_active()`, etc. |
| `app/User.php` | Custom User model with RBAC logic. Not a standard Laravel user. |
| `app/Http/Middleware/UserAuthCheck.php` | Auth middleware - validates JWT cookie against API on every request. |
| `routes/web.php` | ★ All routes defined here (~900 lines). |
| `app/Http/Controllers/CustomerController.php` | Main customer CRUD controller. |
| `app/Http/Controllers/Ajax/Customer/CardController.php` | Card operations (add, block, topup, history, etc.). |
| `app/Providers/AuthServiceProvider.php` | 16 Gate definitions for authorization. |
| `app/Traits/PolicyTrait.php` | Reusable authorization helpers (city/institution checks). |
| `config/owners.php` | Card type definitions (ETK Online, student, social, veteran). |
| `config/cardoperations.php` | Card status codes and Russian labels. |

---

## Frontend Build System

The frontend uses **Gulp** with **Semantic UI**:

```bash
# Install (first time)
cd static/
npm install
cd node_modules/semantic-ui && gulp install && cd ../..

# Build for development
gulp --app="frontend"

# Build for production
gulp --app="frontend" --env=production

# Watch for changes
gulp --app="frontend" watch
```

Output goes to `public/static/`. The `static/` directory contains Semantic UI source customization and app-specific frontend code.

---

## CI/CD Pipeline

**Branches:**
- `development/master` → deploys to dev server
- `release/master` → deploys to production (manual trigger)

**Pipeline stages:**
1. **Building:**
   - Generate `.env` from CI/CD variables (`$SECRETS_PROD`, `$SECRETS_STAGE`, `$SECRETS_BUILD`)
   - `composer install` (with SSH key for private packages)
   - Build static assets (npm + Gulp)
   - Generate Nginx config (for web builds)
2. **Deploy:**
   - **Dev:** rsync to remote dev server
   - **Web build:** rsync + Docker Compose up + Nginx reload
   - **Prod:** rsync to 3 production hosts + `php artisan cache:clear` (manual trigger)

---

## Common Gotchas for New Developers

1. **CSRF is disabled** - The `VerifyCsrfToken` middleware is commented out in `app/Http/Kernel.php`. All POST requests work without CSRF tokens.

2. **No route model binding** - Customer IDs are raw integers passed to controllers. You call the API manually to fetch data.

3. **The `User` model is weird** - It extends `Model` (not `Authenticatable`), has no `$fillable`, and is populated from API responses. Don't treat it like a normal Eloquent model.

4. **Three API clients** - There are 3 different ways to call APIs. The main one is `Census\API`, but there's also `ApiClient\Client` and the Reporter client. Check existing code to see which is used for what.

5. **Heavy caching** - The `Census\API` class caches API responses extensively (institutions, customers, documents, etc.). If data seems stale, check the cache.

6. **Multi-language** - Views use `{{ trans('key') }}` with locale files in `resources/lang/{en,ru,kk}/`. Russian is the default.

7. **No tests** - There's only 1 example test. Be very careful with changes.

8. **Authorization is complex** - Permissions are checked via `\AuthUser::can('permission_name')` calls in controllers. There are 16 Gate rules and 5 Policy classes. Always check what permissions apply before adding features.

9. **External API dependency** - The app won't work at all without the external Census API running. For local development, you need API access configured in `.env`.

10. **Deprecated routes** - Several routes are marked `(deprecated)` in comments. Don't add new code to deprecated endpoints.

---

## Environment Variables (Required)

No `.env.example` exists. These are inferred from the code:

| Variable | Purpose |
|----------|---------|
| `APP_ENV` | Environment (production, development) |
| `APP_DEBUG` | Debug mode |
| `APP_URL` | Application URL |
| `APP_KEY` | Laravel encryption key |
| `APP_TOKEN` | Application bearer token for API auth |
| `API_BACKEND` | Main backend API URL |
| `BASE_API_DOMAIN` | Base API domain for modular client |
| `CDN_BACKEND` | CDN URL for images |
| `BILLING_BACKEND` | Billing API URL |
| `BILLING_TOKEN` | Billing API token |
| `REPORTER_URL` | Reporter API URL |
| `JWT_SECRET` | JWT signing secret |
| `FIRST_COUNTRY_ID` | Default country (26 = Kazakhstan) |

---

## Where to Start When Working on a Feature

1. **Find the route** in `routes/web.php` (or `guest.php`, `pss.php`)
2. **Find the controller** method it maps to
3. **Check what API calls** the controller makes (usually via `Census\API` or `ApiClient\Client`)
4. **Check authorization** - what permissions/gates are checked?
5. **Find the Blade view** in `resources/views/`
6. **Check translations** in `resources/lang/{en,ru,kk}/`
