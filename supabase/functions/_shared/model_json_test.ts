import { parseModelJson } from "./model_json.ts";

function eq(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}

Deno.test("invalid escapes from LaTeX no longer break parsing", () => {
  const raw = String.raw`{"text": "الكمية: $\text{ mg / day}$\n\ 100 < $\$ \alpha$"}`;
  eq(parseModelJson(raw), { text: String.raw`الكمية: $\text{ mg / day}$` + "\n" + String.raw`\ 100 < $\$ \alpha$` });
});

Deno.test("silent misparses (frac, theta, nu) are kept as LaTeX", () => {
  const raw = String.raw`{"t": "$\frac{1}{2} \theta \nu \beta$"}`;
  eq(parseModelJson(raw), { t: String.raw`$\frac{1}{2} \theta \nu \beta$` });
});

Deno.test("real newlines, tabs and unicode escapes stay what they are", () => {
  const raw = String.raw`{"t": "a\nnucleus\tb A \"q\" \\frac"}`;
  eq(parseModelJson(raw), { t: "a\nnucleus\tb A \"q\" \\frac" });
});

Deno.test("code fences are stripped", () => {
  eq(parseModelJson('```json\n{"a": 1}\n```'), { a: 1 });
});
