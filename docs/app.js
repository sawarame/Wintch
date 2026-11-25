/**
 * Wintch 紹介ページ メインスクリプト
 * - 5 言語切替・URL パラメータ・ブラウザ言語自動判定
 * - システム／ライト／ダーク テーマ切替
 * - GitHub Releases API からの最新バージョン・DMG ダウンロード URL 動的取得（フォールバック付き）
 * - インタラクティブ Showcase（通常スイッチャー 3 形式＋グルーピング＋スピナー終了／検索ランチャー／4 メニュー設定画面）
 * - ワンクリック コマンドコピー機能
 */
(function () {
  "use strict";

  const I18N = window.WintchI18n;
  if (!I18N) return;

  const RELEASES_API_URL = "https://api.github.com/repos/sawarame/Wintch/releases/latest";
  const RELEASES_PAGE_URL = "https://github.com/sawarame/Wintch/releases/latest";
  const FALLBACK_VERSION = "v0.4.3";
  const VERSION_CACHE_KEY = "wintch-docs-latest-release";
  const VERSION_CACHE_TTL_MS = 10 * 60 * 1000;

  /** デモ用ウィンドウデータ（MRU 順） */
  const INITIAL_WINDOWS = [
    {
      id: "w1",
      app: "Ghostty",
      code: "G",
      badgeClass: "badge-ghostty",
      thumbClass: "thumb-terminal",
      title: "~/dev/Wintch — swift test",
    },
    {
      id: "w2",
      app: "Safari",
      code: "S",
      badgeClass: "badge-safari",
      thumbClass: "thumb-browser",
      title: "Wintch — GitHub Releases",
    },
    {
      id: "w3",
      app: "Xcode",
      code: "X",
      badgeClass: "badge-xcode",
      thumbClass: "thumb-code",
      title: "SwitcherListView.swift — Wintch",
    },
    {
      id: "w4",
      app: "Safari",
      code: "S",
      badgeClass: "badge-safari",
      thumbClass: "thumb-browser",
      title: "Apple Developer Documentation — AXUIElement",
    },
    {
      id: "w5",
      app: "Slack",
      code: "#",
      badgeClass: "badge-slack",
      thumbClass: "thumb-chat",
      title: "#dev-macos — Release Notes",
    },
    {
      id: "w6",
      app: "Finder",
      code: "F",
      badgeClass: "badge-finder",
      thumbClass: "thumb-finder",
      title: "Applications",
    },
  ];

  /** 検索ランチャー用の起動可能インストール済みアプリ候補 */
  const LAUNCHABLE_APPS = [
    {
      id: "app-notes",
      names: { en: "Notes", ja: "メモ", "zh-Hans": "备忘录", "zh-Hant": "備忘錄", ko: "메모" },
      alias: "Notes",
      code: "N",
      badgeClass: "badge-notes",
    },
    {
      id: "app-settings",
      names: {
        en: "System Settings",
        ja: "システム設定",
        "zh-Hans": "系统设置",
        "zh-Hant": "系統設定",
        ko: "시스템 설정",
      },
      alias: "System Settings",
      code: "⚙",
      badgeClass: "badge-settings",
    },
    {
      id: "app-calc",
      names: { en: "Calculator", ja: "計算機", "zh-Hans": "计算器", "zh-Hant": "計算機", ko: "계산기" },
      alias: "Calculator",
      code: "=",
      badgeClass: "badge-calc",
    },
    {
      id: "app-finder",
      names: { en: "Finder", ja: "Finder", "zh-Hans": "访达", "zh-Hant": "Finder", ko: "Finder" },
      alias: "Finder",
      code: "F",
      badgeClass: "badge-finder",
    },
    {
      id: "app-safari",
      names: { en: "Safari", ja: "Safari", "zh-Hans": "Safari 浏览器", "zh-Hant": "Safari", ko: "Safari" },
      alias: "Safari",
      code: "S",
      badgeClass: "badge-safari",
    },
  ];

  /** アプリケーション全体の状態 */
  const state = {
    locale: I18N.resolveInitialLocale(),
    themeChoice: loadThemeChoice(),
    releaseVersion: FALLBACK_VERSION,
    downloadUrl: RELEASES_PAGE_URL,
    activeTab: "switcher",
    // 通常スイッチャーデモ状態
    switcherStyle: "list", // "list" | "icon" | "capture"
    switcherGrouped: true,
    windows: INITIAL_WINDOWS.map(cloneObject),
    selectedIndex: 1, // 初期選択は MRU 2 番目
    closingId: null,
    // 検索ランチャーデモ状態
    launcherStyle: "list", // "list" | "capture"
    launcherGrouped: true,
    launcherQuery: "note",
    launcherSelectedIndex: 0,
    // 設定画面デモ状態
    settingsTab: "general", // "general" | "switcher" | "launcher" | "system"
  };

  /** 単純オブジェクトを浅く複製する */
  function cloneObject(obj) {
    return Object.assign({}, obj);
  }

  /**
   * 現在の言語に対応する翻訳文字列を取得する
   * @param {string} key 翻訳キー
   * @returns {string} ローカライズ文字列
   */
  function t(key) {
    const dict = I18N.MESSAGES[state.locale] || I18N.MESSAGES.en;
    if (Object.prototype.hasOwnProperty.call(dict, key)) return dict[key];
    return I18N.MESSAGES.en[key] || key;
  }

  /** HTML 特殊文字をエスケープする */
  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  /* ========================================================================
     1. テーマ管理（system / light / dark）
     ======================================================================== */

  function loadThemeChoice() {
    try {
      const saved = localStorage.getItem("wintch-docs-theme");
      if (saved === "light" || saved === "dark" || saved === "system") return saved;
    } catch (_err) {
      // 無視
    }
    return "system";
  }

  function applyTheme(choice) {
    state.themeChoice = choice;
    const prefersDark =
      window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    const resolved = choice === "system" ? (prefersDark ? "dark" : "light") : choice;
    document.documentElement.setAttribute("data-theme-choice", choice);
    document.documentElement.setAttribute("data-theme", resolved);

    try {
      localStorage.setItem("wintch-docs-theme", choice);
    } catch (_err) {
      // localStorage 無効環境では保存をスキップ
    }
    updateThemeButtonTitle();
  }

  function updateThemeButtonTitle() {
    const btn = document.getElementById("theme-toggle");
    if (!btn) return;
    const labelKey =
      state.themeChoice === "dark"
        ? "common.themeDark"
        : state.themeChoice === "light"
          ? "common.themeLight"
          : "common.themeSystem";
    const label = t(labelKey);
    btn.setAttribute("title", label);
    btn.setAttribute("aria-label", label);
  }

  /* ========================================================================
     2. 多言語反映・バージョン表記更新
     ======================================================================== */

  function applyLocale(locale, persist) {
    const normalized = I18N.normalizeLocale(locale) || "en";
    state.locale = normalized;
    document.documentElement.lang = normalized;

    if (persist) {
      try {
        localStorage.setItem("wintch-docs-locale", normalized);
      } catch (_err) {
        // 無視
      }
      try {
        const url = new URL(window.location.href);
        url.searchParams.set("lang", normalized);
        window.history.replaceState(null, "", url.toString());
      } catch (_err) {
        // file:// 等では無視
      }
    }

    // ページタイトル・meta description を更新
    document.title = t("meta.title");
    const descMeta = document.querySelector('meta[name="description"]');
    if (descMeta) descMeta.setAttribute("content", t("meta.description"));

    // すべての data-i18n 要素を更新
    const nodes = document.querySelectorAll("[data-i18n]");
    for (let i = 0; i < nodes.length; i += 1) {
      const key = nodes[i].getAttribute("data-i18n");
      nodes[i].textContent = t(key);
    }

    // 言語ドロップダウン表示を更新
    const labelEl = document.getElementById("current-locale-label");
    if (labelEl) {
      labelEl.textContent = I18N.LOCALE_LABELS[normalized] || "English";
    }
    const options = document.querySelectorAll(".locale-option[data-locale]");
    for (let i = 0; i < options.length; i += 1) {
      const isCurrent = options[i].getAttribute("data-locale") === normalized;
      options[i].setAttribute("aria-checked", isCurrent ? "true" : "false");
    }

    updateThemeButtonTitle();
    updateVersionUI();
    initCopyButtonIcons();
    renderShowcase();
  }

  function updateVersionUI() {
    const versionNodes = document.querySelectorAll("[data-version-text]");
    for (let i = 0; i < versionNodes.length; i += 1) {
      versionNodes[i].textContent = state.releaseVersion;
    }

    const downloadLabels = document.querySelectorAll("[data-download-label]");
    const labelText = state.releaseVersion
      ? t("hero.downloadWithVersion").replace("{version}", state.releaseVersion)
      : t("hero.downloadFallback");
    for (let i = 0; i < downloadLabels.length; i += 1) {
      downloadLabels[i].textContent = labelText;
    }

    const downloadLinks = document.querySelectorAll("[data-download-link]");
    for (let i = 0; i < downloadLinks.length; i += 1) {
      downloadLinks[i].setAttribute("href", state.downloadUrl);
    }
  }

  /**
   * GitHub Releases API から最新安定版バージョンおよび DMG ダウンロード URL を取得する
   * レート制限回避のため sessionStorage に短時間キャッシュし、失敗時は安全にフォールバックする
   */
  async function fetchLatestRelease() {
    try {
      const cachedRaw = sessionStorage.getItem(VERSION_CACHE_KEY);
      if (cachedRaw) {
        const cached = JSON.parse(cachedRaw);
        if (cached && Date.now() - cached.fetchedAt < VERSION_CACHE_TTL_MS && cached.tagName) {
          state.releaseVersion = cached.tagName;
          state.downloadUrl = cached.downloadUrl || RELEASES_PAGE_URL;
          updateVersionUI();
          if (state.activeTab === "settings" && state.settingsTab === "system") {
            renderShowcase();
          }
          return;
        }
      }
    } catch (_err) {
      // キャッシュ読み取り不可時は直接取得する
    }

    try {
      const res = await fetch(RELEASES_API_URL, {
        headers: { Accept: "application/vnd.github+json" },
      });
      if (!res.ok) return;
      const data = await res.json();
      if (!data || !data.tag_name) return;

      const tagName = String(data.tag_name).trim();
      let downloadUrl =
        typeof data.html_url === "string" && data.html_url.startsWith("https://github.com/")
          ? data.html_url
          : RELEASES_PAGE_URL;

      // DMG アセットが存在すれば直接ダウンロード URL を優先する
      if (Array.isArray(data.assets)) {
        const dmgAsset = data.assets.find(function (asset) {
          return (
            asset &&
            typeof asset.name === "string" &&
            asset.name.endsWith(".dmg") &&
            typeof asset.browser_download_url === "string" &&
            asset.browser_download_url.startsWith("https://github.com/")
          );
        });
        if (dmgAsset) {
          downloadUrl = dmgAsset.browser_download_url;
        }
      }

      state.releaseVersion = tagName;
      state.downloadUrl = downloadUrl;
      updateVersionUI();
      if (state.activeTab === "settings" && state.settingsTab === "system") {
        renderShowcase();
      }

      try {
        sessionStorage.setItem(
          VERSION_CACHE_KEY,
          JSON.stringify({ tagName: tagName, downloadUrl: downloadUrl, fetchedAt: Date.now() })
        );
      } catch (_err) {
        // 無視
      }
    } catch (_err) {
      // オフラインや API エラー時はフォールバック表記を維持する
    }
  }

  /* ========================================================================
     3. コピーボタン制御
     ======================================================================== */

  const COPY_ICON_SVG =
    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
  const CHECK_ICON_SVG =
    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

  function initCopyButtonIcons() {
    const buttons = document.querySelectorAll("[data-copy]");
    for (let i = 0; i < buttons.length; i += 1) {
      const btn = buttons[i];
      const statusWrap = btn.querySelector(".copy-status-wrap");
      if (statusWrap && !btn.classList.contains("is-copied")) {
        statusWrap.innerHTML = COPY_ICON_SVG;
      }
      btn.setAttribute("title", t("common.copyCommand"));
      btn.setAttribute("aria-label", t("common.copyCommand") + ": " + btn.getAttribute("data-copy"));
    }
  }

  function copyTextToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      try {
        const area = document.createElement("textarea");
        area.value = text;
        area.setAttribute("readonly", "");
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.select();
        document.execCommand("copy");
        document.body.removeChild(area);
        resolve();
      } catch (err) {
        reject(err);
      }
    });
  }

  function handleCopyClick(btn) {
    const text = btn.getAttribute("data-copy");
    if (!text) return;
    copyTextToClipboard(text)
      .then(function () {
        btn.classList.add("is-copied");
        const statusWrap = btn.querySelector(".copy-status-wrap");
        if (statusWrap) statusWrap.innerHTML = CHECK_ICON_SVG;

        const live = document.getElementById("live-status");
        if (live) live.textContent = t("common.copied");

        window.setTimeout(function () {
          btn.classList.remove("is-copied");
          if (statusWrap) statusWrap.innerHTML = COPY_ICON_SVG;
        }, 1800);
      })
      .catch(function () {
        // クリップボード利用不可環境ではエラーを出さず終了する
      });
  }

  /* ========================================================================
     4. インタラクティブ Showcase ロジック（グルーピング・ファジー検索・描画）
     ======================================================================== */

  /** アプリ単位の安定グルーピング（初出アプリ順、各アプリ内は MRU 順維持） */
  function groupWindowsByApp(windows) {
    const groups = [];
    const indexByApp = Object.create(null);
    for (let i = 0; i < windows.length; i += 1) {
      const win = windows[i];
      if (indexByApp[win.app] === undefined) {
        indexByApp[win.app] = groups.length;
        groups.push({
          app: win.app,
          code: win.code,
          badgeClass: win.badgeClass,
          items: [],
        });
      }
      groups[indexByApp[win.app]].items.push(win);
    }
    return groups;
  }

  /** スペース区切り AND ファジー検索（サブシーケンス一致＋ハイライト位置算出） */
  function matchTokens(text, tokens) {
    const lower = text.toLowerCase();
    const matchedIndices = new Set();

    for (let tIdx = 0; tIdx < tokens.length; tIdx += 1) {
      const token = tokens[tIdx];
      // 連続部分一致を優先し、なければサブシーケンス一致を試す
      const directPos = lower.indexOf(token);
      if (directPos !== -1) {
        for (let k = 0; k < token.length; k += 1) {
          matchedIndices.add(directPos + k);
        }
        continue;
      }

      let cursor = 0;
      const positions = [];
      for (let c = 0; c < token.length; c += 1) {
        const found = lower.indexOf(token[c], cursor);
        if (found === -1) return null;
        positions.push(found);
        cursor = found + 1;
      }
      for (let p = 0; p < positions.length; p += 1) {
        matchedIndices.add(positions[p]);
      }
    }
    return matchedIndices;
  }

  /** 一致文字インデックスを <mark class="match-hl"> で装飾した HTML を返す */
  function highlightText(text, tokens) {
    if (!tokens || tokens.length === 0) return escapeHtml(text);
    const lower = text.toLowerCase();
    const highlights = new Set();

    for (let i = 0; i < tokens.length; i += 1) {
      const token = tokens[i];
      const directPos = lower.indexOf(token);
      if (directPos !== -1) {
        for (let k = 0; k < token.length; k += 1) highlights.add(directPos + k);
      } else {
        let cursor = 0;
        const pos = [];
        let ok = true;
        for (let c = 0; c < token.length; c += 1) {
          const found = lower.indexOf(token[c], cursor);
          if (found === -1) {
            ok = false;
            break;
          }
          pos.push(found);
          cursor = found + 1;
        }
        if (ok) {
          for (let p = 0; p < pos.length; p += 1) highlights.add(pos[p]);
        }
      }
    }

    let html = "";
    let inMark = false;
    for (let i = 0; i < text.length; i += 1) {
      const shouldMark = highlights.has(i);
      if (shouldMark && !inMark) {
        html += '<mark class="match-hl">';
        inMark = true;
      } else if (!shouldMark && inMark) {
        html += "</mark>";
        inMark = false;
      }
      html += escapeHtml(text[i]);
    }
    if (inMark) html += "</mark>";
    return html;
  }

  /** ウィンドウ用サムネイル HTML を生成する */
  function renderThumbHtml(win, mini) {
    const cls = mini ? "capture-thumb-box is-mini" : "capture-thumb-box";
    return (
      '<div class="' +
      cls +
      '" aria-hidden="true">' +
      '<div class="capture-thumb-header"><span class="capture-thumb-dot"></span><span class="capture-thumb-dot"></span><span class="capture-thumb-dot"></span></div>' +
      '<div class="capture-thumb-body ' +
      win.thumbClass +
      '">' +
      '<span class="thumb-bar-accent"></span>' +
      '<span class="thumb-bar-wide"></span>' +
      (mini ? "" : '<span class="thumb-bar-short"></span>') +
      "</div>" +
      "</div>"
    );
  }

  /** Showcase 全体を再描画する */
  function renderShowcase() {
    const stage = document.getElementById("showcase-stage");
    if (!stage) return;

    if (state.activeTab === "switcher") {
      stage.innerHTML = renderSwitcherStage();
    } else if (state.activeTab === "launcher") {
      stage.innerHTML = renderLauncherStage();
      bindLauncherInputEvents(stage);
    } else {
      stage.innerHTML = renderSettingsStage();
    }
  }

  /** 通常スイッチャーの現在表示順（グルーピング ON 時はグループ順）を返す */
  function getSwitcherOrderedWindows() {
    if (!state.switcherGrouped) return state.windows;
    const groups = groupWindowsByApp(state.windows);
    const ordered = [];
    for (let g = 0; g < groups.length; g += 1) {
      for (let i = 0; i < groups[g].items.length; i += 1) {
        ordered.push(groups[g].items[i]);
      }
    }
    return ordered;
  }

  function renderSwitcherStage() {
    const ordered = getSwitcherOrderedWindows();
    if (state.selectedIndex >= ordered.length) {
      state.selectedIndex = Math.max(0, ordered.length - 1);
    }

    const isWide =
      !state.switcherGrouped && (state.switcherStyle === "capture" || state.switcherStyle === "icon");
    const isModified = state.windows.length < INITIAL_WINDOWS.length;

    let panelBody = "";
    if (ordered.length === 0) {
      panelBody = '<div class="launcher-empty">' + escapeHtml(t("showcase.emptySwitcher")) + "</div>";
    } else if (!state.switcherGrouped && state.switcherStyle === "capture") {
      // グルーピング OFF のキャプチャ表示型（Windows Alt+Tab 風カードグリッド）
      panelBody = '<div class="capture-grid-stage">';
      for (let i = 0; i < ordered.length; i += 1) {
        const w = ordered[i];
        const isSel = i === state.selectedIndex;
        const isClosing = state.closingId === w.id;
        panelBody +=
          '<button type="button" class="capture-grid-card' +
          (isSel ? " is-selected" : "") +
          '" data-demo-select="' +
          i +
          '">' +
          '<div style="position:relative;">' +
          renderThumbHtml(w, false) +
          (isClosing ? '<div class="closing-overlay"><span class="closing-spinner"></span></div>' : "") +
          "</div>" +
          '<div class="capture-card-footer">' +
          '<span class="demo-app-badge is-sm ' +
          w.badgeClass +
          '">' +
          escapeHtml(w.code) +
          "</span>" +
          '<div class="capture-card-text">' +
          '<div class="capture-card-app">' +
          escapeHtml(w.app) +
          "</div>" +
          '<div class="capture-card-title">' +
          escapeHtml(w.title) +
          "</div>" +
          "</div>" +
          "</div>" +
          "</button>";
      }
      panelBody += "</div>";
    } else if (!state.switcherGrouped && state.switcherStyle === "icon") {
      // グルーピング OFF のアイコン型（macOS Command+Tab 風タイルグリッド）
      panelBody = '<div class="demo-icon-grid">';
      for (let i = 0; i < ordered.length; i += 1) {
        const w = ordered[i];
        const isSel = i === state.selectedIndex;
        const isClosing = state.closingId === w.id;
        panelBody +=
          '<button type="button" class="demo-icon-tile' +
          (isSel ? " is-selected" : "") +
          '" data-demo-select="' +
          i +
          '">' +
          '<div style="position:relative;">' +
          '<span class="demo-app-badge is-xl ' +
          w.badgeClass +
          '">' +
          escapeHtml(w.code) +
          "</span>" +
          (isClosing ? '<div class="closing-overlay"><span class="closing-spinner"></span></div>' : "") +
          "</div>" +
          '<div class="demo-icon-tile-app">' +
          escapeHtml(w.app) +
          "</div>" +
          '<div class="demo-icon-tile-title">' +
          escapeHtml(w.title) +
          "</div>" +
          "</button>";
      }
      panelBody += "</div>";
    } else if (state.switcherGrouped) {
      // グルーピング ON（リスト型／アイコン型／キャプチャ表示型いずれもアプリ見出し付き縦型リスト）
      const groups = groupWindowsByApp(state.windows);
      let flatIdx = 0;
      panelBody = '<div class="demo-list">';
      for (let g = 0; g < groups.length; g += 1) {
        if (g > 0) panelBody += '<div class="demo-group-divider"></div>';
        const grp = groups[g];
        panelBody +=
          '<div class="demo-group-header">' +
          '<span class="demo-app-badge is-sm ' +
          grp.badgeClass +
          '">' +
          escapeHtml(grp.code) +
          "</span>" +
          "<span>" +
          escapeHtml(grp.app) +
          "</span>" +
          "</div>";
        for (let i = 0; i < grp.items.length; i += 1) {
          const w = grp.items[i];
          const isSel = flatIdx === state.selectedIndex;
          const isClosing = state.closingId === w.id;
          let leading = "";
          if (state.switcherStyle === "capture") {
            leading = renderThumbHtml(w, true);
          } else if (state.switcherStyle === "icon") {
            leading =
              '<span class="demo-app-badge is-lg ' +
              w.badgeClass +
              '">' +
              escapeHtml(w.code) +
              "</span>";
          }
          panelBody +=
            '<button type="button" class="demo-row is-indented' +
            (isSel ? " is-selected" : "") +
            '" data-demo-select="' +
            flatIdx +
            '">' +
            leading +
            '<span class="demo-row-title" style="opacity:1;">' +
            escapeHtml(w.title) +
            "</span>" +
            (isClosing ? '<span class="closing-spinner" aria-hidden="true"></span>' : "") +
            "</button>";
          flatIdx += 1;
        }
      }
      panelBody += "</div>";
    } else {
      // グルーピング OFF のリスト型（フラット表示）
      panelBody = '<div class="demo-list">';
      for (let i = 0; i < ordered.length; i += 1) {
        const w = ordered[i];
        const isSel = i === state.selectedIndex;
        const isClosing = state.closingId === w.id;
        panelBody +=
          '<button type="button" class="demo-row' +
          (isSel ? " is-selected" : "") +
          '" data-demo-select="' +
          i +
          '">' +
          '<span class="demo-app-badge ' +
          w.badgeClass +
          '">' +
          escapeHtml(w.code) +
          "</span>" +
          '<span class="demo-row-app">' +
          escapeHtml(w.app) +
          "</span>" +
          '<span class="demo-row-title">' +
          escapeHtml(w.title) +
          "</span>" +
          (isClosing ? '<span class="closing-spinner" aria-hidden="true"></span>' : "") +
          "</button>";
      }
      panelBody += "</div>";
    }

    return (
      '<div class="panel-column' +
      (isWide ? " is-wide" : "") +
      '">' +
      '<div class="stage-toolbar">' +
      '<div class="style-toggle-bar" role="group">' +
      '<button type="button" class="style-toggle-btn' +
      (state.switcherStyle === "list" ? " is-active" : "") +
      '" data-switcher-style="list">' +
      escapeHtml(t("showcase.styleList")) +
      "</button>" +
      '<button type="button" class="style-toggle-btn' +
      (state.switcherStyle === "icon" ? " is-active" : "") +
      '" data-switcher-style="icon">' +
      escapeHtml(t("showcase.styleIcon")) +
      "</button>" +
      '<button type="button" class="style-toggle-btn' +
      (state.switcherStyle === "capture" ? " is-active" : "") +
      '" data-switcher-style="capture">' +
      escapeHtml(t("showcase.styleCapture")) +
      "</button>" +
      "</div>" +
      '<button type="button" class="group-toggle-btn' +
      (state.switcherGrouped ? " is-on" : "") +
      '" data-switcher-group-toggle>' +
      '<span class="group-toggle-dot" aria-hidden="true"></span>' +
      "<span>" +
      escapeHtml(t("showcase.groupByApp")) +
      "</span>" +
      "</button>" +
      "</div>" +
      '<div class="wintch-panel">' +
      panelBody +
      "</div>" +
      '<div class="demo-controls">' +
      '<button type="button" class="demo-control-btn" data-demo-action="prev"' +
      (ordered.length <= 1 ? " disabled" : "") +
      ">" +
      escapeHtml(t("showcase.prev")) +
      " <kbd>⌥⇧⇥</kbd></button>" +
      '<button type="button" class="demo-control-btn" data-demo-action="next"' +
      (ordered.length <= 1 ? " disabled" : "") +
      ">" +
      escapeHtml(t("showcase.next")) +
      " <kbd>⌥⇥</kbd></button>" +
      '<button type="button" class="demo-control-btn is-danger" data-demo-action="close"' +
      (ordered.length === 0 || state.closingId ? " disabled" : "") +
      ">" +
      escapeHtml(t("showcase.close")) +
      " <kbd>⌥Q</kbd></button>" +
      (isModified
        ? '<button type="button" class="demo-control-btn" data-demo-action="reset">' +
          escapeHtml(t("showcase.reset")) +
          "</button>"
        : "") +
      "</div>" +
      "</div>"
    );
  }

  function renderLauncherStage() {
    const rawQuery = state.launcherQuery || "";
    const tokens = rawQuery
      .trim()
      .toLowerCase()
      .split(/\s+/)
      .filter(Boolean);

    // ウィンドウ候補をファジー検索
    const matchedWindows =
      tokens.length === 0
        ? state.windows.slice()
        : state.windows.filter(function (w) {
            return matchTokens(w.app + " " + w.title, tokens) !== null;
          });

    // 上部に出現したアプリを除外したアプリ起動候補（検索入力時のみ表示）
    const shownApps = new Set(
      matchedWindows.map(function (w) {
        return w.app.toLowerCase();
      })
    );
    const matchedApps =
      tokens.length === 0
        ? []
        : LAUNCHABLE_APPS.filter(function (app) {
            const locName = app.names[state.locale] || app.names.en;
            if (shownApps.has(app.alias.toLowerCase()) || shownApps.has(locName.toLowerCase())) {
              return false;
            }
            return matchTokens(locName + " " + app.alias, tokens) !== null;
          });

    const totalCount = matchedWindows.length + matchedApps.length;
    if (state.launcherSelectedIndex >= totalCount) {
      state.launcherSelectedIndex = 0;
    }

    let listHtml = "";
    if (totalCount === 0) {
      listHtml = '<div class="launcher-empty">' + escapeHtml(t("showcase.noMatches")) + "</div>";
    } else {
      let itemIndex = 0;
      listHtml = '<div class="demo-list">';

      if (matchedWindows.length > 0) {
        if (state.launcherGrouped) {
          const groups = groupWindowsByApp(matchedWindows);
          for (let g = 0; g < groups.length; g += 1) {
            if (g > 0) listHtml += '<div class="demo-group-divider"></div>';
            const grp = groups[g];
            listHtml +=
              '<div class="demo-group-header">' +
              '<span class="demo-app-badge is-sm ' +
              grp.badgeClass +
              '">' +
              escapeHtml(grp.code) +
              "</span>" +
              "<span>" +
              highlightText(grp.app, tokens) +
              "</span>" +
              "</div>";
            for (let i = 0; i < grp.items.length; i += 1) {
              const w = grp.items[i];
              const isSel = itemIndex === state.launcherSelectedIndex;
              listHtml +=
                '<button type="button" class="demo-row is-indented' +
                (isSel ? " is-selected" : "") +
                '" data-launcher-select="' +
                itemIndex +
                '">' +
                (state.launcherStyle === "capture" ? renderThumbHtml(w, true) : "") +
                '<span class="demo-row-title" style="opacity:1;">' +
                highlightText(w.title, tokens) +
                "</span>" +
                "</button>";
              itemIndex += 1;
            }
          }
        } else {
          for (let i = 0; i < matchedWindows.length; i += 1) {
            const w = matchedWindows[i];
            const isSel = itemIndex === state.launcherSelectedIndex;
            listHtml +=
              '<button type="button" class="demo-row' +
              (isSel ? " is-selected" : "") +
              '" data-launcher-select="' +
              itemIndex +
              '">' +
              (state.launcherStyle === "capture" ? renderThumbHtml(w, true) : "") +
              '<span class="demo-app-badge ' +
              w.badgeClass +
              '">' +
              escapeHtml(w.code) +
              "</span>" +
              '<span class="demo-row-app">' +
              highlightText(w.app, tokens) +
              "</span>" +
              '<span class="demo-row-title">' +
              highlightText(w.title, tokens) +
              "</span>" +
              "</button>";
            itemIndex += 1;
          }
        }
      }

      if (matchedApps.length > 0) {
        if (matchedWindows.length > 0) {
          listHtml += '<div class="demo-group-divider"></div>';
        }
        const secLabel =
          matchedWindows.length > 0
            ? t("showcase.launchSection")
            : t("showcase.launchEmptyWindowsSection");
        listHtml += '<div class="launcher-section-label">' + escapeHtml(secLabel) + "</div>";

        for (let i = 0; i < matchedApps.length; i += 1) {
          const app = matchedApps[i];
          const locName = app.names[state.locale] || app.names.en;
          const showAlias = locName.toLowerCase() !== app.alias.toLowerCase();
          const isSel = itemIndex === state.launcherSelectedIndex;
          listHtml +=
            '<button type="button" class="demo-row' +
            (isSel ? " is-selected" : "") +
            '" data-launcher-select="' +
            itemIndex +
            '">' +
            '<span class="demo-app-badge ' +
            app.badgeClass +
            '">' +
            escapeHtml(app.code) +
            "</span>" +
            '<span class="demo-row-app">' +
            highlightText(locName, tokens) +
            "</span>" +
            '<span class="demo-row-title">' +
            (showAlias ? highlightText(app.alias, tokens) : "") +
            "</span>" +
            '<span class="demo-row-badge">' +
            escapeHtml(t("showcase.launchBadge")) +
            "</span>" +
            "</button>";
          itemIndex += 1;
        }
      }
      listHtml += "</div>";
    }

    return (
      '<div class="panel-column">' +
      '<div class="stage-toolbar">' +
      '<div class="style-toggle-bar" role="group">' +
      '<button type="button" class="style-toggle-btn' +
      (state.launcherStyle === "list" ? " is-active" : "") +
      '" data-launcher-style="list">' +
      escapeHtml(t("showcase.styleList")) +
      "</button>" +
      '<button type="button" class="style-toggle-btn' +
      (state.launcherStyle === "capture" ? " is-active" : "") +
      '" data-launcher-style="capture">' +
      escapeHtml(t("showcase.styleCapture")) +
      "</button>" +
      "</div>" +
      '<button type="button" class="group-toggle-btn' +
      (state.launcherGrouped ? " is-on" : "") +
      '" data-launcher-group-toggle>' +
      '<span class="group-toggle-dot" aria-hidden="true"></span>' +
      "<span>" +
      escapeHtml(t("showcase.groupByApp")) +
      "</span>" +
      "</button>" +
      "</div>" +
      '<div class="wintch-panel">' +
      '<div class="launcher-input-bar">' +
      '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.34-4.34"/></svg>' +
      '<input id="demo-launcher-input" type="text" class="launcher-input" value="' +
      escapeHtml(rawQuery) +
      '" placeholder="' +
      escapeHtml(t("showcase.searchPlaceholder")) +
      '" aria-label="' +
      escapeHtml(t("showcase.searchPlaceholder")) +
      '" />' +
      (rawQuery
        ? '<button type="button" class="launcher-clear-btn" data-sample-query="" aria-label="Clear">×</button>'
        : "") +
      "</div>" +
      listHtml +
      "</div>" +
      '<div class="demo-controls">' +
      '<span style="color:rgba(248,250,252,0.78);font-size:0.75rem;font-weight:600;">' +
      escapeHtml(t("showcase.sampleLabel")) +
      "</span>" +
      '<button type="button" class="demo-control-btn" data-sample-query="note">note</button>' +
      '<button type="button" class="demo-control-btn" data-sample-query="safari">safari</button>' +
      '<button type="button" class="demo-control-btn" data-sample-query="calc">calc</button>' +
      '<button type="button" class="demo-control-btn" data-sample-query="">All</button>' +
      "</div>" +
      "</div>"
    );
  }

  function renderSettingsStage() {
    let paneHtml = "";
    if (state.settingsTab === "general") {
      paneHtml =
        '<div class="settings-group">' +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sLaunchAtLogin")) +
        '</div><span class="settings-pill-val is-granted">' +
        escapeHtml(t("showcase.sOn")) +
        "</span></div>" +
        '<div class="settings-row"><div><div class="settings-row-label">' +
        escapeHtml(t("showcase.sAutoUpdate")) +
        '</div><div class="settings-row-sub">' +
        escapeHtml(t("showcase.sAutoUpdateSub")) +
        '</div></div><span class="settings-pill-val">' +
        escapeHtml(t("showcase.sOff")) +
        "</span></div>" +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sLanguage")) +
        '</div><span class="settings-pill-val">' +
        escapeHtml(t("showcase.sLanguageValue")) +
        "</span></div>" +
        "</div>";
    } else if (state.settingsTab === "switcher") {
      paneHtml =
        '<div class="settings-group">' +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sShortcut")) +
        '</div><span class="settings-pill-val">⌥ + Tab</span></div>' +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sDisplayStyle")) +
        '</div><span class="settings-pill-val">' +
        escapeHtml(t("showcase.sStyleList")) +
        "</span></div>" +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sGroupByApp")) +
        '</div><span class="settings-pill-val is-granted">' +
        escapeHtml(t("showcase.sOn")) +
        "</span></div>" +
        "</div>";
    } else if (state.settingsTab === "launcher") {
      paneHtml =
        '<div class="settings-group">' +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sShortcut")) +
        '</div><span class="settings-pill-val">⌥ + Space</span></div>' +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sDisplayStyle")) +
        '</div><span class="settings-pill-val">' +
        escapeHtml(t("showcase.sStyleLauncher")) +
        "</span></div>" +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sGroupByApp")) +
        '</div><span class="settings-pill-val is-granted">' +
        escapeHtml(t("showcase.sOn")) +
        "</span></div>" +
        "</div>";
    } else {
      paneHtml =
        '<div class="settings-group">' +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sAccessibility")) +
        '</div><span class="settings-pill-val is-granted">' +
        escapeHtml(t("showcase.sGranted")) +
        "</span></div>" +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sScreenRecording")) +
        '</div><span class="settings-pill-val is-optin">' +
        escapeHtml(t("showcase.sOptInOnly")) +
        "</span></div>" +
        "</div>" +
        '<div class="settings-group">' +
        '<div class="settings-row"><div class="settings-row-label">Wintch · ' +
        escapeHtml(t("showcase.sAppInfo")) +
        '</div><span class="settings-pill-val">' +
        escapeHtml(state.releaseVersion) +
        "</span></div>" +
        '<div class="settings-row"><div class="settings-row-label">' +
        escapeHtml(t("showcase.sCheckUpdates")) +
        '</div><span class="settings-pill-val is-optin">GitHub Releases</span></div>' +
        "</div>";
    }

    return (
      '<div class="panel-column is-wide">' +
      '<div class="wintch-panel">' +
      '<div class="settings-mock">' +
      '<div class="settings-sidebar" role="tablist">' +
      renderSettingsNavBtn("general", t("showcase.settingsGeneral")) +
      renderSettingsNavBtn("switcher", t("showcase.settingsSwitcher")) +
      renderSettingsNavBtn("launcher", t("showcase.settingsLauncher")) +
      renderSettingsNavBtn("system", t("showcase.settingsSystem")) +
      "</div>" +
      '<div class="settings-pane">' +
      paneHtml +
      "</div>" +
      "</div>" +
      "</div>" +
      "</div>"
    );
  }

  function renderSettingsNavBtn(id, label) {
    const active = state.settingsTab === id ? " is-active" : "";
    return (
      '<button type="button" class="settings-nav-btn' +
      active +
      '" data-settings-tab="' +
      id +
      '">' +
      escapeHtml(label) +
      "</button>"
    );
  }

  function bindLauncherInputEvents(stage) {
    const input = stage.querySelector("#demo-launcher-input");
    if (!input) return;
    input.addEventListener("input", function () {
      const caretPos = input.selectionStart;
      state.launcherQuery = input.value;
      state.launcherSelectedIndex = 0;
      renderShowcase();
      const refreshed = document.getElementById("demo-launcher-input");
      if (refreshed) {
        refreshed.focus();
        if (typeof caretPos === "number") {
          refreshed.setSelectionRange(caretPos, caretPos);
        }
      }
    });
  }

  /* ========================================================================
     5. イベント委譲・初期化
     ======================================================================== */

  function bindEvents() {
    // テーマ切替（system -> light -> dark -> system）
    const themeBtn = document.getElementById("theme-toggle");
    if (themeBtn) {
      themeBtn.addEventListener("click", function () {
        const order = ["system", "light", "dark"];
        const next = order[(order.indexOf(state.themeChoice) + 1) % order.length];
        applyTheme(next);
      });
    }

    // OS テーマ変更追従（system 選択時）
    if (window.matchMedia) {
      const mq = window.matchMedia("(prefers-color-scheme: dark)");
      const onThemeChange = function () {
        if (state.themeChoice === "system") applyTheme("system");
      };
      if (mq.addEventListener) {
        mq.addEventListener("change", onThemeChange);
      } else if (mq.addListener) {
        mq.addListener(onThemeChange);
      }
    }

    // 言語ドロップダウン
    const localeTrigger = document.getElementById("locale-trigger");
    const localeMenu = document.getElementById("locale-menu");
    if (localeTrigger && localeMenu) {
      const closeLocaleMenu = function () {
        localeMenu.hidden = true;
        localeTrigger.setAttribute("aria-expanded", "false");
      };
      localeTrigger.addEventListener("click", function (e) {
        e.stopPropagation();
        const isOpen = !localeMenu.hidden;
        localeMenu.hidden = isOpen;
        localeTrigger.setAttribute("aria-expanded", isOpen ? "false" : "true");
      });
      localeMenu.addEventListener("click", function (e) {
        const opt = e.target.closest(".locale-option[data-locale]");
        if (!opt) return;
        applyLocale(opt.getAttribute("data-locale"), true);
        closeLocaleMenu();
      });
      document.addEventListener("click", function (e) {
        if (!localeMenu.hidden && !localeTrigger.contains(e.target) && !localeMenu.contains(e.target)) {
          closeLocaleMenu();
        }
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape" && !localeMenu.hidden) {
          closeLocaleMenu();
          localeTrigger.focus();
        }
      });
    }

    // コマンドコピーボタン
    document.addEventListener("click", function (e) {
      const copyBtn = e.target.closest("[data-copy]");
      if (copyBtn) {
        handleCopyClick(copyBtn);
        return;
      }

      // Showcase 上部タブ切替
      const tabBtn = e.target.closest("[data-showcase-tab]");
      if (tabBtn) {
        const nextTab = tabBtn.getAttribute("data-showcase-tab");
        if (nextTab && nextTab !== state.activeTab) {
          state.activeTab = nextTab;
          const allTabs = document.querySelectorAll("[data-showcase-tab]");
          for (let i = 0; i < allTabs.length; i += 1) {
            const active = allTabs[i] === tabBtn;
            allTabs[i].classList.toggle("is-active", active);
            allTabs[i].setAttribute("aria-selected", active ? "true" : "false");
          }
          renderShowcase();
        }
        return;
      }

      // 通常スイッチャー表示形式切替
      const styleBtn = e.target.closest("[data-switcher-style]");
      if (styleBtn) {
        state.switcherStyle = styleBtn.getAttribute("data-switcher-style");
        renderShowcase();
        return;
      }

      // 通常スイッチャーグルーピング切替
      if (e.target.closest("[data-switcher-group-toggle]")) {
        state.switcherGrouped = !state.switcherGrouped;
        renderShowcase();
        return;
      }

      // 通常スイッチャー項目クリック選択
      const demoSel = e.target.closest("[data-demo-select]");
      if (demoSel) {
        state.selectedIndex = Number(demoSel.getAttribute("data-demo-select")) || 0;
        renderShowcase();
        return;
      }

      // 通常スイッチャー操作ボタン（前へ・次へ・閉じる・リセット）
      const actionBtn = e.target.closest("[data-demo-action]");
      if (actionBtn) {
        const action = actionBtn.getAttribute("data-demo-action");
        const ordered = getSwitcherOrderedWindows();
        if (action === "prev" && ordered.length > 0) {
          state.selectedIndex = (state.selectedIndex - 1 + ordered.length) % ordered.length;
          renderShowcase();
        } else if (action === "next" && ordered.length > 0) {
          state.selectedIndex = (state.selectedIndex + 1) % ordered.length;
          renderShowcase();
        } else if (action === "close" && ordered.length > 0 && !state.closingId) {
          const target = ordered[state.selectedIndex];
          if (!target) return;
          // 終了処理中スピナーを短時間表示してから一覧から除外する
          state.closingId = target.id;
          renderShowcase();
          window.setTimeout(function () {
            state.windows = state.windows.filter(function (w) {
              return w.id !== target.id;
            });
            state.closingId = null;
            const remaining = getSwitcherOrderedWindows();
            if (state.selectedIndex >= remaining.length) {
              state.selectedIndex = Math.max(0, remaining.length - 1);
            }
            renderShowcase();
          }, 420);
        } else if (action === "reset") {
          state.windows = INITIAL_WINDOWS.map(cloneObject);
          state.selectedIndex = 1;
          state.closingId = null;
          renderShowcase();
        }
        return;
      }

      // 検索ランチャー表示形式・グルーピング・選択・サンプルクエリ
      const lStyle = e.target.closest("[data-launcher-style]");
      if (lStyle) {
        state.launcherStyle = lStyle.getAttribute("data-launcher-style");
        renderShowcase();
        return;
      }
      if (e.target.closest("[data-launcher-group-toggle]")) {
        state.launcherGrouped = !state.launcherGrouped;
        renderShowcase();
        return;
      }
      const lSel = e.target.closest("[data-launcher-select]");
      if (lSel) {
        state.launcherSelectedIndex = Number(lSel.getAttribute("data-launcher-select")) || 0;
        renderShowcase();
        return;
      }
      const sampleBtn = e.target.closest("[data-sample-query]");
      if (sampleBtn) {
        state.launcherQuery = sampleBtn.getAttribute("data-sample-query") || "";
        state.launcherSelectedIndex = 0;
        renderShowcase();
        return;
      }

      // 設定画面サイドバー切替
      const sTab = e.target.closest("[data-settings-tab]");
      if (sTab) {
        state.settingsTab = sTab.getAttribute("data-settings-tab") || "general";
        renderShowcase();
      }
    });
  }

  function init() {
    applyTheme(state.themeChoice);
    bindEvents();
    applyLocale(state.locale, false);
    fetchLatestRelease();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
