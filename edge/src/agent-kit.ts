// Agent discovery for this site, per https://isitagentready.com checks:
// API catalog (RFC 9727), MCP server card, agent skills index, ARD catalog,
// Personal Agent Protocol, OpenAPI, and Link headers. The MCP server and the
// anonymous OAuth endpoints live in agent-mcp.ts.
// Everything here is public and read-only.
import { handleMcp, handleOAuth, oauthServerMetadata, protectedResourceMetadata, authMd } from './agent-mcp';

export interface AgentTool {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  run: (args: Record<string, unknown>) => Promise<unknown>;
}

export interface AgentResource {
  uri: string;
  name: string;
  title: string;
  mimeType: string;
  read: () => Promise<string>;
}

export interface AgentSite {
  origin: string; // https://www.example.org, no trailing slash
  domain: string; // example.org, no www
  name: string;
  slug: string; // short machine name for the MCP server
  description: string;
  contact: string;
  skillName: string;
  skillDescription: string;
  skillBody: string; // Markdown after the front matter
  queries: string[]; // 2 to 5 sample questions agents might ask
  tools: AgentTool[];
  resources: AgentResource[];
}

const CORS = { 'Access-Control-Allow-Origin': '*' };

export function json(data: unknown, status = 200, type = 'application/json; charset=utf-8'): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': type, 'Cache-Control': 'public, max-age=300', ...CORS },
  });
}

export function text(body: string, type: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { 'Content-Type': type, 'Cache-Control': 'public, max-age=300', ...CORS },
  });
}

export function linkHeader(): string {
  return [
    '</.well-known/api-catalog>; rel="api-catalog"; type="application/linkset+json"',
    '</.well-known/mcp/server-card.json>; rel="service-desc"; type="application/json"',
    '</openapi.json>; rel="service-desc"; type="application/vnd.oai.openapi+json"',
    '</llms.txt>; rel="describedby"; type="text/plain"',
    '</auth.md>; rel="service-doc"; type="text/markdown"',
    '</.well-known/agent-skills/index.json>; rel="describedby"; type="application/json"',
    '</.well-known/ai-catalog.json>; rel="ai-catalog"; type="application/json"',
  ].join(', ');
}

function parseAccept(accept: string): Map<string, number> {
  const out = new Map<string, number>();
  for (const part of accept.split(',')) {
    const [type, ...params] = part.trim().toLowerCase().split(';').map((x) => x.trim());
    if (!type) continue;
    let q = 1;
    for (const p of params) if (p.startsWith('q=')) q = Number(p.slice(2));
    out.set(type, Number.isFinite(q) ? q : 0);
  }
  return out;
}

/** True when the client asks for Markdown at least as much as HTML. Browsers never do. */
export function wantsMarkdown(accept: string | null): boolean {
  if (!accept || !accept.toLowerCase().includes('text/markdown')) return false;
  const ranges = parseAccept(accept);
  const pick = (t: string) => ranges.get(t) ?? ranges.get(`${t.split('/')[0]}/*`) ?? ranges.get('*/*') ?? 0;
  const md = pick('text/markdown');
  return md > 0 && md >= pick('text/html');
}

export function markdown(body: string, method: string): Response {
  return new Response(method === 'HEAD' ? null : body, {
    status: 200,
    headers: {
      'Content-Type': 'text/markdown; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
      Vary: 'Accept',
      'x-markdown-tokens': String(Math.ceil(body.length / 4)),
      Link: linkHeader(),
      ...CORS,
    },
  });
}

export function skillMd(site: AgentSite): string {
  return `---\nname: ${site.skillName}\ndescription: ${site.skillDescription}\n---\n\n${site.skillBody.trim()}\n`;
}

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function serverCard(site: AgentSite) {
  return {
    $schema: 'https://static.modelcontextprotocol.io/schemas/mcp-server-card/v1.json',
    version: '1.0',
    protocolVersion: '2025-06-18',
    serverInfo: { name: site.slug, title: site.name, version: '1.0.0' },
    description: `${site.description} Read-only. No authentication required.`,
    documentationUrl: `${site.origin}/llms.txt`,
    transport: { type: 'streamable-http', endpoint: `${site.origin}/mcp` },
    capabilities: { tools: { listChanged: false }, resources: { listChanged: false, subscribe: false } },
    authentication: { required: false },
    tools: site.tools.map(({ name, title, description }) => ({ name, title, description })),
  };
}

function apiCatalog(site: AgentSite) {
  const o = site.origin;
  return {
    linkset: [
      {
        anchor: `${o}/mcp`,
        'service-desc': [
          { href: `${o}/.well-known/mcp/server-card.json`, type: 'application/json' },
          { href: `${o}/openapi.json`, type: 'application/vnd.oai.openapi+json' },
        ],
        'service-doc': [
          { href: `${o}/llms.txt`, type: 'text/plain' },
          { href: `${o}/auth.md`, type: 'text/markdown' },
        ],
        status: [{ href: `${o}/health`, type: 'application/json' }],
      },
    ],
  };
}

function openApi(site: AgentSite) {
  return {
    openapi: '3.1.0',
    info: { title: `${site.name} agent API`, version: '1.0.0', description: `${site.description} Public and read-only.` },
    servers: [{ url: site.origin }],
    paths: {
      '/mcp': {
        post: {
          operationId: 'mcp',
          summary: 'Model Context Protocol endpoint (Streamable HTTP, JSON-RPC 2.0)',
          description: `Methods: initialize, tools/list, tools/call (${site.tools.map((t) => t.name).join(', ')}), resources/list, resources/read.`,
          requestBody: { required: true, content: { 'application/json': { schema: { type: 'object', required: ['jsonrpc', 'method'] } } } },
          responses: { '200': { description: 'JSON-RPC response' }, '202': { description: 'Notification accepted' } },
        },
      },
      '/health': {
        get: { operationId: 'health', summary: 'Service status', responses: { '200': { description: 'OK' } } },
      },
    },
  };
}

function aiCatalog(site: AgentSite) {
  return {
    specVersion: '1.0',
    host: { displayName: site.name, identifier: `did:web:${site.domain}` },
    entries: [
      {
        identifier: `urn:air:${site.domain}:server:${site.slug}`,
        displayName: `${site.name} (MCP)`,
        type: 'application/mcp-server-card+json',
        url: `${site.origin}/.well-known/mcp/server-card.json`,
        representativeQueries: site.queries,
      },
      {
        identifier: `urn:air:${site.domain}:skill:${site.skillName}`,
        displayName: `${site.name} agent skill`,
        type: 'text/markdown',
        url: `${site.origin}/.well-known/agent-skills/${site.skillName}/SKILL.md`,
        representativeQueries: site.queries.slice(0, 3),
      },
    ],
  };
}

/** Serves the agent discovery documents. Returns null for every other path. */
export async function agentRoute(site: AgentSite, request: Request): Promise<Response | null> {
  const path = new URL(request.url).pathname.replace(/\/+$/, '') || '/';
  if (path === '/mcp') return handleMcp(site, request);
  if (path.startsWith('/oauth/')) return handleOAuth(site, request);
  if (request.method !== 'GET' && request.method !== 'HEAD') return null;
  switch (path) {
    case '/.well-known/api-catalog':
      return json(apiCatalog(site), 200, 'application/linkset+json; charset=utf-8');
    case '/.well-known/mcp/server-card.json':
    case '/.well-known/mcp.json':
      return json(serverCard(site));
    case '/.well-known/ai-catalog.json':
      return json(aiCatalog(site));
    case '/.well-known/agent-skills/index.json': {
      const digest = `sha256:${await sha256(skillMd(site))}`;
      return json({
        $schema: 'https://schemas.agentskills.io/discovery/0.2.0/schema.json',
        skills: [{ name: site.skillName, type: 'skill-md', description: site.skillDescription, url: `${site.origin}/.well-known/agent-skills/${site.skillName}/SKILL.md`, digest }],
      });
    }
    case `/.well-known/agent-skills/${site.skillName}/SKILL.md`:
      return text(skillMd(site), 'text/markdown; charset=utf-8');
    case '/.well-known/oauth-authorization-server':
    case '/.well-known/openid-configuration':
      return json(oauthServerMetadata(site));
    case '/.well-known/oauth-protected-resource':
    case '/.well-known/oauth-protected-resource/mcp':
      return json(protectedResourceMetadata(site));
    case '/.well-known/jwks.json':
      return json({ keys: [] });
    case '/.well-known/poppy.json':
      return json({ protocol_version: '0.1', organization: { name: site.name, domain: site.domain }, web: {} });
    case '/auth.md':
      return text(authMd(site), 'text/markdown; charset=utf-8');
    case '/openapi.json':
      return json(openApi(site));
    case '/health':
      return json({ status: 'ok', service: site.slug });
    default:
      return null;
  }
}
