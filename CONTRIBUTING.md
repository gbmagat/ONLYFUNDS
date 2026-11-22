# Development and validation

Start with [setup](docs/SETUP.md) and a separate Firebase project with synthetic data.

## Local checks

```sh
flutter pub get
flutter analyze
flutter test
git diff --check
```

These commands are not a claim that every check currently passes. The tests in `test/` cover amount validation, the shared widgets, and the report calculations, including the monthly forecast and alerts, without Firebase. Pages and services that call Firebase are not tested yet; add Firebase doubles or emulator-backed integration tests before relying on the suite as a quality gate.

For changes to records or totals, follow [the demo walkthrough](docs/DEMO.md). Also check empty accounts, invalid amounts, insufficient balance, sign-out/sign-in, multiple users, and a new month. Verify Firestore ownership rules independently of UI behavior.

## Useful next contributions

- Add/test versioned Firestore rules, required indexes, and emulator setup.
- Test concurrent submissions and failure handling for transactions, deposits, and goals against the Firestore emulator.
- Verify in an emulator that account deletion removes nested records when monthly parent documents do not exist.
- Add service, widget, and integration tests for budgeting flows.
- Evaluate the monthly-total regression against a baseline with held-out error metrics, and test it with seeded multi-month data.
- Persist notification settings/history and clarify sample alerts in the UI.
- Add real screenshots and verified platform/build instructions.

Keep documentation synchronized with behavior. Include purpose, validation, and remaining limitations in pull requests. Never commit real financial records, passwords, CLI tokens, or service-account credentials.
