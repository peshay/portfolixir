# Portfolixir UI Design Notes

## Current Direction

Portfolixir should feel like a modern, self-hosted portfolio management workspace inspired by Portfolio Performance concepts, not a desktop clone. The product shell prioritizes data-dense portfolio workflows: securities, accounts, ledger transactions, classifications, future reports, imports and settings.

The UI foundation uses a persistent desktop sidebar, clear page headers, primary data panels and secondary creation forms. Forms should support the workflow without dominating the page above tables or summaries.

## Responsive Behavior

- Desktop uses a persistent left sidebar and a main workspace constrained to a data-friendly width around 1200-1440px.
- Primary tables, balances and history views should take the wider workspace column.
- Creation forms should sit in secondary panels when the screen has enough width.
- Smartphone layouts collapse to a mobile header with navigation available from a drawer-style menu.
- Forms become single-column on narrow screens.
- Data tables use responsive wrappers with horizontal scrolling when columns cannot be reduced safely.
- Touch targets should remain at least comfortably tappable on mobile.

## Theme Rules

- Theme values should be expressed through CSS variables for background, surface, elevated surface, text, muted text, border, accent, success, warning, error and focus ring.
- Light mode should use intentional neutral surfaces and visible borders rather than raw white HTML defaults.
- Dark mode should use layered surfaces and contrast tokens rather than flat black panels.
- The official logo assets in `priv/static/images` remain the source of truth. Do not create new logo files for theme variants.
- The theme toggle must continue to work without requiring server-side state.

## Localization and Terminology

- User-facing labels should go through Gettext when they are part of the app shell or core workflows.
- German terminology should stay close to Portfolio Performance concepts, especially `Wertpapiere`, `Stammdaten`, `Konten`, `Depots`, `Verrechnungskonten`, `Buchungen` and `Klassifizierungen`.
- English labels should remain polished and usable; do not replace route, module or table names to achieve localization.
- Language selection must remain visible on desktop and mobile, and must not interfere with the theme toggle.

## Accessibility Baseline

- Use semantic landmarks such as `header`, `nav`, `main` and `section`.
- Keep keyboard focus states visible.
- Inputs must have labels.
- Success feedback should use `role="status"` where appropriate.
- Validation errors and warnings that require attention should use `role="alert"`.
- Disabled navigation placeholders should use `aria-disabled="true"`.
- Links and buttons should remain visually distinguishable from static text.
- Avoid tiny text in dense panels.

## Future Accessibility Settings

Future UI work should consider an accessibility settings area for:

- High contrast mode.
- Color-blind-safe palette.
- Reduced motion.
- Larger text.
- Screen-reader audit and remediation.
