// The stored theme and accent, applied before the stylesheet paints: the
// root layout runs this same code inline under its nonce; a page the static
// policy serves (the error page) loads it from here.
(function () {
  var mode = window.localStorage && window.localStorage.getItem("portfolixir-theme");
  if (["system", "light", "dark"].indexOf(mode) === -1) {
    mode = "system";
  }
  var accent = window.localStorage && window.localStorage.getItem("portfolixir-accent");
  if (["violet", "teal", "coral"].indexOf(accent) === -1) {
    accent = "violet";
  }
  document.documentElement.dataset.theme = mode;
  document.documentElement.dataset.accent = accent;
})();
