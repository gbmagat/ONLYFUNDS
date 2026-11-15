# Architecture and data model

## Application flow

`main.dart` initializes Firebase and selects sign-in or home from the current Firebase user. `HomePage` hosts navigation to the dashboard, savings, reports, history, and settings. Pages call service classes and also perform some direct Firebase operations. There is no separate custom API server or strict repository/state-management layer.

| Area | Implementation |
| --- | --- |
| Authentication | `AuthService` wraps email/password authentication, recovery, reauthentication, and account deletion. |
| Profiles | `UserService` creates/reads Firestore profiles; account-page code also updates profiles directly. |
| Transactions | `TransactionService` writes records, checks balance, and exposes current-month summary/history streams. |
| Savings | `SavingsService` maintains category targets and monthly saved totals. The savings page coordinates contributions with `TransactionService`. |
| Reports | `AnalyticsService` fetches up to six months of records, calculates metrics, fits regression, and generates threshold-based recommendations/alerts. |
| Notifications | `NotificationService` displays dialogs/snackbars and stores settings/history in memory. The notification page includes sample alert actions. |

## Firestore paths

```text
users/{uid}
  user_name, email, date_created, phone (optional profile update)
  monthly_records/{YYYY-MM}
    transactions/{autoId}
      label, category, description, amount, type, date_added
    goals/{category}
      amount, lastUpdated
    summary/record
      totalIncome, totalExpense, balance,
      targetSavings, amountSaved, lastUpdated
```

`uid` comes from Firebase Authentication. Month identifiers use the device's local calendar date. Monthly parent documents are used as paths and are not explicitly created by the transaction/savings services. Firestore can contain nested documents without an existing parent document.

| Field | Meaning |
| --- | --- |
| Transaction `amount` / `type` | Numeric amount and `income` or `expense`; assigned to the month in which it is entered. |
| Goal `amount` | Category target, rather than deposits into that category. Repeated additions increase the target. |
| Summary `balance` | Income minus expenses, clamped to zero by the transaction update logic. |
| Summary `targetSavings` | Combined monthly category targets. |
| Summary `amountSaved` | Combined recorded savings contributions for the month. |

Savings deposits create an expense transaction (default label `Savings`, category `Funds`) and separately increase `amountSaved`. Reports include these contributions in expense aggregates. There is no bank integration or actual movement of funds.

## Consistency and account lifecycle

Dashboard/history views subscribe to Firestore snapshots. Some summary updates run inside Firestore transactions, but record creation is not atomic as a whole: `addTransaction` validates balance and writes a record before updating its summary. Savings deductions and saved-total updates are separate calls. Concurrent writes or partial failures can leave inconsistent totals; related validation and writes should be combined in a future revision.

Account deletion reauthenticates, deletes nested records month by month, then removes the profile and Auth account. Because write paths do not create monthly parent documents, a query on `monthly_records` returns nothing for them. Deletion therefore generates the month identifiers from the account's creation date to the present, plus any month documents that do exist. Records filed under a month outside that range, for example from a badly wrong device clock, would be missed. This cleanup has not been run against a live project and should be verified before claiming complete deletion.

## Analytics

- Fetches the current month and five preceding months, one transaction collection at a time.
- Calculates totals, category spending, savings rate, monthly trends, and savings profiles.
- Fits `ml_algo`'s `LinearRegressor` on the expense totals of completed months, using months since the oldest month as the feature, and predicts the calendar month after the current one. The current month is excluded because its total is still growing. At least three completed months with expenses are required; the six-month fetch window allows at most five.
- Generates budget suggestions from fixed spending/income thresholds; these are rule-based.
- Computes a confidence heuristic from the number of months and the spread of monthly totals relative to their mean. There is no held-out evaluation or published error metric.

The UI labels the result as next month's predicted total, which is what the model estimates. With three to five data points it is a rough trend line. Savings deposits are recorded as expenses and are included in the totals. Out-of-sample evaluation is a useful next step before relying on it.

## Platforms and access

Firebase options cover Android and iOS only. Generated desktop/web folders remain, but those platforms are rejected by initialization. Firestore rules and indexes are not versioned here; per-user paths alone do not establish server-enforced access control.
