// ──────────────────────────────
// Config
// ──────────────────────────────
float fMENTOR_WAIT = 18.0;      // seconds to wait for each mentor before moving on
float fTOTAL_TTL   = 120.0;     // seconds until the whole request expires

// ──────────────────────────────
// Transient state for one help attempt
// ──────────────────────────────
string strRequestID;            // minted per attempt (opaque)
string strNonce;                // minted per attempt (handshake)
integer iExpiresAt;            // unix time when invite becomes invalid
integer iClaimed;              // TRUE once a mentor accepts
list lMentors = [];         // filtered + randomized mentor entries (each a JSON map string)
integer iMentorIdx = -1;       // which mentor we’re currently pinging
key kLastHttpReq = NULL_KEY; // last llHTTPRequest id
string strCurrentMentorURL = "";  // URL of mentor being pinged (for optional cancel)
string strButtonCapURL = "";      // set this when your button receives llRequestURL

// Info about the requester (set these earlier in your flow)
key kRequesterID;          // avatar who touched the button
string strRequesterName;        // resolved or passed from HUD
vector  vRequesterLocalPos;    // snapshot when request starts

// ──────────────────────────────
// Entry point: call when HUD pings “ready”
// (You’ll have parsed that ping in listen() / on_rez() etc.)
// ──────────────────────────────
startHelpNotify()
{
    // Mint tokens (opaque, per attempt)
    strRequestID = (string)llGenerateKey();
    strNonce     = (string)llGenerateKey();
    iExpiresAt = (integer)llGetUnixTime() + (integer)fTOTAL_TTL;
    iClaimed   = FALSE;

    // Capture a location snapshot from the Button side
    string region = llGetRegionName();
    vector pos    = vRequesterLocalPos; // you populated this at touch-time; ok if it equals llGetPos()

    // Build handy links
    // Human-friendly SLURL
    string slurl = "https://maps.secondlife.com/secondlife/"
        + llEscapeURL(region) + "/"
        + (string)((integer)pos.x) + "/"
        + (string)((integer)pos.y) + "/"
        + (string)((integer)pos.z);

    // App deep link for teleport
    string app_teleport = "secondlife:///app/teleport/"
        + llEscapeURL(region) + "/"
        + (string)((integer)pos.x) + "/"
        + (string)((integer)pos.y) + "/"
        + (string)((integer)pos.z);

    // App deep link to open IM with the resident (this is what you asked to add)
    string app_im = "secondlife:///app/agent/" + (string)gRequesterID + "/im";

    // Build the payload every Mentor HUD receives
    // (Use JSON map to avoid manual escaping)
    string request_json = llList2Json(JSON_MAP, [
        "type",          "help_request",
        "request_id",    strRequestID,
        "nonce",         strNonce,
        "expires_at",    (string)iExpiresAt,

        // Who needs help
        "requester_id",   (string)gRequesterID,
        "requester_name", gRequesterName,

        // Where they are (snapshot)
        "region_name",    region,
        "pos_local",      (string)pos,            // "(x, y, z)"
        "slurl",          slurl,
        "app_teleport",   app_teleport,
        "app_im",         app_im,

        // Where to reply (the Button’s own cap URL)
        "cap_url",        gButtonCapURL
    ]);

    // 1) Load/refresh your mentor presence list from KVP (not shown here).
    //    Populate lMentors with JSON maps that include at least "hud_url".
    //    Apply your filters (availability, freshness, roles, etc.).

    if (llGetListLength(lMentors) == 0)
    {
        // Graceful failure: nobody to call
        notifyResidentNoMentors();
        return;
    }

    // 2) Randomise once per attempt to avoid bias
    lMentors    = llListRandomize(lMentors, 1);
    iMentorIdx  = -1;

    // Stash the request JSON for reuse between mentors
    llSetPrimitiveParams([PRIM_DESC, request_json]); // cheap local stash; or keep it in a global

    // 3) Kick off the first contact
    contactNextMentor();
}

// ──────────────────────────────
// Contact the next mentor (one at a time)
// ──────────────────────────────
contactNextMentor()
{
    if (iClaimed) return;

    iMentorIdx++;
    if (iMentorIdx >= llGetListLength(lMentors))
    {
        notifyResidentTimedOut();
        return;
    }

    string mentor = llList2String(lMentors, iMentorIdx);
    string url    = llJsonGetValue(mentor, ["hud_url"]); // presence writer should provide this
    if (url == "")
    {
        // Skip bad entries
        contactNextMentor();
        return;
    }

    gCurrentMentorURL = url;

    string request_json = (string)llGetObjectDesc(); // retrieve the payload we stashed

    // POST to the Mentor HUD
    gLastHttpReq = llHTTPRequest(
        url,
        [ HTTP_METHOD,  "POST",
          HTTP_MIMETYPE,"application/json" ],
        request_json
    );

    // Wait for accept/decline; if nothing comes, move on
    llSetTimerEvent(fMENTOR_WAIT);
}

// ──────────────────────────────
timer()
{
    // Per-mentor timeout
    if (!iClaimed)
        contactNextMentor();
}

// ──────────────────────────────
// Button’s cap handler: HUDs reply here with accept/decline
// ──────────────────────────────
http_request(key id, string method, string body)
{
    if (method == URL_REQUEST_GRANTED)
    {
        gButtonCapURL = body;
        llHTTPResponse(id, 200, "OK");
        return;
    }
    if (method == "POST")
    {
        string contentType = llGetHTTPHeader(id, "content-type");
        // We expect application/json
        string action   = llJsonGetValue(body, ["action"]);
        string req_id   = llJsonGetValue(body, ["request_id"]);
        string nonce    = llJsonGetValue(body, ["nonce"]);
        string mentorID = llJsonGetValue(body, ["mentor_id"]);

        // Basic guard: wrong request
        if (req_id != strRequestID)
        {
            llSetContentType(id, CONTENT_TYPE_JSON);
            llHTTPResponse(id, 409, "{\"status\":\"wrong_request\"}");
            return;
        }

        integer now = (integer)llGetUnixTime();

        if (action == "accept")
        {
            if (!iClaimed && (nonce == strNonce) && (now < iExpiresAt))
            {
                iClaimed = TRUE;
                llSetTimerEvent(0.0);

                // Acknowledge winner
                llSetContentType(id, CONTENT_TYPE_JSON);
                llHTTPResponse(id, 200, "{\"status\":\"claimed\"}");

                // Optional: cancel current in-flight invite to reduce HUD noise
                // sendCancelToCurrentMentor(); // (implement if you like)

                // Tell the resident who accepted
                notifyResidentAccepted(mentorID);

                // Cleanup / analytics here (KVP write, etc.)
                return;
            }
            // Late or invalid accept
            llSetContentType(id, CONTENT_TYPE_JSON);
            llHTTPResponse(id, 409, "{\"status\":\"already_claimed_or_invalid\"}");
            return;
        }
        else if (action == "decline")
        {
            // Let the loop continue immediately
            llSetContentType(id, CONTENT_TYPE_JSON);
            llHTTPResponse(id, 200, "{\"status\":\"ok\"}");
            if (!iClaimed)
            {
                llSetTimerEvent(0.0);
                contactNextMentor();
            }
            return;
        }

        // Unknown action
        llSetContentType(id, CONTENT_TYPE_JSON);
        llHTTPResponse(id, 400, "{\"status\":\"bad_action\"}");
        return;
    }

    // Non-POST, just be polite
    llHTTPResponse(id, 405, "Method Not Allowed");
}

// ──────────────────────────────
// Optional: if you want to tell an in‑flight mentor to stop showing UI
// (You’d define the HUD side to react to this)
// ──────────────────────────────
sendCancelToCurrentMentor()
{
    if (gCurrentMentorURL == "") return;

    string cancelJSON = llList2Json(JSON_MAP, [
        "type",       "help_request_cancel",
        "request_id", strRequestID
    ]);

    llHTTPRequest(
        gCurrentMentorURL,
        [ HTTP_METHOD,  "POST",
          HTTP_MIMETYPE,"application/json" ],
        cancelJSON
    );
}

// ──────────────────────────────
// Notify resident helpers (implement as you prefer)
// ──────────────────────────────
notifyResidentAccepted(string mentorID)
{
    // Example: IM/region say/hover text
    llRegionSayTo(gRequesterID, 0,
        "A mentor has accepted your request. (Mentor: " + mentorID + ")");
}

notifyResidentTimedOut()
{
    llRegionSayTo(gRequesterID, 0,
        "Sorry, we couldn’t reach an available mentor right now. Please try again in a minute.");
}

notifyResidentNoMentors()
{
    llRegionSayTo(gRequesterID, 0,
        "No mentor HUDs are online right now. Please try again shortly.");
}
