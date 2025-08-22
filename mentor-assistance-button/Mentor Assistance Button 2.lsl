integer iCommsChannel   = -710672827;
integer iHandle;


key kToucher;
key kHUD;

string strHUD;
string gTranslations;

default
{
	state_entry()
	{
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

	listen(integer channel, string name, key id, string message)
	{
		llListenRemove(iHandle);
		message = llStringTrim(message,STRING_TRIM);
		if(llStringLength(message)){
			//process the message
			state summoningMentor;
		}
		else{
			state default;
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
		
	}
}