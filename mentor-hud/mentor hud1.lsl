// ===== Mentor HUD: presence writer =====
string  KVP_PREFIX = "mentor_presence:";
string  gPresenceKey;              // mentor_presence:<owner-uuid>
string  gMyURL = "";
integer HEARTBEAT = 30;            // seconds
integer gKVPBusy = FALSE;          // simple guard to avoid overlapping writes

// Track outstanding KVP ops so we know which reply is for what
integer OP_NONE   = 0;
integer OP_CREATE = 1;
integer OP_UPDATE = 2;
integer OP_READ   = 3;
integer gLastOp   = OP_NONE;

updatePresence(integer createFirst)
{
    if (gKVPBusy) return;
    gKVPBusy = TRUE;

    key me = llGetOwner();
    gPresenceKey = KVP_PREFIX + (string)me;

    // Build presence JSON
    string payload = llList2Json(JSON_MAP, [
        "mentor_id",     (string)me,
        "display_name",  llGetDisplayName(me),
        "hud_url",       gMyURL,
        "last_seen",     (string)((integer)llGetUnixTime()),
        "region_name",   llGetRegionName(),
        // Optional flags you can filter on later:
        "available",     "true"   // "true"/"false" as strings; or use a JSON boolean via JSON_TRUE
    ]);

    if (createFirst)
    {
        gLastOp = OP_CREATE;
        llCreateKeyValue(gPresenceKey, payload);
    }
    else
    {
        gLastOp = OP_UPDATE;
        llUpdateKeyValue(gPresenceKey, payload, FALSE,"");
    }
}

bumpPresenceHeartbeat()
{
    // Keep last_seen fresh without changing URL
    updatePresence(FALSE);
}

default
{
    state_entry()
    {
        // Ask for URL at start (also triggers on attach)
        llRequestURL();
    }

    attach(key id)
    {
        if (id) { // attached
            llRequestURL();
        } else {
            // detached — optionally clear presence
            // llDeleteKeyValue(gPresenceKey);
            llSetTimerEvent(0.0);
        }
    }

    changed(integer c)
    {
        if (c & (CHANGED_REGION | CHANGED_TELEPORT | CHANGED_REGION_START))
        {
            // Region move invalidates old assumptions; get a fresh URL and write presence
            llRequestURL();
        }
    }

    http_request(key id, string method, string body)
    {
        if (method == URL_REQUEST_GRANTED)
        {
            gMyURL = body;                 // save our callback URL
            updatePresence(TRUE);          // try create; we'll fall back to update if it exists
            llHTTPResponse(id, 200, "OK");

            // (Re)start heartbeat
            llSetTimerEvent((float)HEARTBEAT);
            return;
        }
        else if (method == URL_REQUEST_DENIED)
        {
            // You may want to log/notify; presence write will fail without a URL
            llHTTPResponse(id, 200, "Denied");
            return;
        }

        // Not expecting other incoming HTTP here
        llHTTPResponse(id, 405, "Method Not Allowed");
    }

    timer()
    {
        bumpPresenceHeartbeat();
    }

    dataserver(key qid, string data)
    {
        // KVP reply format you gave: "1,<payload>" or "0,<error_code>"
        integer ok = (integer)llGetSubString(data, 0, 0);
        string tail = llDeleteSubString(data, 0, 1);

        if (gLastOp == OP_CREATE)
        {
            if (ok)
            {
                // Created successfully
                gKVPBusy = FALSE;
                gLastOp = OP_NONE;
            }
            else
            {
                // If it already exists, update instead; otherwise just report
                // We can't directly compare numeric codes portably here, so just try update.
                gLastOp = OP_UPDATE;
                llUpdateKeyValue(gPresenceKey, llList2Json(JSON_MAP, [
                    "mentor_id",     (string)llGetOwner(),
                    "display_name",  llGetDisplayName(llGetOwner()),
                    "hud_url",       gMyURL,
                    "last_seen",     (string)((integer)llGetUnixTime()),
                    "region_name",   llGetRegionName(),
                    "available",     "true"
                ]),FALSE,"");
            }
        }
        else if (gLastOp == OP_UPDATE)
        {
            // Update succeeded? ok==1; else you can inspect tail via llGetExperienceErrorMessage.
            gKVPBusy = FALSE;
            gLastOp = OP_NONE;

            if (!ok)
            {
                // Optional debug:
                llOwnerSay("Presence update failed: " + llGetExperienceErrorMessage((integer)tail));
            }
        }
        // (We’re not using OP_READ here in the HUD.)
    }
}
