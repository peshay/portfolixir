defmodule PortfolixirWeb.AppShell do
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  attr(:current_path, :string, default: "/")
  slot(:inner_block, required: true)

  def shell(assigns) do
    assigns = assign_new(assigns, :current_path, fn -> "/" end)

    assigns =
      assign_new(assigns, :locale, fn -> Gettext.get_locale(PortfolixirWeb.Gettext) end)

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
          --pfx-sidebar-bg: #071426;
          --pfx-sidebar-surface: #0f1d33;
          --pfx-sidebar-elevated: #15243d;
          --pfx-sidebar-text: #f8fafc;
          --pfx-sidebar-muted: #91a4bd;
          --pfx-sidebar-border: rgba(148, 163, 184, 0.2);
          --pfx-topbar-bg: rgba(255, 255, 255, 0.86);
          --pfx-topbar-border: #e3e9f1;
        }

        [data-theme="dark"] {
          --pfx-bg: #0f1724;
          --pfx-surface: #172033;
          --pfx-elevated: #202b3f;
          --pfx-surface-muted: #26344c;
          --pfx-text: #f8fafc;
          --pfx-muted: #b6c2d1;
          --pfx-border: #34445c;
          --pfx-input: #111a2a;
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
          --pfx-sidebar-bg: #050d1b;
          --pfx-sidebar-surface: #0b172a;
          --pfx-sidebar-elevated: #122039;
          --pfx-sidebar-text: #f8fafc;
          --pfx-sidebar-muted: #9aadc4;
          --pfx-sidebar-border: rgba(148, 163, 184, 0.18);
          --pfx-topbar-bg: rgba(15, 23, 36, 0.88);
          --pfx-topbar-border: #26344c;
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
          grid-template-columns: 15.75rem minmax(0, 1fr);
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
          background:
            linear-gradient(180deg, rgba(45, 212, 191, 0.08), transparent 17rem),
            var(--pfx-sidebar-bg);
          border-right: 1px solid var(--pfx-sidebar-border);
          color: var(--pfx-sidebar-text);
          display: flex;
          flex-direction: column;
          gap: 0.95rem;
          min-height: 100vh;
          box-shadow: 18px 0 48px -36px rgba(15, 23, 42, 0.95);
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
          color: var(--pfx-sidebar-text);
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

        #app-shell .app-shell-logo-mark,
        #app-shell .app-shell-mobile-logo {
          width: auto;
          object-fit: contain;
          display: block;
          flex-shrink: 0;
        }

        #app-shell .app-shell-logo-mark {
          display: block;
          max-height: 1.95rem;
          height: 1.95rem;
        }

        #app-shell .app-shell-mobile-logo {
          max-height: 1.9rem;
          height: 1.9rem;
        }

        #app-shell .app-shell-brand-text,
        #app-shell .app-shell-mobile-brand-text {
          color: inherit;
          font-size: 1rem;
          font-weight: 800;
          line-height: 1;
          letter-spacing: 0;
        }

        #app-shell .app-shell-mobile-brand {
          color: var(--pfx-text);
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-logo-mark {
          display: block;
        }

        #app-shell[data-sidebar-collapsed="true"] .app-shell-brand-text {
          display: none;
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
          color: var(--pfx-sidebar-muted);
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
          color: var(--pfx-sidebar-text);
          font-weight: 600;
          line-height: 1.25;
          cursor: pointer;
          transition:
            background-color 0.15s ease,
            border-color 0.15s ease,
            color 0.15s ease;
        }

        #app-shell .app-shell-nav-link:hover {
          background: rgba(255, 255, 255, 0.07);
          border-color: var(--pfx-sidebar-border);
          text-decoration: none;
        }

        #app-shell .app-shell-nav-link.is-active {
          background: linear-gradient(
            90deg,
            rgba(45, 212, 191, 0.2),
            rgba(124, 58, 237, 0.12)
          );
          border-color: rgba(94, 234, 212, 0.35);
          color: #ffffff;
          box-shadow: inset 3px 0 0 var(--pfx-accent);
        }

        #app-shell .app-shell-nav-link.is-disabled {
          opacity: 0.68;
          cursor: not-allowed;
          color: var(--pfx-sidebar-muted);
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
          color: var(--pfx-sidebar-muted);
          background: rgba(255, 255, 255, 0.06);
          border: 1px solid var(--pfx-sidebar-border);
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
          padding: 0.52rem 0.7rem;
          cursor: pointer;
          min-height: 2.25rem;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 0.55rem;
          width: auto;
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

        #app-shell .app-shell-main-column {
          min-width: 0;
          display: flex;
          flex-direction: column;
          min-height: 100vh;
        }

        #app-shell .app-shell-topbar {
          min-height: 3.5rem;
          padding: 0.65rem 2rem;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 1rem;
          background: var(--pfx-topbar-bg);
          border-bottom: 1px solid var(--pfx-topbar-border);
          position: sticky;
          top: 0;
          z-index: 18;
          backdrop-filter: blur(16px);
        }

        #app-shell .app-shell-topbar-left,
        #app-shell .app-shell-topbar-actions,
        #app-shell .app-shell-breadcrumb {
          display: flex;
          align-items: center;
          min-width: 0;
        }

        #app-shell .app-shell-topbar-left {
          gap: 0.85rem;
        }

        #app-shell .app-shell-topbar-actions {
          gap: 0.55rem;
          flex-shrink: 0;
        }

        #app-shell .app-shell-mobile-actions {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          flex-shrink: 0;
        }

        #app-shell .app-shell-language-toggle {
          display: inline-flex;
          align-items: center;
          gap: 0.15rem;
          padding: 0.2rem;
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-elevated);
        }

        #app-shell .app-shell-language-link {
          min-width: 2.25rem;
          min-height: 1.9rem;
          padding: 0.32rem 0.5rem;
          border-radius: 6px;
          color: var(--pfx-muted);
          font-size: 0.78rem;
          font-weight: 850;
          line-height: 1;
          display: inline-flex;
          align-items: center;
          justify-content: center;
        }

        #app-shell .app-shell-language-link:hover {
          text-decoration: none;
          background: var(--pfx-accent-faint);
          color: var(--pfx-accent);
        }

        #app-shell .app-shell-language-link.is-active {
          background: var(--pfx-accent);
          color: var(--pfx-accent-contrast);
        }

        #app-shell .app-shell-breadcrumb {
          gap: 0.45rem;
          color: var(--pfx-muted);
          font-size: 0.86rem;
          font-weight: 650;
        }

        #app-shell .app-shell-breadcrumb-current {
          color: var(--pfx-text);
          font-weight: 800;
        }

        #app-shell .app-shell-breadcrumb-separator {
          color: var(--pfx-muted);
        }

        #app-shell .app-shell-main {
          min-width: 0;
          padding: 1.5rem 2rem 2rem;
          background:
            linear-gradient(180deg, color-mix(in srgb, var(--pfx-surface) 70%, transparent), transparent 18rem),
            var(--pfx-bg);
          overflow-x: hidden;
          flex: 1;
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

        #app-shell .app-shell-action-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.75rem;
          margin: 0 0 1rem;
        }

        #app-shell .app-shell-action-row-left,
        #app-shell .app-shell-action-row-right {
          display: flex;
          align-items: center;
          gap: 0.65rem;
          min-width: 0;
        }

        #app-shell .app-shell-action-row-left {
          flex: 1;
        }

        #app-shell .app-shell-action-list {
          margin: 0;
          padding-left: 1.25rem;
          display: grid;
          gap: 0.45rem;
        }

        #app-shell .app-shell-search {
          max-width: 20rem;
        }

        #app-shell .app-shell-stat-grid {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: 1rem;
          margin-bottom: 1rem;
        }

        #app-shell .app-shell-stat-card {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          gap: 0.8rem;
          align-items: center;
          min-height: 5.25rem;
          padding: 1rem;
          background: var(--pfx-surface);
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          box-shadow: 0 16px 38px -34px rgba(15, 23, 42, 0.55);
        }

        #app-shell .app-shell-stat-icon {
          width: 2.25rem;
          height: 2.25rem;
          border-radius: 999px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          color: var(--pfx-accent);
          background: var(--pfx-accent-soft);
          font-weight: 850;
          font-size: 0.78rem;
          line-height: 1;
        }

        #app-shell .app-shell-stat-label {
          display: block;
          margin: 0 0 0.1rem;
          color: var(--pfx-muted);
          font-size: 0.78rem;
          font-weight: 700;
        }

        #app-shell .app-shell-stat-value {
          display: block;
          color: var(--pfx-text);
          font-size: 1.3rem;
          font-weight: 850;
          line-height: 1.1;
        }

        #app-shell .app-shell-stat-hint {
          display: block;
          margin-top: 0.12rem;
          color: var(--pfx-muted);
          font-size: 0.78rem;
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

        #app-shell .app-shell-empty-state--inline {
          margin-top: 1rem;
        }

        #app-shell .app-shell-onboarding {
          min-height: 17rem;
          padding: 1.35rem;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.65rem;
          background:
            linear-gradient(135deg, var(--pfx-accent-faint), transparent 42%),
            var(--pfx-surface);
        }

        #app-shell .app-shell-onboarding--compact {
          max-width: 760px;
        }

        #app-shell .app-shell-onboarding .app-shell-page-kicker {
          margin: 0;
        }

        #app-shell .app-shell-onboarding h2 {
          font-size: clamp(1.35rem, 2vw, 1.75rem);
          line-height: 1.15;
        }

        #app-shell .app-shell-onboarding > p {
          max-width: 58ch;
          margin: 0;
          color: var(--pfx-muted);
        }

        #app-shell .app-shell-onboarding-actions {
          display: flex;
          align-items: center;
          gap: 0.65rem;
          flex-wrap: wrap;
          margin-top: 0.35rem;
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
          display: inline-flex;
          align-items: center;
          justify-content: center;
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

        #app-shell button.app-shell-primary,
        #app-shell .app-shell-button.app-shell-primary {
          border-color: color-mix(in srgb, var(--pfx-accent) 80%, var(--pfx-input-border));
          background: var(--pfx-accent);
          color: var(--pfx-accent-contrast);
        }

        #app-shell button.app-shell-primary:hover,
        #app-shell .app-shell-button.app-shell-primary:hover {
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

        #app-shell input:disabled,
        #app-shell textarea:disabled,
        #app-shell select:disabled {
          cursor: not-allowed;
          background: var(--pfx-surface-muted);
          color: var(--pfx-muted);
          opacity: 0.72;
        }

        #app-shell .app-shell-table-wrapper {
          width: 100%;
          overflow-x: auto;
          border: 1px solid var(--pfx-border);
          border-radius: var(--pfx-radius);
          background: var(--pfx-surface);
          box-shadow: 0 16px 40px -36px rgba(15, 23, 42, 0.45);
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

        #app-shell .app-shell-bottom-nav {
          display: none;
          position: fixed;
          left: 0;
          right: 0;
          bottom: 0;
          z-index: 30;
          min-height: 4.4rem;
          padding: 0.35rem 0.55rem calc(0.35rem + env(safe-area-inset-bottom));
          background: color-mix(in srgb, var(--pfx-surface) 94%, transparent);
          border-top: 1px solid var(--pfx-border);
          backdrop-filter: blur(18px);
          box-shadow: 0 -18px 40px -34px rgba(15, 23, 42, 0.55);
        }

        #app-shell .app-shell-bottom-link {
          min-width: 0;
          min-height: 3.45rem;
          border-radius: var(--pfx-radius);
          color: var(--pfx-muted);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.2rem;
          font-size: 0.72rem;
          font-weight: 700;
        }

        #app-shell .app-shell-bottom-link:hover {
          text-decoration: none;
          background: var(--pfx-accent-faint);
        }

        #app-shell .app-shell-bottom-link.is-active {
          color: var(--pfx-accent);
          background: var(--pfx-accent-faint);
        }

        #app-shell .app-shell-bottom-icon {
          font-size: 0.8rem;
          line-height: 1;
          font-weight: 850;
        }

        @media (max-width: 1100px) {
          #app-shell .app-shell-workspace-grid {
            grid-template-columns: minmax(0, 1fr);
          }

          #app-shell .app-shell-stat-grid {
            grid-template-columns: repeat(2, minmax(0, 1fr));
          }

          #app-shell .app-shell-section-card--compact {
            max-width: none;
          }
        }

        @media (max-width: 760px) {
          #app-shell .app-shell-mobile-header {
            display: flex;
          }

          #app-shell .app-shell-topbar {
            display: none;
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
            padding: 1rem 1rem 5.5rem;
          }

          #app-shell .app-shell-page-header {
            display: block;
          }

          #app-shell .app-shell-action-row {
            display: grid;
            grid-template-columns: 1fr;
          }

          #app-shell .app-shell-action-row-left,
          #app-shell .app-shell-action-row-right {
            width: 100%;
          }

          #app-shell .app-shell-action-row-right {
            order: -1;
          }

          #app-shell .app-shell-action-row-right .app-shell-primary {
            width: 100%;
          }

          #app-shell .app-shell-search {
            max-width: none;
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

          #app-shell .app-shell-stat-grid {
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 0.65rem;
          }

          #app-shell .app-shell-stat-card {
            min-height: 4.15rem;
            padding: 0.72rem;
            gap: 0.55rem;
          }

          #app-shell .app-shell-stat-icon {
            width: 1.9rem;
            height: 1.9rem;
            font-size: 0.68rem;
          }

          #app-shell .app-shell-stat-label,
          #app-shell .app-shell-stat-hint {
            font-size: 0.72rem;
          }

          #app-shell .app-shell-stat-value {
            font-size: 1.08rem;
          }

          #app-shell table {
            min-width: 34rem;
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

          #app-shell .app-shell-bottom-nav {
            display: grid;
            grid-template-columns: repeat(4, minmax(0, 1fr));
            gap: 0.2rem;
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

        @media (max-width: 340px) {
          #app-shell .app-shell-stat-grid {
            grid-template-columns: 1fr;
          }
        }
      </style>

      <header class="app-shell-mobile-header" aria-label="Mobile application header">
        <a href="/" class="app-shell-mobile-brand" aria-label="Portfolixir">
          <img
            class="app-shell-mobile-logo"
            src="/images/logo-mark.svg"
            alt="Portfolixir"
          />
          <span class="app-shell-mobile-brand-text">Portfolixir</span>
          <span class="app-shell-visually-hidden">Portfolixir</span>
        </a>
        <div class="app-shell-mobile-actions">
          <.language_toggle
            id="mobile-language-toggle"
            current_path={@current_path}
            locale={@locale}
            de_id="mobile-locale-de"
            en_id="mobile-locale-en"
          />
          <button
            id="mobile-nav-toggle"
            class="app-shell-icon-button"
            type="button"
            aria-label={gettext("Open navigation")}
            aria-expanded="false"
            aria-controls="app-shell-mobile-drawer"
            title={gettext("Open navigation")}
          >
            ☰
          </button>
        </div>
      </header>

      <div class="app-shell-layout">
        <aside id="app-shell-mobile-drawer" class="app-shell-sidebar" aria-label={gettext("Primary navigation")}>
          <div class="app-shell-sidebar-top">
            <a href="/" class="app-shell-brand" aria-label="Portfolixir">
              <img
                id="app-shell-brand-mark"
                class="app-shell-logo-mark"
                src="/images/logo-mark.svg"
                alt="Portfolixir"
              />
              <span class="app-shell-brand-text">Portfolixir</span>
              <span class="app-shell-visually-hidden">Portfolixir</span>
            </a>
          </div>

          <nav class="app-shell-sidebar-nav" aria-label={gettext("Main navigation")}>
            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Dashboard") %></p>
              <a
                id="nav-dashboard"
                href="/"
                aria-label={gettext("Dashboard")}
                title={gettext("Dashboard")}
                class={nav_link_class(@current_path, "/")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">DB</span>
                <span class="app-shell-nav-label"><%= gettext("Dashboard") %></span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Securities") %></p>
              <a
                id="nav-securities"
                href="/securities"
                aria-label={gettext("All Securities")}
                title={gettext("All Securities")}
                class={nav_link_class(@current_path, "/securities")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">SEC</span>
                <span class="app-shell-nav-label"><%= gettext("All Securities") %></span>
              </a>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label={gettext("Watchlist")}
                aria-disabled="true"
                title={gettext("Coming soon")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">W</span>
                <span class="app-shell-nav-label"><%= gettext("Watchlist") %></span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Master data") %></p>
              <a
                href="/accounts"
                aria-label={gettext("Accounts")}
                title={gettext("Accounts")}
                class={nav_link_class(@current_path, "/accounts")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">ACC</span>
                <span class="app-shell-nav-label"><%= gettext("Accounts") %></span>
              </a>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label={gettext("Securities accounts")}
                aria-disabled="true"
                title={gettext("Coming soon")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">SA</span>
                <span class="app-shell-nav-label"><%= gettext("Securities accounts") %></span>
              </span>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label={gettext("Deposit accounts")}
                aria-disabled="true"
                title={gettext("Coming soon")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">DA</span>
                <span class="app-shell-nav-label"><%= gettext("Deposit accounts") %></span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Ledger") %></p>
              <a
                id="nav-transactions"
                href="/transactions"
                aria-label={gettext("Transactions")}
                title={gettext("Transactions")}
                class={nav_link_class(@current_path, "/transactions")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">TX</span>
                <span class="app-shell-nav-label"><%= gettext("Transactions") %></span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Classifications") %></p>
              <a
                id="nav-categories"
                href="/taxonomies"
                aria-label={gettext("Categories")}
                title={gettext("Categories")}
                class={nav_link_class(@current_path, "/taxonomies")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">CL</span>
                <span class="app-shell-nav-label"><%= gettext("Categories") %></span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Reports") %></p>
              <a
                id="nav-reports"
                href="/reports/fund-allocations"
                aria-label={gettext("Fund allocations")}
                title={gettext("Fund allocations")}
                class={nav_link_class(@current_path, "/reports/fund-allocations")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">HD</span>
                <span class="app-shell-nav-label"><%= gettext("Fund allocations") %></span>
              </a>
              <span
                class="app-shell-nav-link is-disabled"
                aria-label={gettext("Performance")}
                aria-disabled="true"
                title={gettext("Coming soon")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">PF</span>
                <span class="app-shell-nav-label"><%= gettext("Performance") %></span>
              </span>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Experimental") %></p>
              <a
                id="nav-imports"
                href="/imports"
                aria-label={gettext("Experimental imports")}
                title={gettext("Experimental imports")}
                class={imports_nav_link_class(@current_path)}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">IM</span>
                <span class="app-shell-nav-label"><%= gettext("Imports (experimental)") %></span>
              </a>
            </div>

            <div class="app-shell-nav-group">
              <p class="app-shell-nav-group-title"><%= gettext("Settings") %></p>
              <span
                id="nav-settings"
                class="app-shell-nav-link is-disabled"
                aria-label={gettext("Settings")}
                aria-disabled="true"
                title={gettext("Coming soon")}
              >
                <span class="app-shell-nav-icon" aria-hidden="true">SET</span>
                <span class="app-shell-nav-label"><%= gettext("Settings") %></span>
              </span>
            </div>
          </nav>

          <div class="app-shell-bottom-spacer"></div>
        </aside>

        <div class="app-shell-main-column">
          <header class="app-shell-topbar" aria-label={gettext("Workspace header")}>
            <div class="app-shell-topbar-left">
              <button
                id="sidebar-toggle"
                class="app-shell-icon-button"
                type="button"
                aria-label={gettext("Collapse sidebar")}
                aria-expanded="true"
                title={gettext("Collapse sidebar")}
              >
                ☰
              </button>
              <nav class="app-shell-breadcrumb" aria-label={gettext("Breadcrumb")}>
                <span><%= section_label(@current_path) %></span>
                <span class="app-shell-breadcrumb-separator" aria-hidden="true">›</span>
                <span class="app-shell-breadcrumb-current"><%= page_label(@current_path) %></span>
              </nav>
            </div>

            <div class="app-shell-topbar-actions">
              <.language_toggle
                id="language-toggle"
                current_path={@current_path}
                locale={@locale}
                de_id="locale-de"
                en_id="locale-en"
              />
              <button
                id="theme-toggle"
                class="app-shell-theme-toggle"
                type="button"
                title={gettext("Switch to dark mode")}
                aria-label={gettext("Switch to dark mode")}
                data-dark-label={gettext("Dark mode")}
                data-light-label={gettext("Light mode")}
                data-dark-title={gettext("Switch to dark mode")}
                data-light-title={gettext("Switch to light mode")}
              >
                <span class="app-shell-theme-icon" aria-hidden="true">D</span>
                <span class="app-shell-theme-label"><%= gettext("Dark mode") %></span>
              </button>
            </div>
          </header>

          <main class="app-shell-main">
            <div class="app-shell-main-inner">
              <section class="app-shell-content-card">
                <%= render_slot(@inner_block) %>
              </section>
            </div>
          </main>
        </div>
      </div>

      <nav class="app-shell-bottom-nav" aria-label="Mobile primary navigation">
        <a
          id="mobile-nav-dashboard"
          href="/"
          class={mobile_nav_link_class(@current_path, "/")}
        >
          <span class="app-shell-bottom-icon" aria-hidden="true">DB</span>
          <span><%= gettext("Dashboard") %></span>
        </a>
        <a
          id="mobile-nav-securities"
          href="/securities"
          class={mobile_nav_link_class(@current_path, "/securities")}
        >
          <span class="app-shell-bottom-icon" aria-hidden="true">SEC</span>
          <span><%= gettext("Securities") %></span>
        </a>
        <a
          id="mobile-nav-transactions"
          href="/transactions"
          class={mobile_nav_link_class(@current_path, "/transactions")}
        >
          <span class="app-shell-bottom-icon" aria-hidden="true">TX</span>
          <span><%= gettext("Transactions") %></span>
        </a>
        <a
          id="mobile-nav-categories"
          href="/taxonomies"
          class={mobile_nav_link_class(@current_path, "/taxonomies")}
        >
          <span class="app-shell-bottom-icon" aria-hidden="true">CL</span>
          <span><%= gettext("Categories") %></span>
        </a>
      </nav>

      <script id="theme-toggle-script">
        (function () {
          var themeKey = "portfolixir-theme";
          var sidebarStateKey = "portfolixir.sidebarCollapsed";
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
              themeLabel.textContent = isDark ? toggle.dataset.lightLabel : toggle.dataset.darkLabel;
            }

            if (themeIcon) {
              themeIcon.textContent = isDark ? "L" : "D";
            }

            if (toggle) {
              toggle.setAttribute("title", isDark ? toggle.dataset.lightTitle : toggle.dataset.darkTitle);
              toggle.setAttribute("aria-label", isDark ? toggle.dataset.lightTitle : toggle.dataset.darkTitle);
            }

            try {
              localStorage.setItem(themeKey, resolvedTheme);
            } catch (_error) {}
          }

          function applySidebarState(isCollapsed) {
            shell.setAttribute("data-sidebar-collapsed", isCollapsed ? "true" : "false");
            if (sidebarToggle) {
              sidebarToggle.setAttribute(
                "aria-expanded",
                isCollapsed ? "false" : "true"
              );
              sidebarToggle.setAttribute("title", isCollapsed ? "<%= gettext("Expand sidebar") %>" : "<%= gettext("Collapse sidebar") %>");
              sidebarToggle.setAttribute("aria-label", isCollapsed ? "<%= gettext("Expand sidebar") %>" : "<%= gettext("Collapse sidebar") %>");
            }

            try {
              localStorage.setItem(sidebarStateKey, isCollapsed ? "true" : "false");
            } catch (_error) {}
          }

          function applyMobileNavState(isOpen) {
            shell.setAttribute("data-mobile-nav-open", isOpen ? "true" : "false");
            if (mobileNavToggle) {
              mobileNavToggle.setAttribute("aria-expanded", isOpen ? "true" : "false");
              mobileNavToggle.setAttribute("title", isOpen ? "<%= gettext("Close navigation") %>" : "<%= gettext("Open navigation") %>");
              mobileNavToggle.setAttribute("aria-label", isOpen ? "<%= gettext("Close navigation") %>" : "<%= gettext("Open navigation") %>");
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
              return localStorage.getItem(sidebarStateKey) === "true";
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

  attr(:id, :string, required: true)
  attr(:current_path, :string, required: true)
  attr(:locale, :string, required: true)
  attr(:de_id, :string, required: true)
  attr(:en_id, :string, required: true)

  defp language_toggle(assigns) do
    ~H"""
    <div id={@id} class="app-shell-language-toggle" aria-label={gettext("Language")}>
      <a
        id={@de_id}
        href={locale_path(@current_path, "de")}
        class={language_link_class(@locale, "de")}
        aria-current={if @locale == "de", do: "true", else: "false"}
      >
        DE
      </a>
      <a
        id={@en_id}
        href={locale_path(@current_path, "en")}
        class={language_link_class(@locale, "en")}
        aria-current={if @locale == "en", do: "true", else: "false"}
      >
        EN
      </a>
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

  defp imports_nav_link_class("/imports"), do: "app-shell-nav-link is-active"
  defp imports_nav_link_class("/imports/" <> _), do: "app-shell-nav-link is-active"
  defp imports_nav_link_class(_path), do: "app-shell-nav-link"

  defp mobile_nav_link_class(current_path, path, root_active? \\ false) do
    if current_path == path || (root_active? && current_path == "/") do
      "app-shell-bottom-link is-active"
    else
      "app-shell-bottom-link"
    end
  end

  defp language_link_class(current_locale, locale) do
    if current_locale == locale do
      "app-shell-language-link is-active"
    else
      "app-shell-language-link"
    end
  end

  defp locale_path(path, locale), do: "#{path}?locale=#{locale}"

  defp section_label("/"), do: gettext("Dashboard")
  defp section_label("/dashboard"), do: gettext("Dashboard")
  defp section_label("/documents/new"), do: gettext("Experimental")
  defp section_label("/fund-documents/" <> _), do: gettext("Experimental")
  defp section_label("/imports"), do: gettext("Experimental")
  defp section_label("/imports/" <> _), do: gettext("Experimental")
  defp section_label("/reports/" <> _), do: gettext("Reports")
  defp section_label("/accounts"), do: gettext("Master data")
  defp section_label("/transactions"), do: gettext("Ledger")
  defp section_label("/taxonomies"), do: gettext("Classifications")
  defp section_label(_path), do: gettext("Securities")

  defp page_label("/"), do: gettext("Dashboard")
  defp page_label("/dashboard"), do: gettext("Dashboard")
  defp page_label("/documents/new"), do: gettext("Factsheet document")
  defp page_label("/fund-documents/" <> _), do: gettext("Factsheet allocation review")
  defp page_label("/imports"), do: gettext("Imports")
  defp page_label("/imports/conflicts"), do: gettext("Import conflicts")
  defp page_label("/imports/raw-items/" <> _), do: gettext("Raw import item review")
  defp page_label("/reports/" <> _), do: gettext("Fund allocation report")
  defp page_label("/accounts"), do: gettext("Accounts Overview")
  defp page_label("/transactions"), do: gettext("Transactions")
  defp page_label("/taxonomies"), do: gettext("Classifications")
  defp page_label(_path), do: gettext("All Securities")
end
