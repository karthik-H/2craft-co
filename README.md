# Craft & Co.

Artisan marketplace built from the CodeValid structured requirements spec.

## Stack

- **Backend:** Node.js, Express, PostgreSQL, Prisma, JWT, Stripe, Resend, node-cron
- **Frontend:** React + Vite, TailwindCSS, React Query

## Quick start

```bash
# Start PostgreSQL
docker compose up -d

# Backend
cd backend
npm install
npm run db:setup
npm run dev

# Frontend (new terminal)
cd frontend
npm install
npm run dev
```

- API: http://localhost:4000
- App: http://localhost:5173

## Seed accounts

| Email | Password | Role | Status |
|-------|----------|------|--------|
| admin@craftco.com | Admin1234! | admin | active |
| seller@craftco.com | Seller1234! | seller | active |
| pending@craftco.com | Pending1234! | seller | pending |
| buyer@craftco.com | Buyer1234! | buyer | active |

12 products seeded across jewelry, ceramics, textiles (2 sold out).

## Business rules implemented

- **BR-01** Pending sellers cannot create products
- **BR-02** Zero-stock products remain visible as sold out (greyed out)
- **BR-03** Suspending a seller sets `visible=false` on all listings
- **BR-04** Admin API returns all products including hidden ones
- **BR-05** 10% platform fee on orders
- **BR-06** Weekly payout cron (Mondays 9am) + manual admin trigger
- **BR-07** Seller email notification on paid order (Resend or console demo)
- **BR-08** Reviews only when order status is `delivered`
