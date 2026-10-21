package org.flexscript.collie;

import org.json.JSONObject;

/** Session-owned grants. A stored partial policy grants only explicit true values. */
final class AgentPermissions {
    static final String[] KEYS = {
        "internet", "files_read", "files_write", "db_read", "db_write", "history"};
    static JSONObject load(JSONObject saved) {
        JSONObject result = new JSONObject();
        try {
            for (String key : KEYS)
                result.put(key, saved == null || Boolean.TRUE.equals(saved.opt(key)));
        } catch (Exception impossible) { throw new IllegalStateException(impossible); }
        return result;
    }
}
