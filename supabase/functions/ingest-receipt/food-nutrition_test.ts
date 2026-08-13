import { extractLabeledFoodNutrition } from "./food-nutrition.ts";

const assert = (condition: boolean, message: string) => {
  if (!condition) throw new Error(message);
};

Deno.test("FOOD-001 uses explicit net weight and kJ label for a full package", () => {
  const result = extractLabeledFoodNutrition("净含量100g，每100g能量1564kJ，蛋白质8.4g，碳水51.4g，脂肪14.8g");
  assert(result?.grams === 100, "the package weight must remain 100g");
  assert(Math.abs((result?.calorieKcal ?? 0) - 373.8) < 0.1, "1564kJ/100g must convert to about 374kcal");
  assert(result?.proteinG === 8.4 && result.carbG === 51.4 && result.fatG === 14.8, "macros must preserve explicit label values");
});

Deno.test("FOOD-001 keeps unlabeled small packs on the existing estimate path", () => {
  assert(extractLabeledFoodNutrition("独立包装小零食") === null, "heuristics remain available without label facts");
});

Deno.test("FOOD-001 scales per-100g label values to the explicit package weight", () => {
  const result = extractLabeledFoodNutrition("净含量50g，每100g能量1564kJ，蛋白质8.4g");
  assert(Math.abs((result?.calorieKcal ?? 0) - 186.9) < 0.1, "a 50g pack must use half of the per-100g energy");
  assert(result?.proteinG === 4.2, "per-100g macros must scale to the package weight");
});
