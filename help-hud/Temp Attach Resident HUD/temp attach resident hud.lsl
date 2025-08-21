// === Help HUD (Resident) ===
// Purpose: Display a Shared Media UI, receive selected help options from the page, write to KVP, and finish.

///////////////////////
// CONFIG
///////////////////////
integer iFace = 4;                   // Face used for MOAP on your HUD prim
//llSetLinkMedia(LINK_THIS,string  strBaseUrl = "https://quartzmole.github.io/mentor-hud/help-hud/index.html"; // Your hosted UI

//https://quartzmole.github.io/mentor-hud/
//integer iMediaWidth  = 1024;              // Optional: tune to your UI
//integer iMediaHeight = 768;

string  strKVPPrefix   = "HELPREQ_";        // KVP key prefix
float fKVLifespan      = 300.0;               // Seconds to keep the request (auto-expire)

float fHTTPTimeout = 60;                // Seconds before we give up waiting for page to call back

///////////////////////
// STATE
///////////////////////
key kRezzer;
key     kOwner        = NULL_KEY;
string  strResidentName    = "";
string  strHttpUrl         = "";
string  WRAPPER_HTML= "
    <!doctype html>
            <html>
            <head>
              <meta charset='utf-8'>
              <meta name='viewport' content='width=device-width,initial-scale=1'>
              <title>Request Mentor Help</title>
              <meta http-equiv='cache-control' content='no-cache'>
              <style>
                body { font-family: system-ui, sans-serif; margin: 12px; font-size: 18px; }
              </style>
            </head>
            <body>
              <div id='app'>Loading…</div>

              <script>
                /* Injected by the HUD script before sending the response */
                window.HUD_URL = '{{HUD_URL}}';      // your capability URL (http://simhost-…:12046/cap/…)
                window.CSRF_NONCE = '{{NONCE}}';     // your per-session nonce

                /* Read ?lang=xx from the URL (works in CEF without URLSearchParams) */
                (function () {
                  var s = window.location.search || '';
                  var m = (s.match(/[?&]lang=([^&#]*)/i) || [])[1];
                  window.LANG = m ? decodeURIComponent(m.replace(/\+/g, ' ')) : 'en';
                })();
              </script>
                <script>
                  (function () {
                    // Only show the banner if ?debug=1 (optional; remove this 'if' to always show)
                    var show = /[?&]debug=1/i.test(location.search);
                    if (!show) return;

                    var hud = window.HUD_URL || '(nil)';
                    var nonce = window.CSRF_NONCE || '(nil)';
                    var origin = location.origin;

                    // Force HTTP display (what the app.js will use)
                    var hudHttp = hud.replace(/^https:\/\//i, 'http:');

                    // Console logs (visible in the built‑in browser devtools if available)
                    try {
                      console.log('[HUD DEBUG] origin =', origin);
                      console.log('[HUD DEBUG] injected HUD_URL =', hud);
                      console.log('[HUD DEBUG] NONCE =', nonce);
                      console.log('[HUD DEBUG] will post to =', hudHttp + '?action=submit');
                    } catch (e) {}

                    // On‑screen banner (top-left)
                    var box = document.createElement('div');
                    box.style.position = 'fixed';
                    box.style.top = '6px';
                    box.style.left = '6px';
                    box.style.zIndex = '99999';
                    box.style.padding = '8px 10px';
                    box.style.background = 'rgba(0,0,0,0.75)';
                    box.style.color = '#fff';
                    box.style.font = '12px/1.35 system-ui, sans-serif';
                    box.style.borderRadius = '6px';
                    box.style.maxWidth = '92vw';
                    box.style.wordBreak = 'break-all';
                    box.textContent =
                      'DEBUG — origin=' + origin +
                      ' | HUD_URL=' + hud +
                      ' | POST→ ' + hudHttp + '?action=submit' +
                      ' | nonce=' + nonce;
                    document.body.appendChild(box);
                  })();
                </script>

              <!-- Load the actual UI/logic from GitHub Pages -->
              <script src='https://quartzmole.github.io/mentor-hud/help-hud/app.js'></script>
            </body>
            </html>";
string strLoadingPageHTML = "
    <!doctype html>
    <html>
    <head>
    <meta charset='utf-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <title>Loading…</title>
    <style>
      html,body{margin:0;height:100%;background:#0e0f12}
      .wrap{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
      .loader{width:84px;height:84px;border-radius:50%;border:8px solid #2b2f38;box-sizing:border-box;
        --c:no-repeat radial-gradient(farthest-side,#f4c63d 94%,#0000);
        --b:no-repeat radial-gradient(farthest-side,#000 94%,#0000);
        background:
          var(--c) 11px 15px, var(--b) 6px 15px,
          var(--c) 35px 23px, var(--b) 29px 15px,
          var(--c) 11px 46px, var(--b) 11px 34px,
          var(--c) 36px 0px,  var(--b) 50px 31px,
          var(--c) 47px 43px, var(--b) 31px 48px, #f6d353;
        animation: spin 1s linear infinite;
      }
      @keyframes spin{to{transform:rotate(1turn)}}
      iframe{position:fixed;inset:0;width:100%;height:100%;border:0;display:none;background:#0e0f12}
    </style>
    </head>
    <body>
      <div class='wrap'><div class='loader' aria-label='Loading'></div></div>
      <iframe id='app' src='https://your-gh-pages.example/mentor-hud/form.html'></iframe>
    <script>
      const app=document.getElementById('app');
      const wrap=document.querySelector('.wrap');
      app.addEventListener('load',()=>{ wrap.style.display='none'; app.style.display='block'; }, {once:true});
    </script>
    </body>
    </html>

    ";
key     kHttpReq         = NULL_KEY;
key     kUrlReq          = NULL_KEY;
string  strNonce           = "";            // Simple anti-spoof token
integer iReadySent       = FALSE;         // Once page confirms it loaded
integer iTimerStart      = 0;
integer iCommsChannel   = -710672827;
integer iAttachPoint  = ATTACH_HUD_TOP_CENTER;
vector vOwnerPos;
integer iCounter = 7;
string gURL;
///////////////////////
// UTIL
///////////////////////
string enc(string s) {
    // Minimal encoder for query params
    return llEscapeURL(s);
}


string getFormField(string body, string field) {
    list parts = llParseString2List(body, ["&"], []);
    integer i;
    for (i = 0; i < llGetListLength(parts); ++i) {
        string pair = llList2String(parts, i);
        list kv = llParseString2List(pair, ["="], []);
        if (llGetListLength(kv) == 2) {
            string k = llList2String(kv, 0);
            string v = llList2String(kv, 1);
            if (k == field) return llUnescapeURL(v);
        }
    }
    return "";
}


// No longer use GitHub as the media origin.
// We serve a wrapper from *our* HUD URL on GET.
string buildMediaUrl() {
    llOwnerSay("starting buildMediaUrl");
    if (strHttpUrl == "") {
        // safety fallback while URL not granted yet
        return "about:blank";
    }
    string url = strHttpUrl + "?lang=" + enc(llGetAgentLanguage(kOwner));
    llOwnerSay("returning " + url);
    return url; // <-- media now points to HUD origin (same as POST target)
}

set_media(string url) {
    // Apply media to the HUD face
    llOwnerSay("set_media -- setting media with url "+url);
    llSetLinkMedia(LINK_THIS, iFace, [

        PRIM_MEDIA_AUTO_PLAY, TRUE,
        PRIM_MEDIA_PERMS_CONTROL, PRIM_MEDIA_PERM_NONE,
        PRIM_MEDIA_PERMS_INTERACT, PRIM_MEDIA_PERM_OWNER,  // wearer only
        PRIM_MEDIA_CURRENT_URL, url,
        PRIM_MEDIA_HOME_URL, url,
        PRIM_MEDIA_WHITELIST_ENABLE,     FALSE,

        PRIM_MEDIA_FIRST_CLICK_INTERACT, TRUE
    ]);
}

arm_timeout() {
    iTimerStart = llGetUnixTime();
    llSetTimerEvent(1.0);
}


write_kvp(string requestJson) {
    // Build KVP object to store (augment what page sent if useful)
    // Expecting requestJson to include the selections, e.g.:
    // { "options": ["Account help","Finding freebies"], "notes":"..." }
    string kvpKey = strKVPPrefix + (string)kOwner;
    string payload = llList2Json(JSON_OBJECT, [
        "resident", (string)kOwner,
        "name", strResidentName,
        "selections", requestJson,           // store as embedded JSON string or parse/merge if you prefer
        "timestamp", (string)llGetUnixTime()
    ]);

    // NOTE: If you want "selections" as a real JSON array inside the object, parse requestJson and recompose.
    // For brevity, we store it as a string; many people prefer to parse it with llJson2List and rebuild.

    llUpdateKeyValue(kvpKey, payload,FALSE,"");
}

string ReplaceAll(string src, string find, string repl) {
    integer p;
    integer fl = llStringLength(find);
    while ((p = llSubStringIndex(src, find)) != -1) {
        src = llDeleteSubString(src, p, p + fl - 1);
        src = llInsertString(src, p, repl);
    }
    return src;
}




///////////////////////
// LIFECYCLE
///////////////////////
default
{

    state_entry()
    {
        llClearLinkMedia(LINK_THIS, iFace);
        /*
        strLoadingPageHTML = "<!DOCTYPE html>
        <html>
          <head>
            <title>Loading...</title>
          </head>
          <body style='margin:0;padding:0;'>
            <iframe src='"+strLoadingPageHTML+"'
                style='border:none;width:100%;height:100%;'>
            </iframe>
          </body>
        </html>
        ";*/
        
    }
    on_rez(integer start_param)
    {
        if(start_param){
            llOwnerSay("rezzed with start param");
            kRezzer = llList2Key(llGetObjectDetails(llGetKey(), [OBJECT_REZZER_KEY]),0);
            kOwner = (key)llGetStartString();
            strNonce = (string)llGetKey();
            if(llGetAgentSize(kOwner)==ZERO_VECTOR){
                llDie();
            }
            llRequestExperiencePermissions(llGetOwner(), "");
            llOwnerSay("requesting experience_permissions");


        }
    }

    http_request(key id, string method, string body) // https://wiki.secondlife.com/wiki/Http_request
    {
        llOwnerSay("http_request: method == "+method+" and body == "+body);

        if (method == URL_REQUEST_GRANTED)
        {
            gURL = body;
            // Set BOTH HOME and CURRENT on first apply
            llSetLinkMedia(LINK_THIS, iFace,          // https://wiki.secondlife.com/wiki/LlSetLinkMedia
                [ PRIM_MEDIA_HOME_URL,    gURL,
                  PRIM_MEDIA_CURRENT_URL, gURL,
                  PRIM_MEDIA_AUTO_PLAY,   TRUE,
                  PRIM_MEDIA_FIRST_CLICK_INTERACT, FALSE,
                  PRIM_MEDIA_PERMS_CONTROL,  PRIM_MEDIA_PERM_NONE,
                  PRIM_MEDIA_PERMS_INTERACT, PRIM_MEDIA_PERM_NONE ]);

                
            // Optional: small nudge refresh a moment later if a slow viewer misses the first set
            llSetTimerEvent(0.5);
        }
        else if (method == "GET")
        {
            llSetContentType(id, CONTENT_TYPE_HTML);   // https://wiki.secondlife.com/wiki/LlSetContentType
            llHTTPResponse(id, 200, strLoadingPageHTML);
            state running;


        }
        else if (method == URL_REQUEST_DENIED)
        {
            llOwnerSay("URL request denied: " + body);
        }
    }

    timer()
    {   // Optional “kick” in case the viewer didn’t fetch immediately
        llOwnerSay("timer");
        llSetTimerEvent(0.0);
        if (gURL != "")
        {
            // Re-apply current URL only (doesn't change the page)
            llOwnerSay("reapplying "+gURL);
            llSetLinkMedia(LINK_THIS, iFace, [ PRIM_MEDIA_CURRENT_URL, gURL ]);
        }
    }


    experience_permissions(key agent)
    {
        llOwnerSay("trying to attach to "+llGetUsername(agent));
        llAttachToAvatarTemp(iAttachPoint);
    }


    attach(key id)
    {
        if (id) {
          llRequestURL();
          llOwnerSay("requesting url");
        } 
    }

}

state running{

    state_entry()
    {
        llOwnerSay("Free memory: "+(string)llGetFreeMemory());

        if(llGetLinkNumber()){
            llSetLinkPrimitiveParamsFast(LINK_SET, [PRIM_TEMP_ON_REZ,FALSE]);
        }
        else{
            llSetPrimitiveParams([PRIM_TEMP_ON_REZ,FALSE]);
        }        
        string strUsername = llGetUsername(kOwner);
        string strDisplayName = llGetDisplayName(kOwner);
        strResidentName = strDisplayName;
        if(llList2String(llParseString2List(llToLower(strDisplayName),[" "],["."]),0)!=strUsername){
            strResidentName = strDisplayName+" ("+strUsername+")";
        }
        //set_media(buildMediaUrl());
        kUrlReq = llRequestURL();

    }

    experience_permissions(key agent)
    {
        llDetachFromAvatar();
    }



    http_request(key id, string method, string body)
    {
        // This event fires for both: URL grant and subsequent POSTs from page
        llOwnerSay("http_request event line 224: method == "+method+", and body == "+body);
   
        if (method == URL_REQUEST_GRANTED) {
            strHttpUrl = body;  // <-- save the HTTP cap
            // after you set strHttpUrl = body;
            string lang = llGetAgentLanguage(kOwner);

            // Build the media URL WITH cb & nonce (plus a version to bust cache)
            string mediaUrl =
                strHttpUrl
                + "?lang="  + enc(lang)
                + "&cb="    + enc(strHttpUrl)   // <— add this
                + "&nonce=" + enc(strNonce)     // <— and this
                + "&v="+(string)(++iCounter);                       // cache-buster

            llSetLinkMedia(LINK_THIS, 4, [
                PRIM_MEDIA_HOME_URL,             mediaUrl,
                PRIM_MEDIA_CURRENT_URL,          mediaUrl,
                PRIM_MEDIA_AUTO_PLAY,            TRUE,
                PRIM_MEDIA_FIRST_CLICK_INTERACT, TRUE,
                PRIM_MEDIA_PERMS_INTERACT,       PRIM_MEDIA_PERM_ANYONE,
                PRIM_MEDIA_PERMS_CONTROL,        PRIM_MEDIA_PERM_OWNER,
                PRIM_MEDIA_WHITELIST_ENABLE,     FALSE
            ]);

            // (keep your llHTTPResponse(id,200,"") as you already have)

            llHTTPResponse(id, 200, "");
            return;
        }

        if (id == kUrlReq && method == URL_REQUEST_DENIED) {
            llOwnerSay("Sorry, I couldn't open a callback URL. Please try again later.");
            llRequestExperiencePermissions(kOwner,"");
        }
        if (method == "GET") {
            string html = WRAPPER_HTML;

            // strHttpUrl must be the value you saved from URL_REQUEST_GRANTED (the cap)
            // strNonce is your per-session nonce
            html = ReplaceAll(html, "{{HUD_URL}}", strHttpUrl);
            html = ReplaceAll(html, "{{NONCE}}",  strNonce);

            // (optional) prove we injected the right thing:
            llOwnerSay("WRAP inject HUD_URL=" + strHttpUrl + " NONCE=" + strNonce);

            llSetContentType(id, CONTENT_TYPE_HTML);
            llHTTPResponse(id, 200, html);
            return;
        }


                // Handle the POST from the UI
        if (method == "POST") {
            // --- Parse body into JSON string 'posted' (accept JSON or form) ---
            string contentType = llToLower(llGetHTTPHeader(id, "content-type"));
            string posted = "";

            if (llSubStringIndex(contentType, "application/json") != -1) {
                // Raw JSON (e.g., fetch with JSON body)
                posted = body;
            } else {
                // Parse application/x-www-form-urlencoded and extract only json=...
                list parts = llParseString2List(body, ["&"], []);
                integer i;
                integer n = llGetListLength(parts);
                for (i = 0; i < n; ++i) {
                    string kv = llList2String(parts, i);
                    integer eq = llSubStringIndex(kv, "=");
                    if (eq > 0) {
                        string k = llUnescapeURL(llGetSubString(kv, 0, eq - 1));
                        string v = llUnescapeURL(llGetSubString(kv, eq + 1, -1));
                        if (k == "json") {
                            posted = v;
                            i = n; // terminate loop early (no 'break' in LSL)
                        }
                    }
                }
            }

            if (posted == "") {
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 400, "{\"status\":\"missing_json\"}");
                return;
            }

            // --- Fast size guard (1 KB—tune as you like) ---
            if (llStringLength(posted) > 1024) {
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 413, "{\"status\":\"payload_too_large\"}");
                return;
            }

            // --- Parse + validate shape ---
            // Nonce
            string postedNonce = llJsonGetValue(posted, ["nonce"]);
            if (postedNonce == JSON_INVALID) postedNonce = "";

            if (postedNonce != strNonce) {
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 403, "{\"status\":\"bad_nonce\"}");
                return;
            }

            // Topics must be an array
            if (llJsonValueType(posted, ["topics"]) != JSON_ARRAY) {
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 400, "{\"status\":\"bad_topics_type\"}");
                return;
            }

            string topicsJson = llJsonGetValue(posted, ["topics"]);
            list topicsList = llJson2List(topicsJson);

            integer nTopics = llGetListLength(topicsList);
            if (nTopics < 1 || nTopics > 5) {
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 400, "{\"status\":\"bad_topics_len\"}");
                return;
            }

            // Allowlist of topic codes your UI uses
            list ALLOWED = ["how","exploring","meeting","freebies","avatar"];

            // Deduplicate + validate
            list clean = [];
            integer j;
            for (j = 0; j < nTopics; ++j) {
                string t = llList2String(topicsList, j);

                // Validate against ALLOWED
                if (llListFindList(ALLOWED, [t]) == -1) {
                    llSetContentType(id, CONTENT_TYPE_JSON);
                    llHTTPResponse(id, 400,
                        "{\"status\":\"bad_topic\",\"topic\":\"" + t + "\"}"
                    );
                    return;
                }

                // Deduplicate
                if (llListFindList(clean, [t]) == -1) {
                    clean += [t];
                }
            }

            // Optionally: rebuild a sanitized JSON object to persist
            string safe = llList2Json(JSON_OBJECT,
                ["nonce", postedNonce,
                 "topics", llList2Json(JSON_ARRAY, clean)]
            );

            // Respond OK first
            llSetContentType(id, CONTENT_TYPE_JSON);
            llHTTPResponse(id, 200, "{\"status\":\"ok\"}");

            // Persist the sanitized JSON
            write_kvp(safe);
            return;
        }



        // For any other method:
        llHTTPResponse(id, 405, "Method Not Allowed");
    }

    dataserver(key queryid, string data)
    {
    integer success = (integer)llGetSubString(data, 0, 0); // "1" or "0"
    data = llDeleteSubString(data, 0, 1);                  // chop off the first char (and comma)

    if (success) {
        // ✅ success: 'data' now contains the value you stored (for read),
        // or may just be empty for create/update/delete success.
        llOwnerSay("KVP succeeded: " + data);
        llOwnerSay("Thanks—your help request has been sent.");
    }
    else {
        // ❌ failure: 'data' now contains a numeric error code
        integer code = (integer)data;
        llOwnerSay("KVP failed: " + llGetExperienceErrorMessage(code)); 
    }


        llRequestExperiencePermissions(kOwner, "");

    }

    timer()
    {
        if (iTimerStart && (llGetUnixTime() - iTimerStart) >= fHTTPTimeout) {
            llOwnerSay("Timed out waiting for the help page. Please try again.");
            llDetachFromAvatar();
        }
    }
}
