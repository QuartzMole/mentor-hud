integer iCommsChannel   = -710672827;
integer iHandle;


key kToucher;          // avatar who touched the button
key kHUD;

string strHUD;
string strTranslations;

// ──────────────────────────────
// Config
// ──────────────────────────────
float fMENTOR_WAIT = 18.0;      // seconds to wait for each mentor before moving on
float fTOTAL_TTL   = 120.0;     // seconds until the whole request expires

// ──────────────────────────────
// Transient state for one help attempt
// ──────────────────────────────

integer iExpiresAt;            // unix time when invite becomes invalid
integer iClaimed;              // TRUE once a mentor accepts
integer iMentorIdx = -1;       // which mentor we’re currently pinging

key kLastHttpReq = NULL_KEY; // last llHTTPRequest id
key kButtonCapURL;
key kHttpRequest;

list lTemp;
list lMentors = [];         // filtered + randomized mentor entries (each a JSON map string)

string strRequestID;            // minted per attempt (opaque)
string strNonce;                // minted per attempt (handshake)
string strCurrentMentorURL = "";  // URL of mentor being pinged (for optional cancel)
string strButtonCapURL = "";      // set this when your button receives llRequestURL
string strKVPKey = "WelcomeHUBMentorsOnline~";
string strKVPRequest;
// Info about the requester (set these earlier in your flow)

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
    lTemp = llGetObjectDetails(kToucher,[OBJECT_POS,OBJECT_ROT]);
    if(lTemp == []){
    	llResetScript();
    }
    vector pos    = llList2Vector(lTemp,0);
    pos+=<2.0,0.0,0.0>*llList2Rot(lTemp,1);//arrive just in front of pos

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
        "cap_url",        kButtonCapURL
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

default
{
	state_entry()
	{
		strHUD = llGetInventoryName(INVENTORY_OBJECT,0);
        strTranslations = "{}";

        // add translations one by one
        strTranslations = llJsonSetValue(strTranslations, ["en"], 
            "The help button is in use at the moment. Please try again in a minute or two.");
        strTranslations = llJsonSetValue(strTranslations, ["da"], 
            "Hjælpeknappen er i brug i øjeblikket. Prøv venligst igen om et minut eller to.");
        strTranslations = llJsonSetValue(strTranslations, ["de"], 
            "Die Hilfetaste wird gerade benutzt. Bitte versuchen Sie es in ein oder zwei Minuten erneut.");
        strTranslations = llJsonSetValue(strTranslations, ["es"], 
            "El botón de ayuda está en uso en este momento. Por favor, inténtelo de nuevo en uno o dos minutos.");
        strTranslations = llJsonSetValue(strTranslations, ["fr"], 
            "Le bouton d’aide est utilisé pour le moment. Veuillez réessayer dans une minute ou deux.");
        strTranslations = llJsonSetValue(strTranslations, ["it"], 
            "Il pulsante di aiuto è attualmente in uso. Riprova tra un minuto o due.");
        strTranslations = llJsonSetValue(strTranslations, ["hu"], 
            "A súgó gomb jelenleg használatban van. Kérjük, próbálja meg újra egy-két perc múlva.");
        strTranslations = llJsonSetValue(strTranslations, ["pl"], 
            "Przycisk pomocy jest obecnie używany. Spróbuj ponownie za minutę lub dwie.");
        strTranslations = llJsonSetValue(strTranslations, ["pt"], 
            "O botão de ajuda está em uso no momento. Tente novamente em um ou dois minutos.");
        strTranslations = llJsonSetValue(strTranslations, ["tr"], 
            "Yardım düğmesi şu anda kullanımda. Lütfen bir veya iki dakika içinde tekrar deneyin.");
        strTranslations = llJsonSetValue(strTranslations, ["ja"], 
            "ヘルプボタンは現在使用中です。1〜2分後にもう一度お試しください。");
        strTranslations = llJsonSetValue(strTranslations, ["ko"], 
            "도움말 버튼이 현재 사용 중입니다. 1~2분 후에 다시 시도해 주세요.");
        strTranslations = llJsonSetValue(strTranslations, ["zh"], 
            "帮助按钮当前正在使用中。请在一两分钟后再试。");
        strTranslations = llJsonSetValue(strTranslations, ["zh-tw"], 
            "幫助按鈕目前正在使用中。請在一兩分鐘後再試。");
    }


	changed(integer change)
	{
		if (change & CHANGED_INVENTORY){
			llResetScript();
		}
	}

	touch_end(integer num_detected)
	{
		kToucher  = llDetectedKey(0);
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
		state listening;
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
	        string message = llJsonGetValue(strTranslations, [lang]);

	        // fall back to English if missing
	        if (message == "")
	            message = llJsonGetValue(strTranslations, ["en"]);

	        llRegionSayTo(k, 0, message);
			return;
		}

	}

	state_exit()
	{
		llSetTimerEvent(0.0);
	}

	listen(integer channel, string name, key id, string message)
	{
		llListenRemove(iHandle);
		message = llStringTrim(message,STRING_TRIM);
		if(llStringLength(message)){
			//process the message
			llReleaseURL(kButtonCapURL);
			kHttpRequest = llRequestURL();
			state summoningMentor;
		}
		else{
			state default;
		}
	}

	http_request(key id, string method, string body)
	{
		if(kHttpRequest!=id){
			return;
		}
	    if (method == URL_REQUEST_GRANTED)
	    {
	        gButtonCapURL = body;
	        llHTTPResponse(id, 200, "OK");
	        state summoningMentor;
	    }
	}

	timer()
	{
		if(!~llListFindList(llGetAttachedListFiltered(kToucher,[FILTER_FLAGS,FILTER_FLAG_HUDS]),[kHUD])){
			llResetScript();
		}
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

state summoningMentor{
	state_entry()
	{
		kKVPRequest = llReadKeyValue(strKVPRequest = strKVPKey);
		startHelpNotify();
	}

	dataserver(key queryid, string data)
	{
		if(queryid == kKVPRequest){
			integer success = (integer)llGetSubString(data,0,0);
			data = llDeleteSubString(data,0,1);
			if(success){
				
			}
		}
	}

	http_request(key id, string method, string body)
	{


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
}