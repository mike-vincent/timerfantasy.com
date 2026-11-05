// Read-only MCP server (Streamable HTTP, stateless, JSON responses) and
// anonymous OAuth. Every tool and resource is public. Tokens are optional:
// any agent can register and get one instantly, and a token grants nothing
// beyond what an anonymous request already gets.
import { json, type AgentSite } from './agent-kit';

const SUPPORTED = ['2025-06-18', '2025-03-26', '2024-11-05'];
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept, Authorization, Mcp-Session-Id, Mcp-Protocol-Version',
  'Access-Control-Expose-Headers': 'Mcp-Session-Id',
};
const SCOPES = ['read'];

type Msg = { jsonrpc?: string; id?: string | number | null; method?: string; params?: any };
const ok = (id: Msg['id'], result: unknown) => ({ jsonrpc: '2.0', id, result });
const fail = (id: Msg['id'], code: number, message: string) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });

async function handleMessage(site: AgentSite, m: Msg) {
  if (!m || m.jsonrpc !== '2.0' || typeof m.method !== 'string') return fail(m?.id, -32600, 'Invalid Request');
  switch (m.method) {
    case 'initialize': {
      const asked = m.params?.protocolVersion;
      return ok(m.id, {
        protocolVersion: SUPPORTED.includes(asked) ? asked : SUPPORTED[0],
        capabilities: { tools: { listChanged: false }, resources: { listChanged: false, subscribe: false } },
        serverInfo: { name: site.slug, title: site.name, version: '1.0.0' },
        instructions: `${site.description} All tools are read-only.`,
      });
    }
    case 'ping':
      return ok(m.id, {});
    case 'tools/list':
      return ok(m.id, {
        tools: site.tools.map(({ name, title, description, inputSchema }) => ({
          name, title, description, inputSchema, annotations: { readOnlyHint: true, openWorldHint: false },
        })),
      });
    case 'tools/call': {
      const tool = site.tools.find((t) => t.name === m.params?.name);
      if (!tool) return fail(m.id, -32602, `Unknown tool: ${m.params?.name}`);
      try {
        const data = await tool.run(m.params?.arguments ?? {});
        const structured = data && typeof data === 'object' && !Array.isArray(data) ? { structuredContent: data } : {};
        return ok(m.id, { content: [{ type: 'text', text: typeof data === 'string' ? data : JSON.stringify(data, null, 2) }], ...structured, isError: false });
      } catch (e) {
        return ok(m.id, { content: [{ type: 'text', text: String((e as Error)?.message || e) }], isError: true });
      }
    }
    case 'resources/list':
      return ok(m.id, { resources: site.resources.map(({ uri, name, title, mimeType }) => ({ uri, name, title, mimeType })) });
    case 'resources/read': {
      const r = site.resources.find((x) => x.uri === m.params?.uri);
      if (!r) return fail(m.id, -32602, 'Unknown resource');
      return ok(m.id, { contents: [{ uri: r.uri, mimeType: r.mimeType, text: await r.read() }] });
    }
    default:
      return m.id === undefined ? null : fail(m.id, -32601, `Method not found: ${m.method}`);
  }
}

export async function handleMcp(site: AgentSite, request: Request): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (request.method !== 'POST') {
    return new Response(`MCP endpoint (Streamable HTTP). POST JSON-RPC here. Card: ${site.origin}/.well-known/mcp/server-card.json\n`, {
      status: 405,
      headers: { ...CORS, Allow: 'POST, OPTIONS', 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json(fail(null, -32700, 'Parse error'), { status: 400, headers: CORS });
  }
  const msgs = (Array.isArray(body) ? body : [body]) as Msg[];
  const replies = (await Promise.all(msgs.map((m) => handleMessage(site, m)))).filter((r) => r !== null);
  if (replies.length === 0) return new Response(null, { status: 202, headers: CORS });
  return Response.json(Array.isArray(body) ? replies : replies[0], { headers: CORS });
}

export function oauthServerMetadata(site: AgentSite) {
  const o = site.origin;
  return {
    issuer: o,
    authorization_endpoint: `${o}/oauth/authorize`,
    token_endpoint: `${o}/oauth/token`,
    registration_endpoint: `${o}/oauth/register`,
    revocation_endpoint: `${o}/oauth/revoke`,
    jwks_uri: `${o}/.well-known/jwks.json`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'client_credentials'],
    token_endpoint_auth_methods_supported: ['none'],
    code_challenge_methods_supported: ['S256'],
    scopes_supported: SCOPES,
    subject_types_supported: ['public'],
    id_token_signing_alg_values_supported: ['none'],
    service_documentation: `${o}/auth.md`,
    agent_auth: {
      skill: `${o}/auth.md`,
      register_uri: `${o}/oauth/register`,
      revocation_uri: `${o}/oauth/revoke`,
      claim_uri: `${o}/oauth/claim`,
      claim_endpoint: `${o}/oauth/claim`,
      identity_types_supported: ['anonymous'],
      anonymous: { credential_types_supported: ['oauth_client', 'access_token'], claim_uri: `${o}/oauth/claim` },
    },
  };
}

export function protectedResourceMetadata(site: AgentSite) {
  return {
    resource: site.origin,
    resource_name: `${site.name} MCP server`,
    authorization_servers: [site.origin],
    scopes_supported: SCOPES,
    bearer_methods_supported: ['header'],
    resource_documentation: `${site.origin}/auth.md`,
  };
}

export function authMd(site: AgentSite): string {
  const o = site.origin;
  return `# ${site.name} auth.md

Audience: AI agents and automated clients that read ${site.name} (${o}).

Everything on this site is public and read-only. **No credentials are needed.** Call the MCP server at \`POST ${o}/mcp\` directly.

If your client insists on OAuth, registration is anonymous and instant:

1. Register: \`POST ${o}/oauth/register\` with a JSON body such as \`{"client_name": "my-agent"}\`. The reply holds a \`client_id\`. No secret is issued (\`token_endpoint_auth_method: none\`).
2. Get a token: \`POST ${o}/oauth/token\` with \`grant_type=client_credentials\` and your \`client_id\`, or use the authorization code flow at \`${o}/oauth/authorize\` with PKCE.
3. Send it as \`Authorization: Bearer <token>\`. The token grants scope \`read\`, the same access as an anonymous request.

## Supported registration and identity flows

- Identity type: \`anonymous\`. No sign-in, no email, no account.
- Credential types: \`oauth_client\` (from registration) and \`access_token\` (from the token endpoint).
- Scope: \`read\`.

## Endpoints

- Registration endpoint: \`POST ${o}/oauth/register\`
- Token endpoint: \`POST ${o}/oauth/token\`
- Authorization endpoint: \`GET ${o}/oauth/authorize\`
- Revocation endpoint: \`POST ${o}/oauth/revoke\`
- Claim URI: \`${o}/oauth/claim\`
- MCP server: \`POST ${o}/mcp\`

## Discovery documents


- Protected resource metadata: ${o}/.well-known/oauth-protected-resource
- Authorization server metadata: ${o}/.well-known/oauth-authorization-server
- MCP server card: ${o}/.well-known/mcp/server-card.json
- API catalog: ${o}/.well-known/api-catalog

Revoke a token with \`POST ${o}/oauth/revoke\`. Anonymous clients have no account, so \`${o}/oauth/claim\` has nothing to claim.

Contact: ${site.contact}
`;
}

async function readParams(request: Request): Promise<Record<string, string>> {
  const type = request.headers.get('content-type') || '';
  try {
    if (type.includes('application/json')) return (await request.json()) as Record<string, string>;
    return Object.fromEntries(new URLSearchParams(await request.text()));
  } catch {
    return {};
  }
}

const isLoopback = (u: URL) => u.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(u.hostname);
const oauthError = (error: string, status = 400) => json({ error }, status);

export async function handleOAuth(site: AgentSite, request: Request): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '');
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (path === '/oauth/register' && request.method === 'POST') {
    const body = await readParams(request);
    return json({
      client_id: `anon-${crypto.randomUUID()}`,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      client_name: typeof body.client_name === 'string' ? body.client_name.slice(0, 100) : undefined,
      redirect_uris: Array.isArray(body.redirect_uris) ? body.redirect_uris : [],
      grant_types: ['authorization_code', 'client_credentials'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none',
      scope: SCOPES.join(' '),
    }, 201);
  }
  if (path === '/oauth/token' && request.method === 'POST') {
    const p = await readParams(request);
    if (p.grant_type !== 'client_credentials' && p.grant_type !== 'authorization_code') return oauthError('unsupported_grant_type');
    return json({ access_token: `anon-${crypto.randomUUID()}`, token_type: 'Bearer', expires_in: 86400, scope: SCOPES.join(' ') });
  }
  if (path === '/oauth/authorize' && request.method === 'GET') {
    const raw = url.searchParams.get('redirect_uri');
    if (url.searchParams.get('response_type') !== 'code' || !raw) return oauthError('invalid_request');
    let target: URL;
    try {
      target = new URL(raw);
    } catch {
      return oauthError('invalid_request');
    }
    if (target.protocol !== 'https:' && !isLoopback(target)) return oauthError('invalid_request');
    target.searchParams.set('code', crypto.randomUUID());
    const state = url.searchParams.get('state');
    if (state) target.searchParams.set('state', state);
    // Loopback clients continue at once. Others get a link to follow, so this
    // endpoint never redirects a browser to an arbitrary site on its own.
    if (isLoopback(target)) return Response.redirect(target.toString(), 302);
    const safe = target.toString().replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
    return new Response(
      `<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex"><title>${site.name} access</title><p>${site.name} is public and read-only, so no sign-in is needed.</p><p><a href="${safe}">Continue to ${target.host.replace(/</g, '&lt;')}</a></p>`,
      { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' } },
    );
  }
  if (path === '/oauth/revoke' && request.method === 'POST') return new Response(null, { status: 200, headers: CORS });
  if (path === '/oauth/claim') return json({ status: 'nothing_to_claim', detail: 'Anonymous clients have no account to claim. Access is public and read-only.' });
  return oauthError('not_found', 404);
}
