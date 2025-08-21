// === Help HUD (Resident) ===
// Purpose: Display a Shared Media UI, receive selected help options from the page, write to KVP, and finish.

///////////////////////
// CONFIG
///////////////////////
integer iFace = 4;                   // Face used for MOAP on your HUD prim
//llSetLinkMedia(LINK_THIS,string  strBaseUrl = "https://quartzmole.github.io/mentor-hud/help-hud/index.html"; // Your hosted UI
string strLoadingPage = "https://quartzmole.github.io/mentor-hud/help-hud/loading.html";
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
string  WRAPPER_HTML;
key     kHttpReq         = NULL_KEY;
key     kUrlReq          = NULL_KEY;
string  strNonce           = "";            // Simple anti-spoof token
integer iReadySent       = FALSE;         // Once page confirms it loaded
integer iTimerStart      = 0;
integer iCommsChannel   = -710672827;
integer iAttachPoint  = ATTACH_HUD_TOP_CENTER;
vector vOwnerPos;
integer iCounter = 7;
///////////////////////
// UTIL
///////////////////////
string enc(string s) {
    // Minimal encoder for query params
    return llEscapeURL(s);
}

string strLoadingPageHTML; 



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
        strLoadingPageHTML = "<!DOCTYPE html>
<html>
  <head>
    <title>Loading...</title>
  </head>
  <body style='margin:0;padding:0;'>
    <iframe src='"+strLoadingPage+"'
        style='border:none;width:100%;height:100%;'>
    </iframe>
  </body>
</html>
";
    WRAPPER_HTML = "<!doctype html>
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
            llRequestURL();
            llOwnerSay("requesting url");

        }
    }

     http_request(key id, string method, string body)
    {
        llOwnerSay("http request event: method == "+method);
        if (method == URL_REQUEST_GRANTED)
        {
            string gMyURL = body; // the temp URL granted by the region

            // Point the media face to the temp URL (not the GitHub one)
            llSetLinkMedia(LINK_THIS, 4, [
                PRIM_MEDIA_AUTO_PLAY, TRUE,
                PRIM_MEDIA_CURRENT_URL, gMyURL,
                PRIM_MEDIA_HOME_URL, gMyURL,
                PRIM_MEDIA_HEIGHT_PIXELS, 512,
                PRIM_MEDIA_WIDTH_PIXELS, 512
            ]);
            llOwnerSay("154 changing prim media");
            // Serve your escaped HTML here
            llHTTPResponse(id, 200,strLoadingPageHTML);
            llRequestExperiencePermissions(kOwner,"");
            llOwnerSay("requesting experience_permissions");
        }
        else if (method == URL_REQUEST_DENIED)
        {
            llOwnerSay("Could not get a URL: " + body);
        }
        else if (method == "GET")
        {

        }
        else
        {
            llHTTPResponse(id, 405, "Method not allowed");
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
            state running;
        } 
    }

}

state running{

    state_entry()
    {

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
            llOwnerSay("line 241 method is POST and body is "+body);

            string contentType = llGetHTTPHeader(id, "content-type");
            string posted = "";  // <-- we'll put the JSON here

            if (llSubStringIndex(contentType, "application/json") != -1) {
                // Raw JSON from fetch()
                posted = body;
                llOwnerSay("248 posted(json) == " + posted);
                } 

                else {
                    // Robust form parse: find the json=... field only
                    list parts = llParseString2List(body, ["&"], []);
                    integer i; integer n = llGetListLength(parts);
                    for (i = 0; i < n; ++i) {
                        string kv = llList2String(parts, i);
                        integer eq = llSubStringIndex(kv, "=");
                        if (eq > 0) {
                            string k = llUnescapeURL(llGetSubString(kv, 0, eq-1));
                            string v = llUnescapeURL(llGetSubString(kv, eq+1, -1));
                            if (k == "json") {
                                posted = v;
                                i = n; // terminate loop early (no 'break' in LSL)
                            }
                        }
                    }
                    llOwnerSay("262 posted(form->json) == " + posted);
                }




            // Parse fields from the posted JSON
            string postedNonce = llJsonGetValue(posted, ["nonce"]);
            string topicsJson  = llJsonGetValue(posted, ["topics"]);
            llOwnerSay("DEBUG: postedNonce=" + postedNonce + " | strNonce=" + strNonce);

            if (postedNonce != strNonce) {
                llOwnerSay("270: bad nonce (got " + postedNonce + " expected " + strNonce + ")");
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 403, "{\"status\":\"bad_nonce\"}");
                return;
            }

            // Success: reply once (JSON), then do your work
            llSetContentType(id, CONTENT_TYPE_JSON);
            llHTTPResponse(id, 200, "{\"status\":\"ok\"}");
            llOwnerSay("276: sent status OK");

            // Now write KVP using the same JSON we just parsed
            write_kvp(posted);



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
