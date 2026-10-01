// =====================================================================
// قراية JSON من الموديل لما يكون فيه LaTeX
// Reading JSON from the model when it contains LaTeX
// =====================================================================
// الموديل بيكتب المعادلات جوه نصوص JSON، وكتير بيحط شرطة مائلة واحدة بدل
// اتنين: `\text`, `\$`, `\ `, `\alpha`. اللي زي `\$` و`\alpha` بيكسروا
// JSON.parse خالص (502 للمستخدم)، واللي زي `\frac` و`\text` بيتقروا "صح" بس
// غلط: `\f` بتبقى حرف تحكم و`\t` بتبقى tab.
//
// The model writes equations inside JSON strings and often uses one
// backslash instead of two: `\text`, `\$`, `\ `, `\alpha`. Ones like `\$`
// and `\alpha` break JSON.parse outright (a 502 for the user); ones like
// `\frac` and `\text` parse "fine" but wrong: `\f` becomes a control
// character and `\t` a tab.
// =====================================================================

/// أوامر LaTeX اللي بتبدأ بحرف هروب صالح في JSON (b f n r t u) — دي بس اللي
/// بتتقري غلط من غير ما ترمي خطأ. الكلمة لازم تخلص بعد الأمر، عشان سطر جديد
/// بعده كلمة عادية ("\nucleus") ما يتلمسش.
/// LaTeX commands beginning with a valid JSON escape letter (b f n r t u) —
/// only these misparse silently. The command must end at a word boundary,
/// so a newline before an ordinary word ("\nucleus") is left alone.
const LATEX_COMMANDS = new Set([
  "beta", "bar", "binom", "bf", "boldsymbol", "bullet", "big", "bigg", "bot", "backslash",
  "frac", "forall", "flat",
  "nu", "neq", "ne", "nabla", "neg", "nleq", "ngeq", "newline",
  "rho", "rightarrow", "right", "rm", "rangle", "rceil", "rfloor", "rbrace",
  "text", "times", "theta", "tau", "tan", "tanh", "to", "tilde", "textbf", "textit",
  "textrm", "top", "triangle", "tfrac", "therefore",
  "underline", "uparrow", "upsilon", "unit",
]);

const VALID_ESCAPES = new Set(['"', "\\", "/", "b", "f", "n", "r", "t", "u"]);

/// بيضاعف أي شرطة مائلة مش جزء من هروب JSON مقصود.
/// Doubles every backslash that is not part of an intended JSON escape.
export function repairLatexEscapes(text: string): string {
  let out = "";
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch !== "\\") {
      out += ch;
      i++;
      continue;
    }
    const next = text[i + 1] ?? "";

    // هروب صحيح لشرطة (\\): يتنسخ زي ما هو.
    // A correctly escaped backslash (\\) is copied as it is.
    if (next === "\\") {
      out += "\\\\";
      i += 2;
      continue;
    }

    const word = /^[A-Za-z]+/.exec(text.slice(i + 1))?.[0] ?? "";
    const isLatex = LATEX_COMMANDS.has(word);
    const validUnicode = next === "u" && /^u[0-9a-fA-F]{4}/.test(text.slice(i + 1, i + 6));
    const valid = VALID_ESCAPES.has(next) && (next !== "u" || validUnicode);

    if (valid && !isLatex) {
      out += "\\" + next;
      i += 2;
    } else {
      // أمر LaTeX أو هروب مش صالح: الشرطة نفسها تتهرّب.
      // A LaTeX command or an invalid escape: the backslash itself is escaped.
      out += "\\\\";
      i += 1;
    }
  }
  return out;
}

/// بيقرا رد الموديل: كما هو الأول، وبعد التصليح لو فشل أو لو فيه LaTeX.
/// Reads the model's reply: as it is first, then repaired if that fails or
/// if it carries LaTeX.
export function parseModelJson(text: string): unknown {
  const body = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/```$/, "").trim();
  // التصليح دايمًا لو فيه شرطات: الاتنين بيتقروا، بس غير المصلّح ممكن يكون
  // بايظ في صمت (\frac → حرف تحكم).
  // Always repair when backslashes are present: both may parse, but the
  // unrepaired one can be silently wrong (\frac → a control character).
  if (body.includes("\\")) {
    try {
      return JSON.parse(repairLatexEscapes(body));
    } catch {
      // نرجع للأصل تحت.
      // Fall back to the original below.
    }
  }
  return JSON.parse(body);
}
