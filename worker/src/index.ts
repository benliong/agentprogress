export interface Env {
    PROGRESS_KV: KVNamespace;
}

async function sha256Short(input: string): Promise<string> {
    const data = new TextEncoder().encode(input);
    const hash = await crypto.subtle.digest("SHA-256", data);
    return Array.from(new Uint8Array(hash))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("")
        .slice(0, 12);
}

function corsHeaders(): Record<string, string> {
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
    };
}

function json(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json", ...corsHeaders() },
    });
}

function err(message: string, status: number): Response {
    return new Response(message, { status, headers: corsHeaders() });
}

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        // CORS preflight
        if (request.method === "OPTIONS") {
            return new Response(null, { status: 204, headers: corsHeaders() });
        }

        // Auth: derive userId from token (any token gets its own isolated namespace)
        const auth = request.headers.get("Authorization");
        if (!auth?.startsWith("Bearer ")) return err("Unauthorized", 401);
        const token = auth.slice(7).trim();
        if (!token) return err("Unauthorized", 401);
        const userId = await sha256Short(token);

        const url = new URL(request.url);

        // POST /update — write current entry + append to history
        if (request.method === "POST" && url.pathname === "/update") {
            let body: Record<string, unknown>;
            try {
                body = await request.json();
            } catch {
                return err("Bad Request: invalid JSON", 400);
            }

            const required = ["agent", "hostname", "status", "task", "project"];
            for (const field of required) {
                if (!body[field]) return err(`Bad Request: missing field '${field}'`, 400);
            }

            const key = `current:${userId}:${body.hostname}:${body.agent}`;
            await env.PROGRESS_KV.put(key, JSON.stringify(body), {
                expirationTtl: 4 * 3600, // auto-expire stale entries after 4h
            });

            // Append to history (read-modify-write, cap at 500 lines)
            const histKey = `history:${userId}`;
            const existing = (await env.PROGRESS_KV.get(histKey)) ?? "";
            const lines = existing.split("\n").filter(Boolean);
            lines.push(JSON.stringify(body));
            await env.PROGRESS_KV.put(histKey, lines.slice(-500).join("\n") + "\n");

            return new Response(null, { status: 204, headers: corsHeaders() });
        }

        // GET /current — return all active entries for this user
        if (request.method === "GET" && url.pathname === "/current") {
            const list = await env.PROGRESS_KV.list({ prefix: `current:${userId}:` });
            const entries = await Promise.all(
                list.keys.map((k) =>
                    env.PROGRESS_KV.get(k.name).then((v) => (v ? JSON.parse(v) : null))
                )
            );
            return json({ entries: entries.filter(Boolean) });
        }

        // GET /history?last=N — return last N history entries for this user
        if (request.method === "GET" && url.pathname === "/history") {
            const last = Math.min(parseInt(url.searchParams.get("last") ?? "50"), 500);
            const raw = (await env.PROGRESS_KV.get(`history:${userId}`)) ?? "";
            const entries = raw
                .split("\n")
                .filter(Boolean)
                .slice(-last)
                .map((l) => {
                    try { return JSON.parse(l); } catch { return null; }
                })
                .filter(Boolean);
            return json({ entries });
        }

        return err("Not Found", 404);
    },
};
