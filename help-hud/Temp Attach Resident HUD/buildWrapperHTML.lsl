string buildWrapperHTML(string capURL, string nonce, string lang)
{
    return
    "<!doctype html><html><head>
      <meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
      <title>Help HUD</title>
      <style>
        html,body{margin:0;height:100%;background:#0e0f12}
        #app{display:none;padding:12px;font:16px system-ui,sans-serif;position:relative;z-index:0}
        .wrap{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;z-index:9999}
        .spin{width:72px;height:72px;border:8px solid #2b2f38;border-top-color:#f6d353;border-radius:50%;
             animation:spin .8s linear infinite}
        @keyframes spin{to{transform:rotate(1turn)}}
      </style>
      <link rel='stylesheet' href='https://quartzmole.github.io/mentor-hud/help-hud/app.css?v=18'>
      <style>body,#app{color:#f3f3f3 !important;}</style>
    </head><body>
      <div id='loader' class='wrap'><div class='spin' aria-label='Loading'></div></div>
      <div id='app'>Loading…</div>
      <script>window.__HUD_LOADER_TS=Date.now();
        window.HUD_URL='" + capURL + "';
        window.CSRF_NONCE='" + nonce + "';
        window.LANG='" + lang + "';
      </script>
      <script src='https://quartzmole.github.io/mentor-hud/help-hud/app.js?v=18' defer></script>
    </body></html>";
}
