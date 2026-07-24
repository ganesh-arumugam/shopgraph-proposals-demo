// main.rhai — Request + response log redaction for ShopGraph
//
// Why this is correct (client sees everything, logs see redacted):
//   `response.body.data` (the getter) hands us a COPY of the response data.
//   We redact that copy and log it, and we NEVER assign back to
//   `response.body.data`. So the bytes returned to the client are untouched —
//   only the copy we log is masked.
//
//   This is also why telemetry's built-in response logging is left OFF
//   (telemetry.instrumentation.events.router.response: off in router-config.yaml):
//   that path logs the raw, unredacted body. ALL response logging flows through
//   this script instead.
//
// demo's plain queries it fires once per request, which is what we want here.

// Return a redacted DEEP COPY of `value`. The original is never mutated —
// we always build fresh maps/arrays and only ever read from `value`.
// Any key whose name is in `sensitive` has its value replaced with "[REDACTED]",
// matched anywhere in the tree (top level or deeply nested), case-insensitive.
fn redact(value, sensitive) {
    let t = type_of(value);
    if t == "map" {
        let out = #{};
        for key in value.keys() {
            if is_sensitive(key, sensitive) {
                out[key] = "[REDACTED]";
            } else {
                out[key] = redact(value[key], sensitive);
            }
        }
        return out;
    }
    if t == "array" {
        let out = [];
        for item in value {
            out.push(redact(item, sensitive));
        }
        return out;
    }
    // Scalars (string / number / bool / null) pass through unchanged.
    return value;
}

// Case-insensitive membership test for a field name against the sensitive list.
fn is_sensitive(key, sensitive) {
    let lower = key.to_lower();
    for name in sensitive {
        if lower == name.to_lower() {
            return true;
        }
    }
    return false;
}

fn supergraph_service(service) {
    // Sensitive field names for ShopGraph. The list is seeded with the
    // PII / contact fields we expect as the graph grows, so redaction is in
    // place before the sensitive data is. Kept in-script for the demo; a real
    // deployment would likely source this from config or env. Declared once here
    // so BOTH the request and response closures below capture the same list.
    let sensitive = [
        "email",
        "phone",
        "phoneNumber",
        "buyerId",
        "address",
        "street",
        "postalCode",
        "ssn",
        "taxId",
        "cardNumber",
        "creditCard",
        "cvv",
        "token",
        "password",
        // Demo entry to exercise variable-side redaction: the product search
        // Swap for real PII arg names
        // once the schema exposes them.
        "titleStartsWith",
    ];

    // Request side: log which operation the client sent and the fields it asked
    // for (the query string IS the selection set), with variables redacted.
    // PII via variables are covered; inline literals are a residual risk to note.
    //
    // IntrospectionQuery (schema-explorer tooling: Sandbox, GraphiQL, codegen,
    // Apollo Client bootstrapping, etc.) is noisy and not app traffic, so it's
    // skipped here. The op name is stashed on the context so map_response below
    // which has no operation_name of its own — can apply the same skip.
    service.map_request(|request| {
        let op = request.body.operation_name;
        if op == () {
            op = "(anonymous)";
        }
        request.context["op_name"] = op;
        if op == "IntrospectionQuery" {
            return;
        }
        let vars = redact(request.body.variables, sensitive);
        log_info(`[fields] client request op=${op} variables(redacted)=${vars} query=${request.body.query}`);
    });

    // Response side: log the response body with sensitive fields masked.
    service.map_response(|response| {
        let op = response.context["op_name"];
        if op == "IntrospectionQuery" {
            return;
        }
        
        let redacted = redact(response.body.data, sensitive);

        log_info(`[redaction] supergraph response (redacted for logs): ${redacted}`);
    });
}
