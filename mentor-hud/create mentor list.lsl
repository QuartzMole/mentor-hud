// LDPW Mentor Roster Publisher
// Reads a notecard and writes mentor_roster CSV to Experience KVP.
// Place in an admin-only object in an admin region.

string  NOTECARD    = "Mentor Roster";   // name of the notecard to read
string  ROSTER_KEY  = "mentor_roster";   // KVP key to publish

// --- internal state ---
integer gLineCount  = -1;
integer gLineIndex  = 0;
key     gQueryID    = NULL_KEY;
list    gUUIDs      = [];   // accumulated, normalized, de-duplicated

// Track KVP ops
integer OP_NONE   = 0;
integer OP_CREATE = 1;
integer OP_UPDATE = 2;
integer gKvpOp    = OP_NONE;

// ─────────────────────────────────────────────────────────────
// Utility: normalize & validate UUID-ish strings
string normUUID(string s) {
    s = llToLower(llStringTrim(s, STRING_TRIM));
    if (llStringLength(s) != 36) return "";
    // quick sanity: must contain dashes
    if (llSubStringIndex(s, "-") == -1) return "";
    return s;
}

// Utility: push UUID into gUUIDs if valid + not present
addUUID(string s) {
    string u = normUUID(s);
    if (u == "") return;
    if (~llListFindList(gUUIDs, [u])) return;
    gUUIDs += [u];
}

// ─────────────────────────────────────────────────────────────
// Parse a single notecard line:
// - trims whitespace
// - ignores blank lines
// - ignores comments starting with "#" or "//"
// - accepts either: UUID
parseLine(string raw) {
    string line = llStringTrim(raw, STRING_TRIM);
    if (line == "") return;

    // comments?
    if (llSubStringIndex(line, "#") == 0) return;
    if (llSubStringIndex(line, "//") == 0) return;

    // If line contains commas, take the first field as UUID (future-proofing)
    list parts = llParseStringKeepNulls(line, [","], []);
    if (llGetListLength(parts) > 0) {
        addUUID(llList2String(parts, 0));
    }
}

// ─────────────────────────────────────────────────────────────
// Begin notecard read
beginRead() {
    if (llGetInventoryType(NOTECARD) != INVENTORY_NOTECARD) {
        llOwnerSay("Roster publisher: notecard '" + NOTECARD + "' not found.");
        return;
    }
    gUUIDs = [];
    gLineIndex = 0;
    gLineCount = -1;
    gQueryID = llGetNumberOfNotecardLines(NOTECARD);
}

// After completing read, publish to KVP
publishRoster() {
    string csv = llDumpList2String(gUUIDs, ",");
    // publish with create→update fallback
    gKvpOp = OP_CREATE;
    llCreateKeyValue(ROSTER_KEY, csv);
    // (dataserver will handle fallback to update)
}

// ─────────────────────────────────────────────────────────────
default
{
    state_entry() {
        beginRead();
    }

    on_rez(integer p) {
        llResetScript();
    }

    changed(integer c) {
        if (c & CHANGED_INVENTORY) {
            // notecard edited or replaced
            llOwnerSay("Roster publisher: notecard changed, reloading…");
            beginRead();
        }
        if (c & (CHANGED_REGION | CHANGED_REGION_START)) {
            // (Optional) Re‑publish on region move/start
            beginRead();
        }
    }

    touch_start(integer n) {
        if (llDetectedKey(0) != llGetOwner()) return;
        llOwnerSay("Roster publisher: manual refresh requested.");
        beginRead();
    }

    dataserver(key q, string data)
    {
        if (q == gQueryID) {
            // Notecard flow: either count or a line
            if (gLineCount == -1) {
                // First callback after llGetNumberOfNotecardLines
                if (data == EOF) { // unusual, but handle
                    gLineCount = 0;
                    publishRoster();
                    return;
                }
                gLineCount = (integer)data;
                if (gLineCount <= 0) {
                    // Empty notecard → publish empty roster
                    publishRoster();
                    return;
                }
                // Start reading lines
                gQueryID = llGetNotecardLine(NOTECARD, gLineIndex);
                return;
            }

            // Reading lines
            if (data != EOF) {
                parseLine(data);
                gLineIndex++;
                if (gLineIndex < gLineCount) {
                    gQueryID = llGetNotecardLine(NOTECARD, gLineIndex);
                    return;
                }
                // Done
                publishRoster();
                return;
            }
        }
        else {
            // KVP replies use the same dataserver; handle ops by status char
            integer ok = (integer)llGetSubString(data, 0, 0);
            string  tail = llDeleteSubString(data, 0, 1);

            if (gKvpOp == OP_CREATE) {
                if (ok) {
                    llOwnerSay("Roster published: " + (string)llGetListLength(gUUIDs) + " mentors.");
                    gKvpOp = OP_NONE;
                } else {
                    // likely "key exists" → do update instead
                    gKvpOp = OP_UPDATE;
                    llUpdateKeyValue(ROSTER_KEY, llDumpList2String(gUUIDs, ","));
                }
                return;
            }
            if (gKvpOp == OP_UPDATE) {
                if (!ok) {
                    llOwnerSay("Roster update failed: " + llGetExperienceErrorMessage((integer)tail));
                } else {
                    llOwnerSay("Roster updated: " + (string)llGetListLength(gUUIDs) + " mentors.");
                }
                gKvpOp = OP_NONE;
                return;
            }
        }
    }
}
