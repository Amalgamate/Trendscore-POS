# Super-admin bootstrap

The provisioning CLI can create the same super-admin identity inside each newly provisioned shop database. The account has owner access within that shop. Shop databases stay isolated, so this is a separately stored account in each installation, not a central cross-shop session.

For the live `www.gutagala.trendscore.co.ke` deployment, configure both values as secrets in the GitHub Actions `production` environment:

- `POS_SUPER_ADMIN_PHONE`: the administrator's Kenyan phone number.
- `POS_SUPER_ADMIN_PIN`: a 4–6 digit initial PIN.

Keep the PIN in a secret manager or protected environment setting. Do not add it to the repository, compose files, or shell scripts. The deployment transfers the credentials in a short-lived protected file, deletes it after seeding, and does not pass the PIN in a logged command. The provisioning CLI also reads these names from its environment and redacts the PIN from printed output. If either variable is set without the other, provisioning stops with a configuration error. If neither is set, CLI provisioning continues without creating a platform super-admin.

The initial PIN is hashed in the shop database. The account must replace it on first sign-in; the API blocks other authenticated routes until the change succeeds. Provisioning is safe to resume: rerunning it will not reset the PIN after the account has been created.

The live deployment provisions its shop database and account together. Other new CLI-provisioned installations get the account when these variables are configured. Existing shops need the database migration and one-time super-admin creation script run against each shop database before those shops gain the account.
