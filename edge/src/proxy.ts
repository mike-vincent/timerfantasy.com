// Worker on a route in front of GitHub Pages. GitHub keeps hosting the site;
// this adds what static hosting cannot: Link headers, Markdown versions of
// pages for agents (Accept: text/markdown), and a read-only MCP server with
// its discovery documents. Static files from the site pass through unchanged,
// except the API and AI catalogs, which gain an entry for the MCP server.
import { agentRoute, linkHeader, markdown, serverCard, wantsMarkdown, type AgentSite } from './agent-kit';
import { htmlToMarkdown } from './html-to-md';

// Paths answered here. Everything else goes to GitHub Pages.
const DYNAMIC = new Set([
  '/mcp',
  '/health',
  '/auth.md',
  '/.well-known/mcp/server-card.json',
  '/.well-known/mcp.json',
  '/.well-known/oauth-authorization-server',
  '/.well-known/openid-configuration',
  '/.well-known/oauth-protected-resource',
  '/.well-known/oauth-protected-resource/mcp',
  '/.well-known/jwks.json',
]);

const CATALOG_HEADERS = { 'Cache-Control': 'public, max-age=300', 'Access-Control-Allow-Origin': '*' };

async function withMcpEntry(site: AgentSite, res: Response, path: string): Promise<Response> {
  const doc = (await res.json()) as Record<string, any>;
  const card = `${site.origin}/.well-known/mcp/server-card.json`;
  if (path === '/.well-known/api-catalog') {
    doc.linkset = [
      ...(doc.linkset ?? []),
      {
        anchor: `${site.origin}/mcp`,
        'service-desc': [{ href: card, type: 'application/json' }],
        'service-doc': [{ href: `${site.origin}/auth.md`, type: 'text/markdown' }, { href: `${site.origin}/llms.txt`, type: 'text/plain' }],
        status: [{ href: `${site.origin}/health`, type: 'application/json' }],
      },
    ];
    return new Response(JSON.stringify(doc, null, 2), { headers: { 'Content-Type': 'application/linkset+json; charset=utf-8', ...CATALOG_HEADERS } });
  }
  doc.entries = [
    ...(doc.entries ?? []),
    {
      identifier: `urn:air:${site.domain}:server:${site.slug}`,
      displayName: `${site.name} (MCP)`,
      type: 'application/mcp-server-card+json',
      url: card,
      representativeQueries: site.queries,
    },
  ];
  return new Response(JSON.stringify(doc, null, 2), { headers: { 'Content-Type': 'application/json; charset=utf-8', ...CATALOG_HEADERS } });
}

export async function serveEdge(site: AgentSite, request: Request): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '') || '/';
  if (DYNAMIC.has(path) || path.startsWith('/oauth/')) {
    const hit = await agentRoute(site, request);
    if (hit) return hit;
  }
  const read = request.method === 'GET' || request.method === 'HEAD';
  if (read && (path === '/.well-known/api-catalog' || path === '/.well-known/ai-catalog.json')) {
    const res = await fetch(new Request(url.toString(), { headers: { Accept: 'application/json' } }));
    if (res.ok) return withMcpEntry(site, res, path);
    return res;
  }
  if (read && wantsMarkdown(request.headers.get('accept'))) {
    const res = await fetch(new Request(url.toString(), { headers: { Accept: 'text/html' } }));
    if (res.ok && (res.headers.get('content-type') || '').includes('text/html')) {
      return markdown(htmlToMarkdown(await res.text(), url.toString()), request.method);
    }
  }
  const res = await fetch(request);
  if (!(res.headers.get('content-type') || '').includes('text/html')) return res;
  const out = new Response(res.body, res);
  out.headers.append('Link', linkHeader());
  out.headers.append('Vary', 'Accept');
  // no-transform keeps Cloudflare from injecting scripts (Bot Fight Mode,
  // Rocket Loader, email obfuscation) that would cost PageSpeed points.
  const cc = out.headers.get('Cache-Control');
  if (!cc?.includes('no-transform')) out.headers.set('Cache-Control', cc ? `${cc}, no-transform` : 'no-transform');
  return out;
}

export { serverCard };
