

default
{
    touch_end(integer total_number)
    {
        key toucher = llDetectedKey(0);
        string lang = llGetAgentLanguage(toucher);

        // Get message for this language
        string message = llJsonGetValue(gTranslations, [lang]);

        // If not found, fall back to English
        if (message == "")
            message = llJsonGetValue(gTranslations, ["en"]);

        llRegionSayTo(toucher, 0, message);
    }
}
