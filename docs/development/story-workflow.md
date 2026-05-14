# Story Workflow

Portfolixir adds future MVP behavior through small, human-reviewed Epics. The
reboot foundation keeps story scope narrow so code, tests, translations, and
user documentation stay consistent.

For every user-visible story, use this order:

1. User Story documented.
2. Functional test written directly below the User Story comment.
3. Test failure confirmed for the expected reason.
4. Smallest implementation code written.
5. Security audit completed before finalizing behavior changes.
6. Required gates run.
7. User documentation reviewed and updated when visible behavior changed.

Every user-visible change updates user documentation when behavior changes.
Visible copy stays English-first in code and must include German gettext
translations.

The story comment belongs in the relevant test file immediately above the
functional test:

```elixir
# User story:
# As a local portfolio maintainer,
# I want to record a manual buy transaction,
# so that my holdings are derived from auditable local data.
#
# Acceptance criteria:
# - The transaction is stored with Decimal values.
# - The holdings view includes the bought quantity.
test "records a manual buy transaction and updates holdings" do
  ...
end
```

The first run of the new or changed test must fail for the expected reason. The
implementation should then make the smallest change that fulfills the story and
acceptance criteria.

Run the required gates before review:

```bash
mix format
mix test
mix coveralls
pre-commit run --all-files
```

Review user-facing documentation for every story. Update docs when the story
changes routes, screens, labels, setup, or visible behavior. For background-only
work, record that user documentation was reviewed and no update was needed.

Future MVP Epics should pass local gates and human review before merge.
