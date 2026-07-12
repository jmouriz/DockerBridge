(function () {
  try {
    var theme = localStorage.getItem("dockerbridge-theme");
    if (theme === "light" || theme === "dark") {
      document.documentElement.setAttribute("data-theme", theme);
    }
  } catch (_) {
    // Browser preferences remain the fallback when storage is unavailable.
  }
})();
