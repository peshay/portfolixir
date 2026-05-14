<link rel="stylesheet" href="styles.css">

<main class="docs-shell">
  <header class="docs-hero">
    <img src="assets/logo.svg" alt="" class="docs-logo">
    <div>
      <p class="docs-kicker">Portfolixir</p>
      <h1>Product documentation</h1>
      <p>
        Portfolixir is a local-first Phoenix application for securities tracking:
        audited manual transactions, derived holdings, and stored quote history.
      </p>
    </div>
  </header>

  <nav class="docs-nav">
    <a class="docs-nav-link" href="product-documentation.md">Product documentation</a>
    <a class="docs-nav-link" href="home-deployment.md">Home Deployment</a>
    <a class="docs-nav-link" href="development/story-workflow.md">Story Workflow</a>
    <a class="docs-nav-link" href="development/guide.md">Development Guide</a>
  </nav>

  <section class="docs-panel">
    <h2>Current Scope</h2>
    <p>
      The application is intentionally scoped as a reboot foundation for one local
      portfolio workflow. The aim is to stay small, auditable, and deterministic
      before adding larger features in future epics.
    </p>
    <p>
      Open the full product walkthrough in <a href="product-documentation.md">Product documentation</a>
      and the implementation-focused notes in the development section.
    </p>
  </section>

  <section class="docs-grid">
    <article class="docs-card">
      <h2>Product Workflow</h2>
      <ol>
        <li>Create securities.</li>
        <li>Create one portfolio.</li>
        <li>Link one depot to one cash account.</li>
        <li>Record manual buy and sell transactions.</li>
        <li>Review current holdings.</li>
        <li>Store and display quote history.</li>
      </ol>
    </article>

    <article class="docs-card">
      <h2>Product Documentation</h2>
      <p>
        The focus is on manual, local records only. Features are documented with
        clear behavior, formulas, and limits so scope stays testable and
        predictable.
      </p>
    </article>

    <article class="docs-card">
      <h2>Language and Theme</h2>
      <p>
        The UI supports System, Light, and Dark themes, and EN/DE language
        switching. Language and themes are runtime preferences and do not affect
        persisted domain data.
      </p>
    </article>

    <article class="docs-card">
      <h2>Development</h2>
      <p>
        Start with the development guides when you want local checks, story workflow
        conventions, and scope rules before adding or changing behavior.
      </p>
    </article>
  </section>
</main>
