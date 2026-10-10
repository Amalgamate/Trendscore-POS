# Local shop API

The POS uses the `retailos_test` database in the active `retailos_test`
container. Its existing anonymous Docker volume is published to
`127.0.0.1:55432`, and the container uses Docker's `unless-stopped` restart
policy. This is the only active local POS database.

To start the selected database after it has been manually stopped:

```powershell
docker start retailos_test
```

The former `retailos_shop_postgres` database and its named volume were removed
after creating a verified local backup. Do not start `docker-compose.local.yml`
unless intentionally creating a new, separate database.

Keep shop database connection details in the ignored `apps/shop-api/.env.local`
file. Do not commit that file or put credentials in compose configuration.
Start the API from the repository root with:

```powershell
npm run dev:local --workspace shop-api
```

The POS preview on port 8081 proxies `/api` to the API on port 4001. The local
API environment must therefore use `PORT=4001` and point both Prisma URLs at
`localhost:55432/retailos_test`.

Migrations `0004_supplier_archive` and `0005_customer_credit_workspace` have
been applied to the selected database. Its older migration history still uses
legacy names for migrations represented differently in the local files. Check
`prisma migrate status` and reconcile any future history discrepancy before
deploying additional migrations; do not run migration deployment blindly.
