export interface NormalizedAiDateTime {
  date: string;
  time: string | null;
  iso: string;
}

export function normalizeAiDateTime(value: unknown): NormalizedAiDateTime | null {
  if (typeof value !== "string" || !value.trim()) return null;
  let text = value.trim();
  const compact = text.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日?\s*(\d{1,2})?:?(\d{1,2})?/);
  if (compact) {
    const [, y, m, d, hh, mm] = compact;
    const date = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
    const time = hh && mm ? `${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:00` : null;
    return { date, time, iso: `${date}T${time ?? "00:00:00"}+08:00` };
  }

  text = text.replace("年", "-").replace("月", "-").replace("日", "");
  const normalized = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?(?:([+-]\d{2}:?\d{2}|Z))?$/);
  if (normalized) {
    const [, y, m, d, hh, mm, ss, zone] = normalized;
    const date = `${y}-${m.padStart(2, "0")}-${d.padStart(2, "0")}`;
    const time = hh && mm ? `${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:${(ss ?? "00").padStart(2, "0")}` : null;
    const zoneText = zone ? (zone === "Z" ? "Z" : zone.includes(":") ? zone : `${zone.slice(0, 3)}:${zone.slice(3)}`) : "+08:00";
    return { date, time, iso: `${date}T${time ?? "00:00:00"}${zoneText}` };
  }

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  return {
    date: parsed.toISOString().slice(0, 10),
    time: parsed.toISOString().slice(11, 19),
    iso: parsed.toISOString(),
  };
}

export function normalizeAiDate(value: unknown): string | null {
  return normalizeAiDateTime(value)?.iso ?? null;
}
