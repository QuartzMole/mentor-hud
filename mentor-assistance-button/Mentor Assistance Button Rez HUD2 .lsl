integer iCommsChannel   = -710672827;
integer iHandle;


key kToucher;
key kHUD;

string strHUD;
string gTranslations;


key     kReadReq      = NULL_KEY;       // handle for llReadKeyValue
string  strKVPPrefix  = "request|";     // same as HUD used
string  strPendingRequest = "";         // already used by processingMessage
string  ROSTER_KEY  = "mentor_roster";   // KVP key to publish

// =============================
// Helpers & globals for processingMessage
// =============================
        // set this in your listen() before changing state
string  strPresencePrefix = "presence|"; // presence keys look like "presence|<avatar-key>" -> URL string

list    lPresenceKeys = [];              // raw presence keys returned by llKeysKeyValue
list    lUrlQueue     = [];              // flattened [kMentor, strUrl, kMentor, strUrl, ...] randomized
integer iQueueIndex   = 0;               // index into lUrlQueue (points at a mentor key)
//key     kKVPQuery     = NULL_KEY;        // handle for llKeysKeyValue / llReadKeyValue
key     kHTTPReq      = NULL_KEY;        // current HTTP request handle
key     kCurrentMentor= NULL_KEY;        // mentor whose HUD we’re currently trying
float   fStepTimeout  = 10.0;            // per-HUD timeout seconds
float   fOverallLimit = 120.0;           // overall guard (you already use llGetTime() in default)
integer iAwaitingHTTP = FALSE;           // whether we’re waiting on an http_response



key kRosterRead;

string strReadPrefix = "";
integer iReadChunks = 0;
integer iReadsOutstanding;
integer iReadPending = 0;
list lReadCSVs = [];
list lReadUUIDs = [];
list lMentorRoster;

key kReadMetaReq;





readRoster() {
    kReadMetaReq = llReadKeyValue(ROSTER_KEY + ".meta");
}


startPresenceFromRoster()
{
    lUrlQueue     = [];
    lPresenceKeys = [];
    iQueueIndex   = 0;
    iReadsOutstanding = 0;

    integer i; integer n = llGetListLength(lMentorRoster);
    if (n == 0)
    {
        llRegionSayTo(kToucher, 0, "No mentor roster is configured.");
        llResetScript();
    }

    // Build the exact presence keys we will read, then read them.
    for (i = 0; i < n; ++i)
    {
        key kMentor = (key)llList2String(lMentorRoster, i);
        string strPKey = strPresencePrefix + (string)kMentor;
        lPresenceKeys += [ strPKey ];

        // Asynchronous read; result arrives in dataserver
        llReadKeyValue(strPKey);
        ++iReadsOutstanding;
    }
}


string buildNotifyBody(string strRequestJson)
{
    // We’ll build up the object step-by-step.
    string strOut = "{}";

    if (llJsonValueType(strRequestJson, []) != JSON_INVALID)
    {
        // Valid JSON from the HUD: wrap it as { "type":"help_request", "payload": <that JSON> }
        strOut = llJsonSetValue(strOut, ["type"], "help_request");
        strOut = llJsonSetValue(strOut, ["payload"], strRequestJson);
        return strOut;
    }

    // Fallback: not valid JSON — keep the original text under "payload_raw"
    strOut = llJsonSetValue(strOut, ["type"], "help_request");
    strOut = llJsonSetValue(strOut, ["payload_raw"], strRequestJson);
    return strOut;
}



// Advance to next mentor in the queue (randomised) and POST to their HUD URL.
tryNextMentor()
{
    if (iAwaitingHTTP) return; // Don’t double-fire
    if (iQueueIndex >= llGetListLength(lUrlQueue))
    {
        // No more mentors to try
        llRegionSayTo(kToucher, 0,
            "Sorry — no mentors accepted in time. If you still need help, please touch the button and try again.");
        llResetScript();

    }

    kCurrentMentor = (key)llList2String(lUrlQueue, iQueueIndex);
    string strUrl  = llList2String(lUrlQueue, iQueueIndex + 1);

    // POST JSON directly (LSL wiki: llHTTPRequest, use HTTP_MIMETYPE + HTTP_METHOD)
    string strBody = buildNotifyBody(strPendingRequest);
    kHTTPReq = llHTTPRequest(
        strUrl,
        [ HTTP_METHOD, "POST",
          HTTP_MIMETYPE, "application/json" ],
        strBody
    );

    // Arm per-step timeout
    iAwaitingHTTP = TRUE;
    llSetTimerEvent(fStepTimeout);
}




// Notify the next mentor in lUrlQueue using strPendingRequest.
// Assumes lUrlQueue, iQueueIndex, strPendingRequest already set.
key     kNotifyReq;
integer iNotifyTimeoutSec = 8;
integer iNotifyAttempts = 0;
integer iNotifyMaxAttempts = 1;
integer bWaitingNotify = FALSE;

sendNextMentor()
{
    // If we've exhausted the queue, stop here.
    integer total = llGetListLength(lUrlQueue);
    if (iQueueIndex >= total) {
        // Nobody accepted / no more URLs
        llRegionSayTo(kToucher, 0, "No mentors accepted the request at this time. Please try again shortly.");
        // Decide your flow (e.g., return to idle state or reset)
        // state default; // if your idle state is default
        return;
    }

    // Get current mentor URL
    string url = llList2String(lUrlQueue, iQueueIndex);

    // Basic sanity
    if (llStringLength(url) == 0 || llSubStringIndex(url, "http") != 0) {
        // Skip bad URL and move on
        ++iQueueIndex;
        sendNextMentor();
        return;
    }

    // (Re)start attempt counter for this index if first try
    if (!bWaitingNotify) {
        iNotifyAttempts = 0;
    }

    // Fire HTTP POST to the mentor HUD URL with your JSON body
    kNotifyReq = llHTTPRequest(
        url,
        [
            HTTP_METHOD, "POST",
            HTTP_MIMETYPE, "application/json",
            HTTP_VERIFY_CERT, TRUE
            // You can add HTTP_CUSTOM_HEADER, "X-Request-Type", "mentor_help", etc. if your HUD expects it
        ],
        strPendingRequest
    );

    // Start/refresh the timer for this attempt
    bWaitingNotify = TRUE;
    ++iNotifyAttempts;
    llSetTimerEvent((float)iNotifyTimeoutSec);
}
default
{
    state_entry()
    {
        llSetTimerEvent(0.0);
        strHUD = llGetInventoryName(INVENTORY_OBJECT,0);
        gTranslations = "{}";

        // add translations one by one
        gTranslations = llJsonSetValue(gTranslations, ["en"], 
            "The help button is in use at the moment. Please try again in a minute or two.");
        gTranslations = llJsonSetValue(gTranslations, ["da"], 
            "Hjælpeknappen er i brug i øjeblikket. Prøv venligst igen om et minut eller to.");
        gTranslations = llJsonSetValue(gTranslations, ["de"], 
            "Die Hilfetaste wird gerade benutzt. Bitte versuchen Sie es in ein oder zwei Minuten erneut.");
        gTranslations = llJsonSetValue(gTranslations, ["es"], 
            "El botón de ayuda está en uso en este momento. Por favor, inténtelo de nuevo en uno o dos minutos.");
        gTranslations = llJsonSetValue(gTranslations, ["fr"], 
            "Le bouton d’aide est utilisé pour le moment. Veuillez réessayer dans une minute ou deux.");
        gTranslations = llJsonSetValue(gTranslations, ["it"], 
            "Il pulsante di aiuto è attualmente in uso. Riprova tra un minuto o due.");
        gTranslations = llJsonSetValue(gTranslations, ["hu"], 
            "A súgó gomb jelenleg használatban van. Kérjük, próbálja meg újra egy-két perc múlva.");
        gTranslations = llJsonSetValue(gTranslations, ["pl"], 
            "Przycisk pomocy jest obecnie używany. Spróbuj ponownie za minutę lub dwie.");
        gTranslations = llJsonSetValue(gTranslations, ["pt"], 
            "O botão de ajuda está em uso no momento. Tente novamente em um ou dois minutos.");
        gTranslations = llJsonSetValue(gTranslations, ["tr"], 
            "Yardım düğmesi şu anda kullanımda. Lütfen bir veya iki dakika içinde tekrar deneyin.");
        gTranslations = llJsonSetValue(gTranslations, ["ja"], 
            "ヘルプボタンは現在使用中です。1〜2分後にもう一度お試しください。");
        gTranslations = llJsonSetValue(gTranslations, ["ko"], 
            "도움말 버튼이 현재 사용 중입니다. 1~2분 후에 다시 시도해 주세요.");
        gTranslations = llJsonSetValue(gTranslations, ["zh"], 
            "帮助按钮当前正在使用中。请在一两分钟后再试。");
        gTranslations = llJsonSetValue(gTranslations, ["zh-tw"], 
            "幫助按鈕目前正在使用中。請在一兩分鐘後再試。");

        readRoster();
    }

    dataserver(key kID, string strData)
    {
        integer iSuccess = (integer)llGetSubString(strData, 0, 0);
        strData = llDeleteSubString(strData, 0, 1);
        if (kID == kReadMetaReq) {
            if (!iSuccess) {
                llOwnerSay("❌ Roster meta read failed: " + llGetExperienceErrorMessage((integer)strData));
                return;
            }
            // strData is JSON: {"ver":1,"prefix":"mentor_roster.v<ts>.","chunks":N,...}
            strReadPrefix = llJsonGetValue(strData, ["prefix"]);
            iReadChunks = (integer)llJsonGetValue(strData, ["chunks"]);
            if (strReadPrefix == "" || iReadChunks <= 0) {
            llOwnerSay("❌ Roster meta malformed.");
            return;
            }
            // Request each chunk
            lReadCSVs = [];
            iReadPending = iReadChunks;
            integer i;
            for (i = 0; i < iReadChunks; ++i) {
            llReadKeyValue(strReadPrefix + (string)i);
            }
            return;
        }


        // --- Any chunk read? We don't track IDs individually; just count successes ---
        // If you need strict mapping, keep a map of requestId → index.
        if (iSuccess && iReadPending > 0) {
            // strData is a CSV string of UUIDs for one chunk
            lReadCSVs += [ strData ];
            --iReadPending;
            if (iReadPending == 0) {
                // Stitch into one big CSV and turn into a list
                string big = llDumpList2String(lReadCSVs, ",");
                lReadUUIDs  = llCSV2List(big);
                // Optional: dedupe to be safe
                list uniq = [];
                integer j; integer m = llGetListLength(lReadUUIDs);
                for (j = 0; j < m; ++j) {
                    string u = llList2String(lReadUUIDs, j);
                    if (llListFindList(uniq, [u]) == -1) uniq += [u];
                }
                if (kID == kRosterRead)
                {
                    if (!iSuccess) return;
                    // Accept CSV or JSON:
                    if (llJsonValueType(strData, []) != JSON_INVALID)
                    {
                        // JSON array of strings
                        lMentorRoster = llJson2List(strData);
                    }
                    else
                    {
                        lMentorRoster = llCSV2List(strData);
                    }
                }
            }

            // (the other dataserver branch shown above handles presence reads)
        }
    }

    changed(integer change)
    {
        if (change & CHANGED_INVENTORY){
            llResetScript();
        }
    }

    touch_end(integer num_detected)
    {
        if(llGetAgentSize(kToucher)!=ZERO_VECTOR && kToucher!=llDetectedKey(0)){
            return;
        }
        kToucher  = llDetectedKey(0);
        //rez temp hud to aclutter (turns perm when attached)
        llRezObjectWithParams(strHUD,[
            REZ_PARAM,TRUE,
            REZ_FLAGS,REZ_FLAG_TEMP,
            REZ_POS,<0.0,0.0,-2.>,TRUE,TRUE,
            REZ_PARAM_STRING,(string)kToucher
            ]);

    }

    object_rez(key id)
    {
        kHUD = id;
        llSetTimerEvent(1.0);
        llResetTime();
        
    }

    timer()
    {
        if(~llListFindList(llGetAttachedListFiltered(kToucher,[FILTER_FLAGS,FILTER_FLAG_HUDS]),[kHUD])){//HUD has attached to resident
            llSetTimerEvent(0.0);
            state listening;
        }
        if(llGetTime()>10.0 || llGetAgentSize(kToucher)==ZERO_VECTOR){//either HUD has not attached for some reason, or Av is no longer in the region, bail
            llResetScript();
        }
    }
}

state listening{
    state_entry()
    {
        //state change automatically removes old listener
        iHandle = llListen(iCommsChannel,"",kHUD,"");
        //llTextBox(kToucher,"What do you need help with?  Do you need help in a specific language?\n\nPlease enter a brief message and click \"Submit\".", iCommsChannel);
        llResetTime();
        llSetTimerEvent(1.0);
    }
    changed(integer change)
    {
        if (change & CHANGED_INVENTORY){
            llResetScript();
        }
    }

    touch_end(integer num_detected)
    {
        key k = llDetectedKey(0);
        if(k!=kToucher){
            string lang = llGetAgentLanguage(k);

            // look up translation
            string message = llJsonGetValue(gTranslations, [lang]);

            // fall back to English if missing
            if (message == "")
                message = llJsonGetValue(gTranslations, ["en"]);

            llRegionSayTo(k, 0, message);
            return;
        }
    }

    state_exit()
    {
        llSetTimerEvent(0.0);
    }

    listen(integer iChan, string strName, key kSpeaker, string strMsg)
    {
        // Expecting the HUD’s ping JSON:
        // {"type":"help_request_kvp","resident":"<uuid>","kvp_key":"request|<uuid>"}
        if (iChan != iCommsChannel) return;

        if (llJsonValueType(strMsg, []) == JSON_INVALID) return;
        string strType = (string)llJsonGetValue(strMsg, ["type"]);
        if (llToLower(strType) != "help_request_kvp") return;

        string strKvpKey = (string)llJsonGetValue(strMsg, ["kvp_key"]);
        if (strKvpKey == "")
        {
            // Fallback: reconstruct from resident if provided
            string strResident = (string)llJsonGetValue(strMsg, ["resident"]);
            if (strResident != "") strKvpKey = strKVPPrefix + strResident;
        }
        if (strKvpKey == "") return;

        // Pull the fresh payload from KVP (async -> dataserver)
        kReadReq = llReadKeyValue(strKvpKey);
    }

    dataserver(key kID, string strData)
    {
        integer iSuccess = (integer)llGetSubString(strData, 0, 0);
        strData = llDeleteSubString(strData, 0, 1);

        if (kID == kReadReq)
        {
            if (!iSuccess)
            {
                // Couldn’t read — you might tell the resident
                // llRegionSayTo(kToucher, 0, "Sorry — I couldn’t retrieve your request. Please try again.");
                return;
            }

            // strData now holds the value you wrote in the HUD’s write_kvp()
            // Example structure (as per your code):
            // { "resident": "...", "name": "...", "selections": "<JSON string>", "timestamp": "..." }
            // If you stored selections as JSON *string*, keep it as-is or parse/merge here.
            strPendingRequest = strData;

            // Hand off to the existing processing pipeline
            state processingMessage;
        }
    }
    timer()
    {
        if(llGetTime()>120.0){
            llRegionSayTo(kToucher,0,"Your request has timed out.  If you still need help, please touch the button and try again.");
            state default;
        }
        list l = llGetObjectDetails(kToucher,[OBJECT_POS]);
        if(l == []){ // avatar has left the region
            state default;
        }
        if(llVecDist(llGetPos(),llList2Vector(l,0))>15.0){//av has moved out of range
            state default;
        }
    }
}


state processingMessage
{
    state_entry()
    {
        // We assume strPendingRequest was set in listen() before switching state.
        // Defensive check:
        if (strPendingRequest == "")
        {
            llRegionSayTo(kToucher, 0, "Sorry — I didn’t receive your message correctly. Please try again.");
            state default;
            return;
        }

        // Reset per-state bookkeeping
        lPresenceKeys = [];
        lUrlQueue     = [];
        iQueueIndex   = 0;
        iAwaitingHTTP = FALSE;

        // Start the presence key enumeration (async -> dataserver)
        startPresenceFromRoster();

        // Also start an overall guard timer if you want. Your default state already uses llGetTime(),
        // but we can set an upper bound here too
        llResetTime();
    }

    // Handle both llKeysKeyValue and llReadKeyValue results
    // processingMessage: collect presence URLs from KVP reads
    dataserver(key q, string data)
    {
        // KVP replies are "1,<value>" on success, or "0,<errorcode>" on failure
        integer ok = (integer)llGetSubString(data, 0, 0);
        string  tail = llDeleteSubString(data, 0, 1);

        // We are in the middle of reading presence keys kicked off by startPresenceFromRoster()
        // iReadsOutstanding was incremented once per llReadKeyValue() call.
        if (iReadsOutstanding > 0)
        {
            if (ok)
            {
                // 'tail' is the value stored at this presence key (expected: the mentor HUD's URL)
                string url = tail;

                // Basic sanity: keep only plausible HTTP(S) URLs (non-empty)
                // and avoid duplicates in lUrlQueue.
                if (llStringLength(url) > 0 && llSubStringIndex(url, "http") == 0)
                {
                    if (llListFindList(lUrlQueue, [url]) == -1)
                    {
                        lUrlQueue += [ url ];
                    }
                }
                // else: empty/missing URL means mentor HUD isn't online/present; just skip
            }
            else
            {
                // Log the KVP read error but keep going
                integer err = (integer)tail;
                llOwnerSay("Presence read failed: " + llGetExperienceErrorMessage(err));
            }

            // One fewer read to account for
            --iReadsOutstanding;

            // When all presence reads have returned, proceed
            if (iReadsOutstanding == 0)
            {
                // If nobody had a live URL, bail politely
                if (llGetListLength(lUrlQueue) == 0)
                {
                    llRegionSayTo(kToucher, 0, "No mentors are currently available. Please try again shortly.");
                    // Decide your flow: either return to idle, or reset, or pop state
                    // Example: state default;  // if default is your idle state
                    return;
                }

                // Randomise order so we spread load fairly
                lUrlQueue = llListRandomize(lUrlQueue, 1);
                iQueueIndex = 0;

                // Hand over to your sender to actually notify mentors in sequence.
                // This should use lUrlQueue[iQueueIndex] and strPendingRequest,
                // and advance iQueueIndex as replies time out or decline.
                // (Keep your existing function name if you already have one.)
                sendNextMentor(); // <-- your function that begins the notify/forward loop
            }

            // We handled a presence read; nothing more to do in this event
            return;
        }

        // If you have other dataserver traffic in this state (notecard, userKey, etc.),
        // handle it below in additional branches. Otherwise, we ignore unrelated replies.
    }

    http_response(key id, integer status, list meta, string body)
    {
        if (id != kNotifyReq) return;

        // Stop the per-mentor timeout
        llSetTimerEvent(0.0);
        bWaitingNotify = FALSE;

        // Treat network/HTTP failure as a soft failure for this mentor
        integer ok = (status >= 200 && status < 300);

        // Your HUD can reply with a JSON like {"status":"accepted"} or {"accepted":true}
        // We'll accept on either "accepted": true or "status":"accepted" textually.
        integer accepted = FALSE;
        if (ok) {
            // Very light parsing without bringing in heavy JSON logic:
            // - look for the word accepted and either "true" or the string "accepted"
            // Adjust these heuristics to your actual HUD reply.
            if (llSubStringIndex(body, "\"accepted\"") != -1) {
                // crude: check for true
                if (llSubStringIndex(body, "true") != -1) accepted = TRUE;
            } else if (llSubStringIndex(body, "\"status\"") != -1 &&
                       llSubStringIndex(body, "accepted") != -1) {
                accepted = TRUE;
            }
        }

        if (accepted) {
            // Success path: a mentor accepted.
            llRegionSayTo(kToucher, 0, "A mentor is responding to your request. Thank you!");
            // Hand off to your success flow (e.g., go idle, or keep state to await mentor follow-up)
            state default; // if appropriate
            return;
        }

        // Not accepted / failure: either retry this mentor (if allowed) or advance to next
        if (!ok && iNotifyAttempts < iNotifyMaxAttempts) {
            // Retry the same mentor once (optional)
            sendNextMentor();
            return;
        }

        // Move to next mentor in queue
        ++iQueueIndex;
        sendNextMentor();
    }


    timer()
    {
        // Either per-step timeout (waiting for HTTP), or overall cap
        if (iAwaitingHTTP)
        {
            // Step timeout: move to next mentor
            iAwaitingHTTP = FALSE;
            llSetTimerEvent(0.0);
            iQueueIndex += 2;
            tryNextMentor();
            return;
        }

        // Overall guard (optional): if we’ve been here too long, bail
        if (llGetTime() > fOverallLimit)
        {
            llRegionSayTo(kToucher, 0,
                "Sorry — no mentors accepted in time. If you still need help, please touch the button and try again.");
            state default;
        }
    }

    state_exit()
    {
        // Clean up
        llSetTimerEvent(0.0);

        kHTTPReq       = NULL_KEY;
        iAwaitingHTTP  = FALSE;
        iQueueIndex    = 0;
        lPresenceKeys  = [];
        lUrlQueue      = [];
        kCurrentMentor = NULL_KEY;
    }
}


