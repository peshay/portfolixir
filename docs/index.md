# Portfolixir

Portfolixir is in a controlled foundation reset.

This branch is not a finished MVP. It is the clean base for future
human-reviewed MVP Epics.

## Foundation Scope

The reboot foundation keeps only the narrow local portfolio-tracking base:

- Phoenix and LiveView shell;
- securities master data;
- one portfolio model;
- cash accounts and linked depots;
- manual buy and sell transaction records;
- derived holdings from stored transactions;
- stored quote history and a simple security detail chart.

## Future Work

Future MVP functionality will be added Epic-by-Epic. Each Epic should pass local
checks, deploy to staging, receive human staging review, and only then be
promoted toward production.

Deferred capabilities remain out of scope until explicitly reviewed and scoped.
