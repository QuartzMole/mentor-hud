// LDPW Mentor Roster Publisher
// Reads a notecard and writes mentor_roster CSV to Experience KVP.
// Place in an admin-only object in an admin region.

string  strNotecard    = "Mentor Roster";   // name of the notecard to read
string  ROSTER_KEY  = "mentor_roster";   // KVP key to publish
string strName;
// --- internal state ---
integer iLineCount  = -1;
integer iLineLindex  = 0;
key     kNotecardLinesQueryID;
key     kNotecardQueryID;    
key     kNameToKeyQueryID;
key     kKVPRequest;
list    lUUIDs      = [];   // accumulated, normalized, de-duplicated


default
{
    state_entry() {
        strNotecard = llGetInventoryName(INVENTORY_NOTECARD,0);
        if(llGetInventoryType(strNotecard)!=INVENTORY_NOTECARD){
            llOwnerSay("There is no notecard here for me to read");
            return;
        }
        lUUIDs = [];
        iLineLindex = 0;
        iLineCount = -1;

        state readingNotecard;
    }

    on_rez(integer p) {
        llResetScript();
    }

    changed(integer change)
    {
        if(change & CHANGED_INVENTORY){
            llResetScript();
        }
    }
}
state readingNotecard{

    state_entry()
    {
        kNotecardLinesQueryID = llGetNumberOfNotecardLines(strNotecard);
        
    }

    on_rez(integer p) {
        llResetScript();
    }

    changed(integer c) {
        if (c & CHANGED_INVENTORY) {
            // notecard edited or replaced
            llOwnerSay("Roster publisher: notecard changed, reloading…");
            llResetScript();
        }
        if (c & (CHANGED_REGION | CHANGED_REGION_START)) {
            // (Optional) Re‑publish on region move/start
           llResetScript();
        }
    }

    touch_start(integer n) {
        if (llDetectedKey(0) != llGetOwner()) return;
        llOwnerSay("Roster publisher: manual refresh requested.");
        kNotecardLinesQueryID = llGetNumberOfNotecardLines(strNotecard);

    }

    dataserver(key q, string data)
    {
        if (q == kNotecardLinesQueryID){
            iLineCount = (integer)data;
            kNotecardQueryID = llGetNotecardLine(strNotecard,iLineLindex);
        }
        if (q == kNotecardQueryID) {
            data = llStringTrim(data,STRING_TRIM);
            if(data != EOF){            
                if(data !="" && llGetSubString(data,0,1)!="//"){//data comprises printing characters and is not commented out
                    strName = data;
                    kNameToKeyQueryID = llRequestUserKey(strName);
                }
            }
            else{
                if(lUUIDs!=[]){//if there are some uuids to send
                    kKVPRequest = llUpdateKeyValue(ROSTER_KEY,llList2CSV(lUUIDs),FALSE,"");//if ROSTER_KEY doesn't exist, this will create it just as well as llCreateKeyValue does
                }
                else{
                    llOwnerSay("The names on the notecard returned no valid UUIDs.  Please check and try again.");
                }
            }

        }

        else if (q == kNotecardQueryID){
            if((key)data!=NULL_KEY){
                lUUIDs+=[data];
            }
            else{
                llOwnerSay("I can't find a UUID for any resident called  "+strName+".\n\nPlease check spelling and that you're using their log in name or username, not their display name.");
            }
            ++iLineLindex;
            kNotecardQueryID = llGetNotecardLine(strNotecard,iLineLindex);
        }

        if (kKVPRequest == q) {
            // KVP replies use the same dataserver; handle ops by status char
            integer ok = (integer)llGetSubString(data, 0, 0);
            string  tail = llDeleteSubString(data, 0, 1);
            if(ok){
                llOwnerSay("updated "+ROSTER_KEY+" with the value "+tail);
            }
            else{
                llOwnerSay("could not update "+(ROSTER_KEY+" because "+llGetExperienceErrorMessage((integer)tail)));
            }
        }
    }
}
