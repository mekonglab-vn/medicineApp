# server-node — MedicineApp API

Node.js + Express backend cho MedicineApp.

## Quick Start

```bash
# 1. Start PostgreSQL
docker compose up -d

# 2. Install dependencies
cd server-node && npm install

# 3. Setup environment
cp .env.example .env

# 4. Run migrations
npm run migrate

# 5. Start server
npm run dev
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Server + DB + Python status |
| POST | `/api/auth/register` | Register |
| POST | `/api/auth/login` | Login → JWT |
| POST | `/api/auth/refresh` | Refresh token |
| GET | `/api/drugs/search?q=` | Search drugs |
| POST | `/api/scan` | Scan prescription image |
| GET | `/api/plans` | List medication plans |

## Tech Stack

- **Runtime:** Node.js 20 (ES modules)
- **Framework:** Express 4
- **Database:** PostgreSQL 16 (Docker)
- **Auth:** JWT + bcrypt
- **Validation:** Zod
- **Logging:** Winston
- **Security:** Helmet, CORS, rate-limit
