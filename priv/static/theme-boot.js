// The stored theme and accent, applied before the stylesheet paints: the
// root layout runs this same code inline under its nonce; a page the static
// policy serves (the error page) loads it from here. A browser that blocks
// site data throws on the first read of window.localStorage, so each read
// is in try/catch and the page comes up in the system theme and the
// default accent (#1439).
(function () {
  var mode = null;
  var accent = null;
  try { mode = window.localStorage && window.localStorage.getItem("portfolixir-theme"); } catch (_) {}
  if (["system", "light", "dark"].indexOf(mode) === -1) {
    mode = "system";
  }
  try { accent = window.localStorage && window.localStorage.getItem("portfolixir-accent"); } catch (_) {}
  if (["violet", "teal", "coral"].indexOf(accent) === -1) {
    accent = "violet";
  }
  document.documentElement.dataset.theme = mode;
  document.documentElement.dataset.accent = accent;
})();
