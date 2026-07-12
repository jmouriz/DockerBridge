(function () {
  "use strict";

  var translations = window.DockerBridgeI18n || {};
  var supportedLanguages = ["en", "es", "pt"];
  var languageStorageKey = "dockerbridge-language";
  var themeStorageKey = "dockerbridge-theme";

  function safeStorageGet(key) {
    try {
      return localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function safeStorageSet(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (_) {
      // Preferences continue to work for the current page without persistence.
    }
  }

  function normalizeLanguage(value) {
    var normalized = String(value || "").toLowerCase();
    return supportedLanguages.find(function (language) {
      return normalized === language || normalized.indexOf(language + "-") === 0;
    }) || null;
  }

  function browserLanguage() {
    var candidates = navigator.languages || [navigator.language];
    for (var index = 0; index < candidates.length; index += 1) {
      var language = normalizeLanguage(candidates[index]);
      if (language) {
        return language;
      }
    }
    return "en";
  }

  var queryLanguage = normalizeLanguage(new URL(window.location.href).searchParams.get("lang"));
  var storedLanguage = normalizeLanguage(safeStorageGet(languageStorageKey));
  var activeLanguage = queryLanguage || storedLanguage || browserLanguage();

  function translate(key) {
    var active = translations[activeLanguage] || translations.en || {};
    var fallback = translations.en || {};
    return active[key] || fallback[key] || key;
  }

  function setMeta(selector, value) {
    var element = document.querySelector(selector);
    if (element) {
      element.setAttribute("content", value);
    }
  }

  function applyMetadata() {
    var page = document.documentElement.getAttribute("data-page");
    var isPrivacy = page === "privacy";
    var title = translate(isPrivacy ? "meta.privacyTitle" : "meta.homeTitle");
    var description = translate(isPrivacy ? "meta.privacyDescription" : "meta.homeDescription");
    var shareDescription = isPrivacy ? description : translate("meta.homeShareDescription");

    document.title = title;
    setMeta('meta[name="description"]', description);
    setMeta('meta[property="og:title"]', title);
    setMeta('meta[property="og:description"]', shareDescription);
    setMeta('meta[property="og:image:alt"]', translate("meta.ogImageAlt"));
    setMeta('meta[name="twitter:title"]', title);
    setMeta('meta[name="twitter:description"]', shareDescription);
  }

  function applyTranslations() {
    document.documentElement.lang = activeLanguage;

    document.querySelectorAll("[data-i18n]").forEach(function (element) {
      element.textContent = translate(element.getAttribute("data-i18n"));
    });

    [
      ["data-i18n-aria-label", "aria-label"],
      ["data-i18n-title", "title"],
      ["data-i18n-alt", "alt"]
    ].forEach(function (mapping) {
      document.querySelectorAll("[" + mapping[0] + "]").forEach(function (element) {
        element.setAttribute(mapping[1], translate(element.getAttribute(mapping[0])));
      });
    });

    var languageSelect = document.getElementById("language-select");
    if (languageSelect) {
      languageSelect.value = activeLanguage;
    }

    applyMetadata();
    updateOpenScreenshot();
  }

  function selectLanguage(language, persist) {
    var normalized = normalizeLanguage(language) || "en";
    activeLanguage = normalized;

    if (persist) {
      safeStorageSet(languageStorageKey, normalized);
      var url = new URL(window.location.href);
      url.searchParams.set("lang", normalized);
      history.replaceState(null, "", url.pathname + url.search + url.hash);
    }

    applyTranslations();
  }

  var languageSelect = document.getElementById("language-select");
  if (languageSelect) {
    languageSelect.addEventListener("change", function (event) {
      selectLanguage(event.target.value, true);
    });
  }

  function preferredTheme() {
    var stored = safeStorageGet(themeStorageKey);
    return stored === "light" || stored === "dark" || stored === "system" ? stored : "system";
  }

  function updateThemeColor() {
    var explicitTheme = document.documentElement.getAttribute("data-theme");
    var dark = explicitTheme === "dark" || (!explicitTheme && window.matchMedia("(prefers-color-scheme: dark)").matches);
    setMeta('meta[name="theme-color"]', dark ? "#08111f" : "#f5f7fb");
  }

  function applyTheme(theme, persist) {
    var normalized = theme === "light" || theme === "dark" ? theme : "system";
    if (normalized === "system") {
      document.documentElement.removeAttribute("data-theme");
    } else {
      document.documentElement.setAttribute("data-theme", normalized);
    }

    var themeSelect = document.getElementById("theme-select");
    if (themeSelect) {
      themeSelect.value = normalized;
    }

    if (persist) {
      safeStorageSet(themeStorageKey, normalized);
    }
    updateThemeColor();
  }

  var themeSelect = document.getElementById("theme-select");
  if (themeSelect) {
    themeSelect.addEventListener("change", function (event) {
      applyTheme(event.target.value, true);
    });
  }

  var systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
  systemTheme.addEventListener("change", function () {
    if (preferredTheme() === "system") {
      updateThemeColor();
    }
  });

  document.querySelectorAll("[data-current-year]").forEach(function (element) {
    element.textContent = String(new Date().getFullYear());
  });

  var dialog = document.getElementById("screenshot-dialog");
  var screenshotButtons = Array.prototype.slice.call(document.querySelectorAll("[data-screenshot-index]"));
  var activeScreenshotIndex = 0;
  var lastScreenshotTrigger = null;

  function screenshotDetails(index) {
    var button = screenshotButtons[index];
    if (!button) {
      return null;
    }
    var image = button.querySelector("img");
    var figure = button.closest("figure");
    var caption = figure ? figure.querySelector("figcaption") : null;
    return {
      src: image ? image.getAttribute("src") : "",
      altKey: image ? image.getAttribute("data-i18n-alt") : "",
      captionKey: caption ? caption.getAttribute("data-i18n") : ""
    };
  }

  function updateOpenScreenshot() {
    if (!dialog || !dialog.open || screenshotButtons.length === 0) {
      return;
    }
    var details = screenshotDetails(activeScreenshotIndex);
    if (!details) {
      return;
    }
    var image = dialog.querySelector("[data-lightbox-image]");
    var caption = dialog.querySelector("[data-lightbox-caption]");
    image.setAttribute("src", details.src);
    image.setAttribute("alt", translate(details.altKey));
    caption.textContent = translate(details.captionKey);
  }

  function openScreenshot(index, trigger) {
    if (!dialog || typeof dialog.showModal !== "function") {
      return;
    }
    activeScreenshotIndex = index;
    lastScreenshotTrigger = trigger;
    dialog.showModal();
    document.body.classList.add("dialog-open");
    updateOpenScreenshot();
  }

  function closeScreenshot() {
    if (dialog && dialog.open) {
      dialog.close();
    }
  }

  function moveScreenshot(direction) {
    if (screenshotButtons.length === 0) {
      return;
    }
    activeScreenshotIndex = (activeScreenshotIndex + direction + screenshotButtons.length) % screenshotButtons.length;
    updateOpenScreenshot();
  }

  screenshotButtons.forEach(function (button, index) {
    button.addEventListener("click", function () {
      openScreenshot(index, button);
    });
  });

  if (dialog) {
    var closeButton = dialog.querySelector("[data-lightbox-close]");
    var previousButton = dialog.querySelector("[data-lightbox-previous]");
    var nextButton = dialog.querySelector("[data-lightbox-next]");

    closeButton.addEventListener("click", closeScreenshot);
    previousButton.addEventListener("click", function () { moveScreenshot(-1); });
    nextButton.addEventListener("click", function () { moveScreenshot(1); });

    dialog.addEventListener("click", function (event) {
      if (event.target === dialog) {
        closeScreenshot();
      }
    });

    dialog.addEventListener("close", function () {
      document.body.classList.remove("dialog-open");
      if (lastScreenshotTrigger) {
        lastScreenshotTrigger.focus();
      }
    });

    dialog.addEventListener("keydown", function (event) {
      if (event.key === "ArrowLeft") {
        moveScreenshot(-1);
      } else if (event.key === "ArrowRight") {
        moveScreenshot(1);
      }
    });
  }

  applyTheme(preferredTheme(), false);
  selectLanguage(activeLanguage, false);
})();
