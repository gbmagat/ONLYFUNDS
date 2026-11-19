# Demo walkthrough

Use your own Firebase project and a disposable account after [setup](SETUP.md). This is a manual review script, not a completed test report.

1. Register and sign in.
2. Add **₱10,000** income under **Income/Allowance**.
3. Add **₱500** Food/Grocery and **₱200** Transportation expenses.
4. Check the dashboard: income **₱10,000**, expenses **₱700**, balance **₱9,300**.
5. Open History. Compare Newest/Oldest ordering and Income/Expense filters.
6. In Savings, add a **₱2,000** target in an available category and deposit **₱1,000** toward the monthly saved total.
7. Check expenses **₱1,700**, balance **₱8,300**, target savings **₱2,000**, and amount saved **₱1,000**. The deposit records an allocation; it is not a bank transfer.
8. Attempt an expense above **₱8,300** and check the insufficient-balance message.
9. Open Reports for category spending, savings analysis, and recommendations. The **₱1,000** deposit counts as savings, not spending: expenses **₱700**, savings **₱9,300**, a 93% savings rate, and no Funds entry in the category breakdown. An account with fewer than three completed months of expenses should produce the insufficient-data prediction state.
10. Sign out and back in to check that the same account's records remain available.

Dashboard and history are scoped to the current month. A fresh month uses separate records.

## Analytics and alerts

The forecast needs expenses in at least three completed calendar months, so a freshly registered demo account cannot exercise it. Use an account with older records, or seed earlier months in a test project. Present it as an experimental estimate; the repository has no measured prediction accuracy. The notification page's sample alerts use demonstration amounts rather than the account's actual balance.

## Portfolio visuals

Capture the dashboard, filtered history, savings progress, and reports using synthetic data. Keep account emails and Firebase console details out of screenshots. Add actual screenshots to `docs/images/` and link them in the README when available; no app screenshots or app-store release are currently included.

A short recording can follow sign-in → income/expense entry → savings → history → reports. Explain the Firestore organization and one improvement you would make next.
