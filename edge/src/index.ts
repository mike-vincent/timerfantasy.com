import { serveEdge } from './proxy';
import { htmlToMarkdown } from './html-to-md';
import type { AgentSite } from './agent-kit';

const ORIGIN = 'https://timerfantasy.com';
const PAGES = ['/', '/privacy/', '/terms/'];

const text = async (path: string) => {
  const res = await fetch(`${ORIGIN}${path}`);
  if (!res.ok) throw new Error(`Not found: ${path}`);
  return res.text();
};

const site: AgentSite = {
  origin: ORIGIN,
  domain: 'timerfantasy.com',
  name: 'Timer Fantasy',
  slug: 'timerfantasy',
  description: 'Timer Fantasy is a macOS app with beautiful analog timers: set a timer by dragging on a clock face and track countdowns from the menu bar.',
  contact: 'https://mikevincent.dev/',
  skillName: 'timer-fantasy',
  skillDescription: 'Explain what Timer Fantasy does and where to get it.',
  skillBody: 'See https://timerfantasy.com/.well-known/agent-skills/timer-fantasy/SKILL.md',
  queries: [
    'analog timer app for Mac',
    'menu bar countdown timer for macOS',
    'where do I download Timer Fantasy',
  ],
  tools: [
    {
      name: 'get_app_info',
      title: 'App info',
      description: 'Facts about Timer Fantasy: what it does, platform, download link, author, privacy and terms links.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      run: async () => JSON.parse(await text('/app.json')),
    },
    {
      name: 'get_page',
      title: 'Read a page as Markdown',
      description: `A page of timerfantasy.com as Markdown. Paths: ${PAGES.join(', ')}.`,
      inputSchema: { type: 'object', properties: { path: { type: 'string', enum: PAGES } }, required: ['path'], additionalProperties: false },
      run: async (args) => {
        const path = PAGES.includes(String(args.path)) ? String(args.path) : '/';
        // A subrequest to this Worker's own route goes straight to GitHub Pages, so convert here.
        return htmlToMarkdown(await text(path), `${ORIGIN}${path}`);
      },
    },
  ],
  resources: [
    { uri: `${ORIGIN}/llms.txt`, name: 'llms', title: 'Timer Fantasy summary for agents', mimeType: 'text/plain', read: () => text('/llms.txt') },
  ],
};

export default { fetch: (request: Request) => serveEdge(site, request) };
