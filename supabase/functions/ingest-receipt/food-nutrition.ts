export interface LabeledFoodNutrition {
  grams: number;
  calorieKcal: number | null;
  proteinG: number | null;
  carbG: number | null;
  fatG: number | null;
}

/** Reads only explicit package label facts; absence keeps the existing estimate path. */
export function extractLabeledFoodNutrition(text: string): LabeledFoodNutrition | null {
  const source = text.replace(/\s+/gu, "");
  const gramsMatch = source.match(/(?:净含量|含量|规格)[：:]?(\d+(?:\.\d+)?)克?/u);
  const energyMatch = source.match(/(\d+(?:\.\d+)?)(?:千焦|kJ)(?:\/|每|每?)(?:100克|100g)/iu)
    ?? source.match(/每100(?:克|g).*?(\d+(?:\.\d+)?)(?:千焦|kJ)/iu);
  if (!gramsMatch && !energyMatch) return null;
  const grams = gramsMatch ? Number(gramsMatch[1]) : 100;
  if (!Number.isFinite(grams) || grams <= 0) return null;
  const per100Kj = energyMatch ? Number(energyMatch[1]) : null;
  const macro = (label: string): number | null => {
    const match = source.match(new RegExp(`${label}[：:]?(\\d+(?:\\.\\d+)?)`, "iu"));
    return match ? Math.round(Number(match[1]) * grams / 100 * 10) / 10 : null;
  };
  return {
    grams,
    calorieKcal: per100Kj != null && Number.isFinite(per100Kj)
      ? Math.round((per100Kj / 4.184) * grams / 100 * 10) / 10
      : null,
    proteinG: macro("蛋白质"),
    carbG: macro("碳水(?:化合物)?"),
    fatG: macro("脂肪"),
  };
}
