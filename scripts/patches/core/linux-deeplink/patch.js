'use strict';
/**
 * linux-deeplink — route kimi:// and kimi-work:// from inside the Electron
 * shell (Chat webview will-navigate / window.open / claw routes) through
 * handleDeepLink, instead of dropping them or sending them to
 * shell.openExternal (which only allows http/https/mailto/tel).
 *
 * Without this, Invite/claim flows that work in a browser fail inside the
 * unofficial Linux desktop build: deep links never open the local Work surface.
 */
const { replaceAll } = require('../../shared');

module.exports = [
  {
    id: 'linux-deeplink-will-navigate',
    phase: 'main-bundle',
    order: 40,
    ciPolicy: 'optional',
    file: 'out/main/index.js',
    apply: (source) => {
      const needle =
        'if (parsed2.protocol === "kimi:") {\n' +
        '          event.preventDefault();\n' +
        '          return;\n' +
        '        }';
      const repl =
        'if (parsed2.protocol === "kimi:" || parsed2.protocol === "kimi-work:") {\n' +
        '          event.preventDefault();\n' +
        '          handleDeepLink(url);\n' +
        '          return;\n' +
        '        }';
      if (!source.includes(needle)) return source;
      return replaceAll(source, needle, repl);
    },
  },
  {
    id: 'linux-deeplink-window-open',
    phase: 'main-bundle',
    order: 41,
    ciPolicy: 'optional',
    file: 'out/main/index.js',
    apply: (source) => {
      const needle =
        'wc.setWindowOpenHandler(({ url }) => {\n' +
        '      try {\n' +
        '        const host = new URL(url).hostname;\n' +
        '        if (getAllowedHosts().includes(host)) {\n' +
        '          return { action: "allow", overrideBrowserWindowOptions: { show: false } };\n' +
        '        }\n' +
        '      } catch {\n' +
        '      }\n' +
        '      safeOpenExternal(url);\n' +
        '      return { action: "deny" };\n' +
        '    });';
      const repl =
        'wc.setWindowOpenHandler(({ url }) => {\n' +
        '      try {\n' +
        '        const parsedPopup = new URL(url);\n' +
        '        if (parsedPopup.protocol === "kimi:" || parsedPopup.protocol === "kimi-work:") {\n' +
        '          handleDeepLink(url);\n' +
        '          return { action: "deny" };\n' +
        '        }\n' +
        '        const host = parsedPopup.hostname;\n' +
        '        if (getAllowedHosts().includes(host)) {\n' +
        '          return { action: "allow", overrideBrowserWindowOptions: { show: false } };\n' +
        '        }\n' +
        '      } catch {\n' +
        '      }\n' +
        '      safeOpenExternal(url);\n' +
        '      return { action: "deny" };\n' +
        '    });';
      if (!source.includes(needle)) return source;
      return replaceAll(source, needle, repl);
    },
  },
  {
    id: 'linux-deeplink-route-claw',
    phase: 'main-bundle',
    order: 42,
    ciPolicy: 'optional',
    file: 'out/main/index.js',
    apply: (source) => {
      const needle =
        'async function routeClawWindowOpen(rawUrl) {\n' +
        '  const url = rawUrl?.trim();\n' +
        '  if (!url) {\n' +
        '    return;\n' +
        '  }\n' +
        '  const localPath = extractLocalPath(url);\n';
      const repl =
        'async function routeClawWindowOpen(rawUrl) {\n' +
        '  const url = rawUrl?.trim();\n' +
        '  if (!url) {\n' +
        '    return;\n' +
        '  }\n' +
        '  try {\n' +
        '    const scheme = new URL(url).protocol;\n' +
        '    if (scheme === "kimi:" || scheme === "kimi-work:") {\n' +
        '      handleDeepLink(url);\n' +
        '      return;\n' +
        '    }\n' +
        '  } catch {\n' +
        '  }\n' +
        '  const localPath = extractLocalPath(url);\n';
      if (!source.includes(needle)) return source;
      return replaceAll(source, needle, repl);
    },
  },
  {
    id: 'linux-deeplink-cold-start',
    phase: 'main-bundle',
    order: 43,
    ciPolicy: 'optional',
    file: 'out/main/index.js',
    apply: (source) => {
      const needle =
        '  app.on("open-url", (_event, url) => {\n' +
        '    handleDeepLink(url);\n' +
        '  });\n' +
        '  return true;\n' +
        '}\n' +
        'function handleDeepLink(rawUrl) {';
      const repl =
        '  app.on("open-url", (_event, url) => {\n' +
        '    handleDeepLink(url);\n' +
        '  });\n' +
        '  const startupDeepLink = process.argv.find(isDeepLinkArg);\n' +
        '  if (startupDeepLink) {\n' +
        '    KLogMain.info("App", `startup deep link: ${startupDeepLink}`);\n' +
        '    setTimeout(() => handleDeepLink(startupDeepLink), 2500);\n' +
        '  }\n' +
        '  return true;\n' +
        '}\n' +
        'function handleDeepLink(rawUrl) {';
      if (!source.includes(needle) || source.includes('startup deep link:')) return source;
      return replaceAll(source, needle, repl);
    },
  },
  {
    id: 'linux-deeplink-handle-logging',
    phase: 'main-bundle',
    order: 44,
    ciPolicy: 'optional',
    file: 'out/main/index.js',
    apply: (source) => {
      // Logging only — does not claim to complete invite/draw payloads.
      const needle =
        '  deps?.getWindowManager()?.showAndFocus();\n' +
        '  if (parsed2.protocol === `${WORK_DEEP_LINK_SCHEME}:`) {\n' +
        '    deps?.getKimiAgent()?.openPage();\n' +
        '    return;\n' +
        '  }';
      const repl =
        '  KLogMain.info("App", `handleDeepLink protocol=${parsed2.protocol} host=${parsed2.host} path=${parsed2.pathname}${parsed2.search}`);\n' +
        '  deps?.getWindowManager()?.showAndFocus();\n' +
        '  if (parsed2.protocol === `${WORK_DEEP_LINK_SCHEME}:`) {\n' +
        '    deps?.getKimiAgent()?.openPage();\n' +
        '    // Best-effort: also push non-trivial path into kimiView. Claim/draw\n' +
        '    // payloads are still incomplete on Linux (see upstream issue).\n' +
        '    const workPath = deepLinkToNavigatePath(parsed2);\n' +
        '    if (workPath && workPath !== "/home" && workPath !== "/") {\n' +
        '      try {\n' +
        '        deps?.getWindowManager()?.kimiView?.webContents.send("bridge:push-navigate", workPath);\n' +
        '      } catch (e) {\n' +
        '        KLogMain.warn("App", `work deep link navigate failed: ${String(e)}`);\n' +
        '      }\n' +
        '    }\n' +
        '    return;\n' +
        '  }';
      if (!source.includes(needle) || source.includes('handleDeepLink protocol=')) return source;
      return replaceAll(source, needle, repl);
    },
  },
];
