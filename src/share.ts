// Delen naar K: link en titel uit gedeelde tekst halen.

/** Eerste link uit een stuk tekst (zoals Chrome die deelt: "Titel https://..."). */
export function splitShared(text: string, subject = ''): { url?: string; title?: string; text?: string } {
  const m = text.match(/https?:\/\/\S+/);
  if (!m) return { text: text.trim(), title: subject.trim() || undefined };
  const rest = text.replace(m[0], '').trim();
  return { url: m[0].replace(/[).,]+$/, ''), title: (subject.trim() || rest || undefined) };
}

