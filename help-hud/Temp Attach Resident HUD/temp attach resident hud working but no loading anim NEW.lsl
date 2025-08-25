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
float fKVLifespan      = 120.0;               // Seconds to keep the request (auto-expire)

float fHTTPTimeout = 60;                // Seconds before we give up waiting for page to call back

///////////////////////
// STATE
///////////////////////
key kRezzer;
key     kOwner        = NULL_KEY;
string  strResidentName    = "";
string  strHttpUrl         = "";


key     kUrlReq          = NULL_KEY;
key     kKVPWrite  = NULL_KEY;            // handle for llUpdateKeyValue
string  strNonce           = "";            // Simple anti-spoof token
//integer iReadySent       = FALSE;         // Once page confirms it loaded
integer iTimerStart      = 0;
integer iCommsChannel   = -710672827;
integer iAttachPoint  = ATTACH_HUD_TOP_CENTER;
//vector vOwnerPos;
integer iCounter = 7;
string gURL;






///////////////////////
// UTIL
///////////////////////
string enc(string s) {
    // Minimal encoder for query params
    return llEscapeURL(s);
}

write_kvp(string strRequestJson)
{
    // Build KVP object (same as you posted, just variables renamed to your style)
    string strKvpKey = strKVPPrefix + (string)kOwner;
        // NOTE: this stores strRequestJson as a string field. If you want a true array/object,
        // parse and recompose; otherwise this is OK if the reader knows to treat it as JSON text.
    string strPayload = llList2Json(JSON_OBJECT, [
        "resident",   (string)kOwner,
        "name",       strResidentName,
        "selections", strRequestJson,
        "timestamp",  (string)llGetUnixTime()
    ]);

    // IMPORTANT: keep the handle so we can detect success in dataserver
    kKVPWrite = llUpdateKeyValue(strKvpKey, strPayload, FALSE, "");
}




// Build a no-iframe wrapper with a visible spinner.
// It injects HUD_URL, NONCE, and LANG for app.js, then loads CSS/JS from GitHub.
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

    http_request(key id, string method, string body)
    {
        llOwnerSay("http_request: method == "+method+" and body == "+body);

        if (method == URL_REQUEST_GRANTED)
        {
            gURL = body;
            llSetLinkMedia(LINK_THIS, iFace, [
                PRIM_MEDIA_HOME_URL,            gURL,
                PRIM_MEDIA_CURRENT_URL,         gURL,
                PRIM_MEDIA_AUTO_PLAY,           TRUE,
                PRIM_MEDIA_FIRST_CLICK_INTERACT,TRUE,
                PRIM_MEDIA_PERMS_INTERACT,      PRIM_MEDIA_PERM_NONE,
                PRIM_MEDIA_PERMS_CONTROL,       PRIM_MEDIA_PERM_NONE,
                PRIM_MEDIA_WHITELIST_ENABLE,    FALSE
            ]);
            llSetTimerEvent(0.5); // optional nudge
        }
        // --- default state ---
        else if (method == "GET")
        {
            // 2-letter lang from Accept-Language
            string accept = llGetHTTPHeader(id, "accept-language"); string lang="en";
            integer c=llSubStringIndex(accept, ","); if(~c) accept=llGetSubString(accept,0,c-1);
            integer s=llSubStringIndex(accept, ";"); if(~s) accept=llGetSubString(accept,0,s-1);
            if (llStringLength(accept)>=2) lang = llToLower(llGetSubString(accept,0,1));

            llSetContentType(id, CONTENT_TYPE_HTML);  // <-- REQUIRED
            llHTTPResponse(id, 200, buildWrapperHTML(gURL, strNonce, lang));
            //llSetContentType(id, CONTENT_TYPE_HTML);
            //llHTTPResponse(id, 200, "<!doctype html><meta charset='utf-8'><body style='color:#fff;background:#111'>HELLO</body>");


            state running; // switch after sending the first page
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
        llOwnerSay("state running");
        llOwnerSay("Free memory: "+(string)llGetFreeMemory());
        llSetTimerEvent(fKVLifespan);//release help button if no response in fKVLifespan seconds (120.0)
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
       // kUrlReq = llRequestURL();

    }

    experience_permissions(key agent)
    {
        llDetachFromAvatar();
    }
    changed(integer change)
    {
        if(change & CHANGED_REGION){
            llRequestExperiencePermissions(kOwner,"");
        }
    }


    http_request(key id, string method, string body)
    {
        // This event fires for both: URL grant and subsequent POSTs from page
        llOwnerSay("http_request event line 413: method == "+method+", and body == "+body);
   
        if (method == URL_REQUEST_GRANTED) {
            llOwnerSay("URL request granted");
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
// --- running state ---
        if (method == "GET")
        {
            string accept = llGetHTTPHeader(id, "accept-language"); string lang="en";
            integer c=llSubStringIndex(accept, ","); if(~c) accept=llGetSubString(accept,0,c-1);
            integer s=llSubStringIndex(accept, ";"); if(~s) accept=llGetSubString(accept,0,s-1);
            if (llStringLength(accept)>=2) lang = llToLower(llGetSubString(accept,0,1));

            llSetContentType(id, CONTENT_TYPE_HTML);  // <-- REQUIRED
            llHTTPResponse(id, 200, buildWrapperHTML(gURL, strNonce, lang));
            return;
        }



                // Handle the POST from the UI
            else if (method == "POST")
            {
                // ----- your existing POST parsing/validation stays unchanged -----
                // (…the code you pasted is fine…)
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

                // Send a tiny HTML page so the hidden iframe reliably fires 'load'
                // and also notifies the parent page via postMessage.
                llSetContentType(id, CONTENT_TYPE_HTML);
                llHTTPResponse(id, 200,
                    "<!doctype html><meta charset='utf-8'><title>OK</title>"+
                    "<script>try{parent&&parent.postMessage('help_ok','*')}catch(e){}</script>"+
                    "OK"
                );

                write_kvp(posted);
                return;
            }



        // For any other method:
        llHTTPResponse(id, 405, "Method Not Allowed");
    }

    dataserver(key kID, string strData)
    {
        integer iSuccess = (integer)llGetSubString(strData, 0, 0);
        strData = llDeleteSubString(strData, 0, 1);

        if (kID == kKVPWrite)
        {
            if (!iSuccess)
            {
                // Optionally, report the failure
                llOwnerSay("Could not save your request: " + llGetExperienceErrorMessage((integer)strData));
                state detach;
            }

            // KVP write succeeded — now notify the Help Button (rezzer)
            // Send a tiny JSON with just enough info for the Help Button to know what to read.
            string strPing = llList2Json(JSON_OBJECT, [
                "type",      "help_request_kvp",
                "resident",  (string)kOwner,
                "kvp_key",   (string)(strKVPPrefix + (string)kOwner)
            ]);

            // Use a private channel. Region-targeted, object-to-object.
            // Syntax: llRegionSayTo(targetKey, channel, message)
            llRegionSayTo(kRezzer, iCommsChannel, strPing);
        }
        state detach;
    }


    timer()
    {
        if (iTimerStart && (llGetUnixTime() - iTimerStart) >= fHTTPTimeout) {
            llOwnerSay("Timed out waiting for the help page. Please try again.");
            llDetachFromAvatar();
        }
    }
}

state detach{
    state_entry()
    {
        llSetTimerEvent(5.0);
    }

    timer()
    {
        llRequestExperiencePermissions(kOwner,"");
    }
    changed(integer change)
    {
        if(change & CHANGED_REGION){
            llRequestExperiencePermissions(kOwner,"");
        }
    }
    experience_permissions(key agent)
    {
        llDetachFromAvatar();
    }
}
