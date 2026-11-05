// Turns a rendered page into plain Markdown for agents that send
// Accept: text/markdown. Keeps headings, paragraphs, lists, links and emphasis;
// drops scripts, styles, navigation and the footer.
const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', middot: '·', mdash: '—', ndash: '–', copy: '©', hellip: '…', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“' };

function decode(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) => {
    if (e[0] === '#') {
      const n = e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(n) ? String.fromCodePoint(n) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

const flat = (s: string) => s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

export function htmlToMarkdown(html: string, pageUrl: string): string {
  const title = flat(html.match(/<title>([\s\S]*?)<\/title>/i)?.[1] ?? '');
  const description = html.match(/<meta name="description" content="([^"]*)"/i)?.[1] ?? '';
  const abs = (href: string) => {
    try {
      return new URL(decode(href), pageUrl).toString();
    } catch {
      return href;
    }
  };
  let s = (html.match(/<body[^>]*>([\s\S]*)<\/body>/i)?.[1] ?? html)
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<(script|style|svg|noscript|template|nav|footer|form|button|dialog)\b[\s\S]*?<\/\1>/gi, '')
    .replace(/<a\b[^>]*?href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, (_, href: string, inner: string) => {
      const label = flat(inner);
      return label ? `[${label}](${abs(href)}) ` : '';
    })
    .replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_, n: string, inner: string) => `\n\n${'#'.repeat(Number(n))} ${flat(inner)}\n\n`)
    .replace(/<(strong|b)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_, _t, inner: string) => `**${flat(inner)}**`)
    .replace(/<(em|i)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_, _t, inner: string) => `*${flat(inner)}*`)
    .replace(/<li\b[^>]*>/gi, '\n- ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|section|article|header|main|ul|ol|li|table|tr|blockquote|figure|figcaption|dl|dt|dd|address)>/gi, '\n\n')
    .replace(/<(td|th)\b[^>]*>/gi, ' | ')
    .replace(/<[^>]+>/g, ' ');
  s = decode(s)
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/^(- )\n+/gm, '$1')
    .trim();
  const head = /^# /m.test(s) ? '' : `# ${title}\n\n${description ? `> ${decode(description)}\n\n` : ''}`;
  return `${head}${s}\n\nSource: ${pageUrl}\n`;
}
