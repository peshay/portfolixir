# Portfolixir

Portfolixir is in a controlled foundation reset.

This branch is not a finished MVP. It is the clean base for future
human-reviewed MVP Epics.

## Foundation Scope

The reboot foundation keeps only the narrow local portfolio-tracking base:

- Phoenix and LiveView shell;
- neutral, unbranded HTML surfaces;
- securities master data;
- one portfolio model;
- cash accounts and linked depots;
- manual buy and sell transaction records;
- derived holdings from stored transactions;
- stored quote history and a simple security detail chart.

For trade entry, the selected depot determines the linked cash account. The UI
is intentionally plain; visual design and branding are deferred to a separate
reviewed change.

## Future Work

Future MVP functionality will be added Epic-by-Epic. Each Epic should pass local
checks, include tests, and update user documentation when behavior changes.

Deferred capabilities remain out of scope until explicitly reviewed and scoped.

For a small local or home setup, see [Home Deployment](home-deployment.md).
