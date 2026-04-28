defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component

  attr(:current_path, :string, default: "/")
  slot(:inner_block, required: true)

  def shell(assigns) do
    assigns = assign_new(assigns, :current_path, fn -> "/" end)

    ~H"""
    <div
      id="app-shell"
      data-layout="portfolio-workspace"
      data-theme="light"
      data-sidebar-collapsed="false"
      data-mobile-nav-open="false"
    >
      <style id="app-shell-styles">
        :root {
          --pfx-bg: #f4f7fb;
          --pfx-surface: #ffffff;
          --pfx-elevated: #f9fbfd;
          --pfx-surface-muted: #eef3f8;
          --pfx-text: #111827;
          --pfx-muted: #5f6f82;
          --pfx-border: #d8e1ea;
          --pfx-input: #ffffff;
          --pfx-input-border: #c6d2df;
          --pfx-link: #0f766e;
          --pfx-accent: #0f766e;
          --pfx-accent-contrast: #ffffff;
          --pfx-accent-soft: #dff7f3;
          --pfx-accent-faint: rgba(15, 118, 110, 0.12);
          --pfx-brand-violet: #7c3aed;
          --pfx-success: #15803d;
          --pfx-success-soft: rgba(21, 128, 61, 0.12);
          --pfx-warning: #b45309;
          --pfx-warning-soft: rgba(180, 83, 9, 0.13);
          --pfx-error: #b91c1c;
          --pfx-error-soft: rgba(185, 28, 28, 0.12);
          --pfx-focus-ring: rgba(20, 184, 166, 0.46);
          --pfx-shadow: 0 18px 40px -32px rgba(17, 24, 39, 0.42);
          --pfx-radius: 8px;
        }

        [data-theme="dark"] {
          --pfx-bg: #111827;
          --pfx-surface: #182231;
          --pfx-elevated: #202b3b;
          --pfx-surface-muted: #243246;
          --pfx-text: #f8fafc;
          --pfx-muted: #b6c2d1;
          --pfx-border: #334155;
          --pfx-input: #121a27;
          --pfx-input-border: #475569;
          --pfx-link: #5eead4;
          --pfx-accent: #2dd4bf;
          --pfx-accent-contrast: #052e2b;
          --pfx-accent-soft: rgba(45, 212, 191, 0.18);
          --pfx-accent-faint: rgba(45, 212, 191, 0.13);
          --pfx-brand-violet: #a78bfa;
          --pfx-success: #4ade80;
          --pfx-success-soft: rgba(74, 222, 128, 0.13);
          --pfx-warning: #fbbf24;
          --pfx-warning-soft: rgba(251, 191, 36, 0.13);
          --pfx-error: #f87171;
          --pfx-error-soft: rgba(248, 113, 113, 0.13);
          --pfx-focus-ring: rgba(94, 234, 212, 0.5);
          --pfx-shadow: 0 20px 48px -32px rgba(0, 0, 0, 0.9);
        }

        html,
        body {
          min-height: 100%;
          margin: 0;
          background: var(--pfx-bg);
        }

        #app-shell,
        #app-shell * {
          box-sizing: border-box;
        }

        #app-shell {
          min-height: 100vh;
          margin: 0;
          background: var(--pfx-bg);
          color: var(--pfx-text);
          font-family:
            Inter,
            ui-sans-serif,
            system-ui,
            -apple-system,
            BlinkMacSystemFont,
            "Segoe UI",
            sans-serif;
          font-size: 16px;
          line-height: 1.5;
        }

        #app-shell a {
          color: var(--pfx-link);
          text-decoration: none;
        }

        #app-shell a:hover {
          text-decoration: underline;
          text-underline-offset: 0.18em;
        }

        #app-shell :focus-visible {
          outline: 3px solid var(--pfx-focus-ring);
          outline-offset: 2px;
        }

        #app-shell .app-shell-layout {
          min-height: 100vh;
          display: grid;
          grid-template-columns: 17.5rem minmax(0, 1fr);
          align-items: stretch;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-layout {
          grid-template-columns: 5.5rem minmax(0, 1fr);
        }

        #app-shell .app-shell-mobile-header {
          display: none;
          min-height: 4rem;
          padding: 0.65rem 1rem;
          align-items: center;
          justify-content: space-between;
          gap: 0.75rem;
          background: color-mix(in srgb, var(--pfx-surface) 94%, transparent);
          border-bottom: 1px solid var(--pfx-border);
          position: sticky;
          top: 0;
          z-index: 20;
          backdrop-filter: blur(14px);
        }

        #app-shell .app-shell-sidebar {
          min-width: 0;
          padding: 1rem;
          background: var(--pfx-surface);
          border-right: 1px solid var(--pfx-border);
          display: flex;
          flex-direction: column;
          gap: 0.95rem;
          min-height: 100vh;
          box-shadow: 10px 0 30px -36px rgba(17, 24, 39, 0.8);
        }

        #app-shell .app-shell-sidebar-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          padding-bottom: 0.35rem;
        }

        #app-shell .app-shell-brand,
        #app-shell .app-shell-mobile-brand {
          display: flex;
          align-items: center;
          gap: 0.6rem;
          min-width: 0;
          color: var(--pfx-text);
          overflow: hidden;
        }

        #app-shell .app-shell-brand {
          padding: 0.25rem 0.2rem;
          flex: 1;
        }

        #app-shell .app-shell-brand:hover,
        #app-shell .app-shell-mobile-brand:hover {
          text-decoration: none;
        }

        #app-shell .app-shell-logo-wordmark,
        #app-shell .app-shell-logo-mark,
        #app-shell .app-shell-mobile-logo {
          width: auto;
          object-fit: contain;
          display: block;
          flex-shrink: 0;
        }

        #app-shell .app-shell-logo-wordmark {
          max-height: 2.15rem;
          height: 2.15rem;
          max-width: 13.75rem;
        }

        #app-shell .app-shell-logo-mark {
          max-height: 2.25rem;
          height: 2.25rem;
        }

        #app-shell .app-shell-mobile-logo {
          max-height: 2rem;
          height: 2rem;
          max-width: 10.5rem;
        }

        #app-shell .app-shell-logo-wordmark-light,
        #app-shell .app-shell-logo-wordmark-dark,
        #app-shell .app-shell-logo-mark {
          display: none;
        }

        #app-shell:not([data-sidebar-collapsed="true"])[data-theme="light"]
          .app-shell-logo-wordmark-light {
          display: block;
        }

        #app-shell:not([data-sidebar-collapsed="true"])[data-theme="dark"]
          .app-shell-logo-wordmark-dark {
          display: block;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-logo-mark {
          display: block;
        }

        #app-shell .app-shell-mobile-logo-light,
        #app-shell .app-shell-mobile-logo-dark {
          display: none;
        }

        #app-shell[data-theme="light"] .app-shell-mobile-logo-light {
          display: block;
        }

        #app-shell[data-theme="dark"] .app-shell-mobile-logo-dark {
          display: block;
        }

        #app-shell .app-shell-visually-hidden {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          white-space: nowrap;
          border: 0;
        }

        #app-shell .app-shell-icon-button {
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-elevated);
          color: var(--pfx-text);
          width: 2.5rem;
          height: 2.5rem;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          font: inherit;
          font-weight: 700;
          transition:
            border-color 0.15s ease,
            background-color 0.15s ease,
            color 0.15s ease;
        }

        #app-shell .app-shell-icon-button:hover {
          border-color: color-mix(in srgb, var(--pfx-accent) 32%, var(--pfx-border));
          background: var(--pfx-accent-faint);
          color: var(--pfx-accent);
        }

        #app-shell .app-shell-sidebar-nav {
          display: flex;
          flex-direction: column;
          gap: 0.9rem;
          min-width: 0;
        }

        #app-shell .app-shell-nav-group {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }

        #app-shell .app-shell-nav-group-title {
          margin: 0;
          padding: 0 0.55rem;
          color: var(--pfx-muted);
          font-size: 0.74rem;
          font-weight: 700;
          letter-spacing: 0.05em;
          line-height: 1.3;
          text-transform: uppercase;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-group-title {
          display: none;
        }

        #app-shell .app-shell-nav-link {
          min-height: 2.75rem;
          display: flex;
          align-items: center;
          gap: 0.7rem;
          border: 1px solid transparent;
          border-radius: var(--pfx-radius);
          padding: 0.64rem 0.7rem;
          color: var(--pfx-text);
          font-weight: 600;
          line-height: 1.25;
          cursor: pointer;
          transition:
            background-color 0.15s ease,
            border-color 0.15s ease,
            color 0.15s ease;
        }

        #app-shell .app-shell-nav-link:hover {
          background: var(--pfx-accent-faint);
          border-color: color-mix(in srgb, var(--pfx-accent) 22%, transparent);
          text-decoration: none;
        }

        #app-shell .app-shell-nav-link.is-active {
          background: linear-gradient(
            90deg,
            var(--pfx-accent-faint),
            color-mix(in srgb, var(--pfx-brand-violet) 8%, transparent)
          );
          border-color: color-mix(in srgb, var(--pfx-accent) 42%, var(--pfx-border));
          color: var(--pfx-accent);
          box-shadow: inset 3px 0 0 var(--pfx-accent);
        }

        #app-shell .app-shell-nav-link.is-disabled {
          opacity: 0.68;
          cursor: not-allowed;
          color: var(--pfx-muted);
          background: transparent;
        }

        #app-shell .app-shell-nav-link.is-disabled:hover {
          border-color: transparent;
          background: transparent;
        }

        #app-shell .app-shell-nav-icon {
          width: 1.65rem;
          min-width: 1.65rem;
          height: 1.65rem;
          border-radius: 6px;
          font-size: 0.72rem;
          font-weight: 800;
          letter-spacing: 0;
          line-height: 1;
          text-align: center;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
          color: var(--pfx-muted);
          background: var(--pfx-elevated);
          border: 1px solid var(--pfx-border);
        }

        #app-shell .app-shell-nav-link.is-active .app-shell-nav-icon {
          color: var(--pfx-accent-contrast);
          background: var(--pfx-accent);
          border-color: var(--pfx-accent);
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-link {
          justify-content: center;
          padding: 0.58rem;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-label {
          display: none;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-brand {
          justify-content: center;
        }

        #app-shell .app-shell-theme-toggle {
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-elevated);
          color: var(--pfx-text);
          padding: 0.62rem 0.7rem;
          cursor: pointer;
          min-height: 2.5rem;
          display: inline-flex;
          align-items: center;
          justify-content: flex-start;
          gap: 0.55rem;
          width: 100%;
          font: inherit;
          font-weight: 650;
          white-space: nowrap;
          transition:
            border-color 0.15s ease,
            background-color 0.15s ease,
            color 0.15s ease;
        }

        #app-shell .app-shell-theme-toggle:hover {
          border-color: color-mix(in srgb, var(--pfx-accent) 32%, var(--pfx-border));
          background: var(--pfx-accent-faint);
        }

        #app-shell .app-shell-theme-label {
          display: inline-block;
          font-size: 0.92rem;
          line-height: 1;
        }

        #app-shell .app-shell-theme-icon {
          width: 1.25rem;
          min-width: 1.25rem;
          text-align: center;
          font-size: 0.95rem;
          line-height: 1;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-toggle {
          width: 2.5rem;
          padding: 0.55rem;
          justify-content: center;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-theme-label {
          display: none;
        }

        #app-shell .app-shell-bottom-spacer {
          margin-top: auto;
        }

        #app-shell .app-shell-main {
          min-width: 0;
          padding: 2rem;
          background:
            linear-gradient(180deg, color-mix(in srgb, var(--pfx-elevated) 52%, transparent), transparent 18rem),
            var(--pfx-bg);
          overflow-x: hidden;
        }

        #app-shell .app-shell-main-inner {
          max-width: 1440px;
          margin: 0 auto;
        }

        #app-shell .app-shell-content-card {
          background: transparent;
          border: 0;
          padding: 0;
        }

        #app-shell .app-shell-page-header {
          margin: 0 0 1.25rem;
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
        }

        #app-shell .app-shell-page-kicker {
          margin: 0 0 0.25rem;
          color: var(--pfx-accent);
          font-size: 0.78rem;
          font-weight: 800;
          letter-spacing: 0.08em;
          text-transform: uppercase;
        }

        #app-shell h1,
        #app-shell h2,
        #app-shell h3 {
          margin: 0;
          color: var(--pfx-text);
          font-weight: 750;
          letter-spacing: 0;
        }

        #app-shell h1 {
          font-size: clamp(1.55rem, 2vw, 2rem);
          line-height: 1.15;
        }

        #app-shell .app-shell-page-header p {
          margin: 0.35rem 0 0;
          max-width: 70ch;
          color: var(--pfx-muted);
        }

        #app-shell .app-shell-section-card {
          background: color-mix(in srgb, var(--pfx-surface) 96%, transparent);
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          padding: 1rem;
          box-shadow: var(--pfx-shadow);
        }

        #app-shell .app-shell-section-card + .app-shell-section-card {
          margin-top: 1rem;
        }

        #app-shell .app-shell-section-card--compact {
          max-width: 760px;
        }

        #app-shell .app-shell-section-title {
          margin: 0;
          color: var(--pfx-text);
          font-size: 1rem;
          line-height: 1.25;
        }

        #app-shell .app-shell-section-header {
          margin-bottom: 0.85rem;
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 0.75rem;
        }

        #app-shell .app-shell-section-header p,
        #app-shell .app-shell-panel-intro {
          margin: 0.3rem 0 0;
          color: var(--pfx-muted);
          font-size: 0.92rem;
        }

        #app-shell .app-shell-workspace-grid {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(20rem, 0.38fr);
          gap: 1rem;
          align-items: start;
        }

        #app-shell .app-shell-workspace-grid > [data-priority="primary"] {
          min-width: 0;
        }

        #app-shell .app-shell-workspace-grid > [data-priority="secondary"] {
          min-width: 0;
        }

        #app-shell .app-shell-workspace-stack {
          display: grid;
          gap: 1rem;
          min-width: 0;
        }

        #app-shell .app-shell-responsive-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
          gap: 1rem;
          align-items: start;
        }

        #app-shell .app-shell-summary-strip {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: 0.65rem;
          margin-top: 0.65rem;
          padding: 0.8rem;
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-elevated);
        }

        #app-shell .app-shell-summary-item {
          min-width: 0;
        }

        #app-shell .app-shell-summary-label {
          display: block;
          margin: 0 0 0.15rem;
          color: var(--pfx-muted);
          font-size: 0.78rem;
          font-weight: 700;
          letter-spacing: 0.04em;
          text-transform: uppercase;
        }

        #app-shell .app-shell-summary-value {
          color: var(--pfx-text);
          font-size: 1rem;
          font-weight: 750;
          overflow-wrap: anywhere;
        }

        #app-shell .app-shell-empty-state {
          background: var(--pfx-elevated);
          border: 1px dashed color-mix(in srgb, var(--pfx-border) 82%, var(--pfx-muted));
          border-radius: var(--pfx-radius);
          padding: 1rem;
        }

        #app-shell .app-shell-empty-state h3 {
          margin: 0 0 0.3rem;
          font-size: 1rem;
          color: var(--pfx-text);
        }

        #app-shell .app-shell-empty-state p {
          margin: 0;
          color: var(--pfx-muted);
        }

        #app-shell .app-shell-help-text,
        #app-shell .app-shell-muted {
          margin: 0.3rem 0 0;
          color: var(--pfx-muted);
          font-size: 0.9rem;
        }

        #app-shell .app-shell-badge {
          display: inline-flex;
          align-items: center;
          min-height: 1.55rem;
          padding: 0.16rem 0.5rem;
          border: 1px solid var(--pfx-border);
          border-radius: 999px;
          background: var(--pfx-elevated);
          color: var(--pfx-muted);
          font-size: 0.78rem;
          font-weight: 750;
          white-space: nowrap;
        }

        #app-shell .app-shell-badge--accent {
          border-color: color-mix(in srgb, var(--pfx-accent) 38%, var(--pfx-border));
          background: var(--pfx-accent-soft);
          color: var(--pfx-accent);
        }

        #app-shell .app-shell-warning-note {
          margin-top: 0.75rem;
          border: 1px solid color-mix(in srgb, var(--pfx-warning) 42%, var(--pfx-border));
          border-radius: var(--pfx-radius);
          background: var(--pfx-warning-soft);
          color: var(--pfx-text);
          padding: 0.65rem 0.75rem;
          font-size: 0.9rem;
        }

        #app-shell .app-shell-alert {
          margin: 0.75rem 0 0;
          border-radius: var(--pfx-radius);
          padding: 0.65rem 0.75rem;
          border: 1px solid transparent;
          font-size: 0.92rem;
        }

        #app-shell .app-shell-alert--success {
          border-color: color-mix(in srgb, var(--pfx-success) 48%, var(--pfx-border));
          background: var(--pfx-success-soft);
          color: var(--pfx-success);
        }

        #app-shell .app-shell-alert--warning {
          border-color: color-mix(in srgb, var(--pfx-warning) 48%, var(--pfx-border));
          background: var(--pfx-warning-soft);
          color: var(--pfx-text);
        }

        #app-shell .app-shell-alert--error {
          border-color: color-mix(in srgb, var(--pfx-error) 48%, var(--pfx-border));
          background: var(--pfx-error-soft);
          color: var(--pfx-error);
        }

        #app-shell form {
          margin: 0;
        }

        #app-shell .app-shell-form-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 0.8rem 0.85rem;
        }

        #app-shell .app-shell-form-grid .app-shell-field--full,
        #app-shell .app-shell-form-grid .app-shell-form-actions,
        #app-shell .app-shell-form-grid .app-shell-fieldset {
          grid-column: 1 / -1;
        }

        #app-shell .app-shell-field,
        #app-shell .app-shell-fieldset {
          min-width: 0;
        }

        #app-shell .app-shell-fieldset {
          margin: 0;
          padding: 0.8rem;
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-elevated);
        }

        #app-shell .app-shell-fieldset legend {
          padding: 0 0.35rem;
          color: var(--pfx-muted);
          font-size: 0.78rem;
          font-weight: 800;
          letter-spacing: 0.06em;
          text-transform: uppercase;
        }

        #app-shell .app-shell-fieldset-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 0.8rem 0.85rem;
        }

        #app-shell label {
          display: block;
          margin: 0 0 0.28rem;
          color: var(--pfx-muted);
          font-size: 0.87rem;
          font-weight: 650;
        }

        #app-shell input,
        #app-shell textarea,
        #app-shell select,
        #app-shell table {
          background: var(--pfx-input);
          color: var(--pfx-text);
        }

        #app-shell input,
        #app-shell textarea,
        #app-shell select {
          width: 100%;
          min-height: 2.65rem;
          border: 1px solid var(--pfx-input-border);
          border-radius: var(--pfx-radius);
          padding: 0.54rem 0.65rem;
          font: inherit;
        }

        #app-shell textarea {
          min-height: 5rem;
          resize: vertical;
        }

        #app-shell input:focus,
        #app-shell textarea:focus,
        #app-shell select:focus {
          border-color: color-mix(in srgb, var(--pfx-accent) 72%, var(--pfx-input-border));
        }

        #app-shell .app-shell-form-actions {
          display: flex;
          align-items: center;
          justify-content: flex-start;
          gap: 0.6rem;
          flex-wrap: wrap;
          margin-top: 0.1rem;
        }

        #app-shell .app-shell-form-grid + .app-shell-empty-state,
        #app-shell .app-shell-form-grid + .app-shell-list,
        #app-shell .app-shell-form-grid + .app-shell-table-wrapper {
          margin-top: 1rem;
        }

        #app-shell button,
        #app-shell .app-shell-button {
          border: 1px solid var(--pfx-input-border);
          border-radius: var(--pfx-radius);
          padding: 0.62rem 0.9rem;
          cursor: pointer;
          background: var(--pfx-elevated);
          color: var(--pfx-text);
          font: inherit;
          font-weight: 700;
          min-height: 2.65rem;
          transition:
            background-color 0.15s ease,
            border-color 0.15s ease,
            color 0.15s ease,
            transform 0.15s ease;
        }

        #app-shell button:hover,
        #app-shell .app-shell-button:hover {
          border-color: color-mix(in srgb, var(--pfx-accent) 35%, var(--pfx-input-border));
          background: var(--pfx-accent-faint);
          text-decoration: none;
        }

        #app-shell button.app-shell-primary {
          border-color: color-mix(in srgb, var(--pfx-accent) 80%, var(--pfx-input-border));
          background: var(--pfx-accent);
          color: var(--pfx-accent-contrast);
        }

        #app-shell button.app-shell-primary:hover {
          filter: brightness(0.98);
        }

        #app-shell button.app-shell-secondary {
          border-color: color-mix(in srgb, var(--pfx-muted) 42%, var(--pfx-input-border));
          background: var(--pfx-elevated);
          color: var(--pfx-text);
        }

        #app-shell button:disabled,
        #app-shell button[aria-disabled="true"] {
          cursor: not-allowed;
          opacity: 0.62;
        }

        #app-shell .app-shell-table-wrapper {
          width: 100%;
          overflow-x: auto;
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-surface);
        }

        #app-shell table {
          width: 100%;
          min-width: 46rem;
          border-collapse: collapse;
          font-size: 0.92rem;
        }

        #app-shell th,
        #app-shell td {
          text-align: left;
          border-bottom: 1px solid var(--pfx-border);
          padding: 0.68rem 0.75rem;
          vertical-align: top;
        }

        #app-shell th {
          background: var(--pfx-elevated);
          color: var(--pfx-muted);
          font-size: 0.76rem;
          font-weight: 800;
          letter-spacing: 0.05em;
          text-transform: uppercase;
          white-space: nowrap;
        }

        #app-shell tr:last-child td {
          border-bottom: 0;
        }

        #app-shell tbody tr:hover td {
          background: var(--pfx-accent-faint);
        }

        #app-shell .app-shell-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: 0.55rem;
        }

        #app-shell .app-shell-list-item {
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-elevated);
          padding: 0.75rem;
        }

        #app-shell .app-shell-list-item + .app-shell-list-item {
          margin-top: 0;
        }

        @media (max-width: 1100px) {
          #app-shell .app-shell-workspace-grid {
            grid-template-columns: minmax(0, 1fr);
          }

          #app-shell .app-shell-section-card--compact {
            max-width: none;
          }
        }

        @media (max-width: 760px) {
          #app-shell .app-shell-mobile-header {
            display: flex;
          }

          #app-shell .app-shell-layout {
            display: block;
            min-height: auto;
          }

          #app-shell .app-shell-sidebar,
          #app-shell[data-sidebar-collapsed="true"] .app-shell-sidebar {
            display: none;
            width: 100%;
            min-width: 100%;
            min-height: auto;
            border-right: none;
            border-bottom: 1px solid var(--pfx-border);
            box-shadow: var(--pfx-shadow);
          }

          #app-shell[data-mobile-nav-open="true"] .app-shell-sidebar {
            display: flex;
          }

          #app-shell .app-shell-sidebar-top {
            display: none;
          }

          #app-shell .app-shell-sidebar-nav {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 0.8rem;
          }

          #app-shell .app-shell-nav-link,
          #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-link {
            justify-content: flex-start;
            padding: 0.68rem;
          }

          #app-shell[data-sidebar-collapsed="true"] .app-shell-nav-label {
            display: inline;
          }

          #app-shell .app-shell-main {
            padding: 1rem;
          }

          #app-shell .app-shell-page-header {
            display: block;
          }

          #app-shell .app-shell-section-card {
            padding: 0.9rem;
          }

          #app-shell .app-shell-form-grid,
          #app-shell .app-shell-fieldset-grid,
          #app-shell .app-shell-responsive-grid,
          #app-shell .app-shell-summary-strip {
            grid-template-columns: 1fr;
          }

          #app-shell table {
            min-width: 40rem;
            font-size: 0.88rem;
          }

          #app-shell th,
          #app-shell td {
            padding: 0.58rem 0.62rem;
          }

          #app-shell input,
          #app-shell textarea,
          #app-shell select,
          #app-shell button,
          #app-shell .app-shell-button {
            min-height: 2.85rem;
          }
        }

        @media (max-width: 520px) {
          #app-shell .app-shell-sidebar-nav {
            grid-template-columns: 1fr;
          }

          #app-shell .app-shell-mobile-logo {
            max-width: 8.8rem;
          }

          #app-shell .app-shell-table-wrapper {
            margin-left: -0.25rem;
            margin-right: -0.25rem;
            width: calc(100% + 0.5rem);
          }
        }
      </style>

      <header class="app-shell-mobile-header" aria-label="Mobile application header">
        <a href="/securities" class="app-shell-mobile-brand" aria-label="Portfolixir">
          <img
            class="app-shell-mobile-logo app-shell-mobile-logo-light"
            src="/images/logo-light.svg"
            alt="Portfolixir"
          />
          <img
            class="app-shell-mobile-logo app-shell-mobile-logo-dark"
            src="/images/logo-dark.svg"
            alt="Portfolixir"
          />
          <span class="app-shell-visually-hidden">Portfolixir</span>
        </a>
        <button
          id="mobile-nav-toggle"
          class="app-shell-icon-button"
          type="button"
          aria-label="Open navigation"
          aria-expanded="false"
          title="Open navigation"
        >
          ☰
        </button>
      </header>

      <div class="app-shell-layout">
        <aside class="app-shell-sidebar" aria-label="Primary navigation">
          <div class="app-shell-sidebar-top">
            <a href="/securities" class="app-shell-brand" aria-label="Portfolixir">
              <img
                id="app-shell-brand-light-wordmark"
                class="app-shell-logo-wordmark app-shell-logo-wordmark-light"
                src="/images/logo-light.svg"
                alt="Portfolixir"
              />
              <img
                id="app-shell-brand-dark-wordmark"
                class="app-shell-logo-wordmark app-shell-logo-wordmark-dark"
                src="/images/logo-dark.svg"
                alt="Portfolixir"
              />
              <img
                id="app-shell-brand-mark"
                class="app-shell-logo-mark"
                src="/images/logo-mark.svg"
                alt="Portfolixir mark"
              />
              <span class="app-shell-visually-hidden">Portfolixir</span>
            </a>
            <button
              id="sidebar-toggle"
              class="app-shell-icon-button"
              type="button"
              aria-label="Collapse sidebar"
              title="Collapse sidebar"
            >
              ☰
            </button>
          </div>

          <nav class="app-shell-sidebar-nav" aria-label="Main navigation">
            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Securities</p>
              <a
                href="/securities"
                aria-label="All Securities"
                title="All Securities"
                class={nav_link_class(@current_path, "/securities", true)}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">SEC</span>
                <span class="app-shell-nav-label">All Securities</span>
              </a>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Watchlist"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">W</span>
                <span class="app-shell-nav-label">Watchlist</span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Master data</p>
              <a
                href="/accounts"
                aria-label="Accounts"
                title="Accounts"
                class={nav_link_class(@current_path, "/accounts")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">ACC</span>
                <span class="app-shell-nav-label">Accounts</span>
              </a>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Securities accounts"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">SA</span>
                <span class="app-shell-nav-label">Securities accounts</span>
              </span>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Deposit accounts"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">DA</span>
                <span class="app-shell-nav-label">Deposit accounts</span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Ledger</p>
              <a
                href="/transactions"
                aria-label="Transactions"
                title="Transactions"
                class={nav_link_class(@current_path, "/transactions")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">TX</span>
                <span class="app-shell-nav-label">Transactions</span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Classifications</p>
              <a
                href="/taxonomies"
                aria-label="Classifications"
                title="Classifications"
                class={nav_link_class(@current_path, "/taxonomies")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">CL</span>
                <span class="app-shell-nav-label">Classifications</span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Reports</p>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Holdings"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">HD</span>
                <span class="app-shell-nav-label">Holdings</span>
              </span>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Performance"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">PF</span>
                <span class="app-shell-nav-label">Performance</span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title">Imports</p>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label="Imports"
                aria-disabled="true"
                title="Coming soon"
              >
                <span class="app-shell-nav-icon" aria-hidden="true">IM</span>
                <span class="app-shell-nav-label">Imports</span>
              </span>
            </div>
          </nav>

          <button
            id="theme-toggle"
            class="app-shell-theme-toggle app-shell-bottom-spacer"
            type="button"
            title="Switch to dark mode"
            aria-label="Switch to dark mode"
          >
            <span class="app-shell-theme-icon" aria-hidden="true">T</span>
            <span class="app-shell-theme-label">Dark mode</span>
          </button>
        </aside>

        <main class="app-shell-main">
          <div class="app-shell-main-inner">
            <section class="app-shell-content-card">
              <%= render_slot(@inner_block) %>
            </section>
          </div>
        </main>
      </div>

      <script id="theme-toggle-script">
        (function () {
          var themeKey = "portfolixir-theme";
          var sidebarKey = "portfolixir-sidebar-collapsed";
          var shell = document.getElementById("app-shell");
          var toggle = document.getElementById("theme-toggle");
          var themeLabel = document.querySelector("#theme-toggle .app-shell-theme-label");
          var themeIcon = document.querySelector("#theme-toggle .app-shell-theme-icon");
          var sidebarToggle = document.getElementById("sidebar-toggle");
          var mobileNavToggle = document.getElementById("mobile-nav-toggle");

          function normalizeTheme(value) {
            return value === "dark" ? "dark" : "light";
          }

          function applyTheme(theme) {
            var resolvedTheme = normalizeTheme(theme);
            shell.setAttribute("data-theme", resolvedTheme);
            document.documentElement.setAttribute("data-theme", resolvedTheme);
            var isDark = resolvedTheme === "dark";

            if (themeLabel) {
              themeLabel.textContent = isDark ? "Light mode" : "Dark mode";
            }

            if (themeIcon) {
              themeIcon.textContent = isDark ? "L" : "D";
            }

            if (toggle) {
              toggle.setAttribute("title", isDark ? "Switch to light mode" : "Switch to dark mode");
              toggle.setAttribute("aria-label", isDark ? "Switch to light mode" : "Switch to dark mode");
            }

            try {
              localStorage.setItem(themeKey, resolvedTheme);
            } catch (_error) {}
          }

          function applySidebarState(isCollapsed) {
            shell.setAttribute("data-sidebar-collapsed", isCollapsed ? "true" : "false");
            if (sidebarToggle) {
              sidebarToggle.setAttribute("aria-pressed", isCollapsed ? "true" : "false");
              sidebarToggle.setAttribute("title", isCollapsed ? "Expand sidebar" : "Collapse sidebar");
              sidebarToggle.setAttribute("aria-label", isCollapsed ? "Expand sidebar" : "Collapse sidebar");
            }

            try {
              localStorage.setItem(sidebarKey, isCollapsed ? "true" : "false");
            } catch (_error) {}
          }

          function applyMobileNavState(isOpen) {
            shell.setAttribute("data-mobile-nav-open", isOpen ? "true" : "false");
            if (mobileNavToggle) {
              mobileNavToggle.setAttribute("aria-expanded", isOpen ? "true" : "false");
              mobileNavToggle.setAttribute("title", isOpen ? "Close navigation" : "Open navigation");
              mobileNavToggle.setAttribute("aria-label", isOpen ? "Close navigation" : "Open navigation");
            }
          }

          function currentTheme() {
            try {
              return normalizeTheme(localStorage.getItem(themeKey));
            } catch (_error) {}
            return "light";
          }

          function currentSidebarCollapsed() {
            try {
              return localStorage.getItem(sidebarKey) === "true";
            } catch (_error) {}
            return false;
          }

          function ensureFavicons() {
            var head = document.head;
            if (!head) {
              return;
            }

            var svgFavicon = document.querySelector("link[data-pfx-favicon='svg']");
            if (!svgFavicon) {
              svgFavicon = document.createElement("link");
              svgFavicon.setAttribute("rel", "icon");
              svgFavicon.setAttribute("type", "image/svg+xml");
              svgFavicon.setAttribute("data-pfx-favicon", "svg");
              head.appendChild(svgFavicon);
            }

            var icoFavicon = document.querySelector("link[data-pfx-favicon='ico']");
            if (!icoFavicon) {
              icoFavicon = document.createElement("link");
              icoFavicon.setAttribute("rel", "alternate icon");
              icoFavicon.setAttribute("type", "image/x-icon");
              icoFavicon.setAttribute("data-pfx-favicon", "ico");
              head.appendChild(icoFavicon);
            }

            svgFavicon.href = "/favicon.svg";
            icoFavicon.href = "/favicon.ico";
          }

          if (shell) {
            applyTheme(currentTheme());
            applySidebarState(currentSidebarCollapsed());
            applyMobileNavState(false);
            ensureFavicons();
          }

          if (toggle) {
            toggle.addEventListener("click", function () {
              var nextTheme = shell.getAttribute("data-theme") === "dark" ? "light" : "dark";
              applyTheme(nextTheme);
            });
          }

          if (sidebarToggle) {
            sidebarToggle.addEventListener("click", function () {
              var isCollapsed = shell.getAttribute("data-sidebar-collapsed") === "true";
              applySidebarState(!isCollapsed);
            });
          }

          if (mobileNavToggle) {
            mobileNavToggle.addEventListener("click", function () {
              var isOpen = shell.getAttribute("data-mobile-nav-open") === "true";
              applyMobileNavState(!isOpen);
            });
          }
        })();
      </script>
    </div>
    """
  end

  defp nav_link_class(current_path, path, root_active? \\ false) do
    if current_path == path || (root_active? && current_path == "/") do
      "app-shell-nav-link is-active"
    else
      "app-shell-nav-link"
    end
  end
end
