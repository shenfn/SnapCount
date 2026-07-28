export function uniqueNotificationLines(
  lines: Array<string | null | undefined>,
): string[] {
  const seen = new Set<string>();
  const unique: string[] = [];

  for (const value of lines) {
    const line = value?.trim();
    if (!line) continue;

    const key = line.replace(/\s+/g, " ");
    if (seen.has(key)) continue;

    seen.add(key);
    unique.push(line);
  }

  return unique;
}

export function mergePlannerNotification(
  plannerMessage: string | null | undefined,
  fallbackNotification: string,
  companionMessage?: string | null,
): string {
  return uniqueNotificationLines([
    ...String(companionMessage ?? "").split("\n"),
    plannerMessage,
    ...fallbackNotification.split("\n"),
  ]).join("\n");
}
