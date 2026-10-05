# ADR-0002: M-Pesa is asynchronous, and TIMEOUT is not failure

- **Status:** Accepted
- **Date:** 2026-10-05

## Context

The original product spec modelled M-Pesa payment as a linear flow:

```
INITIATED → PROMPT SENT → WAITING → SUCCESS
                                  ↘ FAILED
                                  ↘ TIMEOUT
```

That model is wrong in a way that costs real money.

## The problem

When a customer's M-Pesa prompt expires because they never entered their
PIN, Daraja reports a timeout. **The transaction can still settle
afterwards.** A customer who walked away may tap their PIN on a delayed
notification minutes later.

If we record TIMEOUT as a failure and complete the sale as unpaid, we hand
over goods for money that later arrives — or, worse, we refuse a customer
who has genuinely paid.

There is a second, independent failure mode: we write to our database, our
response to Daraja times out, Daraja retries the callback, and we process
the same payment twice.

## Decision

### 1. UNKNOWN and TIMEOUT are non-terminal

```
TERMINAL:     SUCCESS, FAILED, CANCELLED
RECONCILE:    TIMEOUT, UNKNOWN, WAITING
```

Implemented in `packages/payment-provider/src/states.ts`. `canTransition()`
rejects illegal moves, so no code path can mark a TIMEOUT as FAILED.

### 2. Idempotency is enforced by the database, not by convention

`Payment.merchantReconciliationId` and `SalePayment.idempotencyKey` are
`@unique`. A replayed callback hits a constraint violation, not a second
financial entry. The idempotency key is generated client-side and sent to
Daraja as `MerchantReconciliationID`, so the same key travels the whole
round trip.

### 3. A recorded SUCCESS is never silently flipped

Reconciliation is decided by `decideReconcile()` in
`packages/payment-provider/src/reconcile.ts`:

| Recorded | Reported | Action |
|---|---|---|
| anything | same state | `none` |
| `SUCCESS` | different | `keep_polling` |
| `SUCCESS` | different, 3+ consecutive | `write_reversal` |
| non-terminal | `SUCCESS` | `apply_success` |
| non-terminal | `FAILED`/`CANCELLED` | `apply_failure` |
| settled failure | `SUCCESS` | `write_reversal` |

The reversal path appends a correcting entry. It never mutates the
original record, so the audit trail shows both the decision and the
correction.

### 4. A single contradicting read is treated as a glitch

Contradicting a SUCCESS we already reported to a customer is a serious
action. `CONTRADICTION_THRESHOLD = 3` means we re-query three times before
reversing anything.

### 5. Reconciliation runs for 24 hours

`RECONCILE_WINDOW_HOURS = 24`, with backoff from 5s to 1h so a genuinely
dead payment does not consume the API quota.

## Consequences

- The billing and POS flows must handle a non-obvious terminal state. The
  UI says "still confirming" rather than "failed" — see `describeState()`.
- Payment code cannot be written as a simple `await`. Everything that
  settles asynchronously needs a reconciler.
- `FakeMpesaProvider` exists so all of this is testable without Safaricom,
  whose sandbox is unreliable and whose production approval takes weeks.
  Scenario is chosen by msisdn suffix, including a `LATE_SETTLE` case that
  reproduces the dangerous path on demand.
