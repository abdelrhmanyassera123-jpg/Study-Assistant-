// بيرسم جدول محاضرات النهاردة صورة، عشان الإشعار المفتوح يبان جدول مرتّب.
// Draws today's lectures as a picture, so the expanded notification shows a
// tidy table.
//
// إشعارات الويب مفيهاش تخطيط مخصص زي تطبيقات أندرويد — النص سطر ورا سطر
// بس. الصورة الكبيرة (image) هي الحاجة الوحيدة اللي ينفع ترسم فيها أي شكل،
// وبتظهر لما الإشعار يتسحب لتحت. بيتستخدم من pwa-sw.js، ومن صفحة تجربة.
// Web notifications have no custom layout like Android apps: text, line
// after line, only. The large image is the one place any shape can be
// drawn, and it shows when the notification is pulled down. Used from
// pwa-sw.js, and from a preview page.

/* exported drawDigestTable */
async function drawDigestTable(rows) {
  if (!Array.isArray(rows) || rows.length === 0 || typeof OffscreenCanvas === "undefined") {
    return null;
  }

  // أندرويد بيصغّر الصورة لعرض الإشعار؛ أكتر من 6 صفوف بيبقوا صغيرين أوي.
  // اللي بيتشال هو أقدم اللي خلص.
  // Android scales the picture to the notification's width; past 6 rows they
  // get too small. What goes is the earliest of those already over.
  const MAX = 6;
  let shown = rows;
  if (rows.length > MAX) {
    const firstLive = Math.max(0, rows.findIndex((r) => r.state !== "done"));
    const from = Math.min(Math.max(0, firstLive - 1), rows.length - MAX);
    shown = rows.slice(from, from + MAX);
  }

  const W = 720;
  const pad = 18;
  const rowH = 78;
  const gap = 8;
  const H = pad * 2 + shown.length * rowH + (shown.length - 1) * gap;
  const canvas = new OffscreenCanvas(W, H);
  const ctx = canvas.getContext("2d");
  const font = (weight, size) => `${weight} ${size}px system-ui, "Segoe UI", Roboto, sans-serif`;

  const colors = {
    page: "#18201C",
    row: "#222C27",
    now: "#E3B341",
    nowText: "#1A1A1A",
    text: "#F2F5F3",
    muted: "#9DB0A6",
    next: "#E3B341",
  };

  roundRect(ctx, 0, 0, W, H, 28);
  ctx.fillStyle = colors.page;
  ctx.fill();
  ctx.direction = "rtl";
  ctx.textBaseline = "alphabetic";

  shown.forEach((row, i) => {
    const y = pad + i * (rowH + gap);
    const x0 = pad;
    const x1 = W - pad;
    const now = row.state === "now";
    const done = row.state === "done";

    roundRect(ctx, x0, y, x1 - x0, rowH, 18);
    ctx.fillStyle = now ? colors.now : colors.row;
    ctx.fill();
    if (row.state === "next") {
      ctx.lineWidth = 3;
      ctx.strokeStyle = colors.next;
      ctx.stroke();
    }

    ctx.globalAlpha = done ? 0.38 : 1;
    const ink = now ? colors.nowText : colors.text;
    const soft = now ? "rgba(26,26,26,0.72)" : colors.muted;

    // الوقت على اليمين: البداية كبيرة والنهاية تحتها.
    // The time on the right: the start large, the end beneath it.
    const timeRight = x1 - 18;
    ctx.textAlign = "right";
    ctx.fillStyle = ink;
    ctx.font = font(700, 26);
    ctx.fillText(row.start || "", timeRight, y + 36);
    ctx.fillStyle = soft;
    ctx.font = font(500, 18);
    ctx.fillText(row.end ? `لحد ${row.end}` : "", timeRight, y + 62);

    // القاعة على الشمال.
    // The room on the left.
    const roomText = row.room || "";
    ctx.font = font(700, 22);
    const roomW = roomText ? ctx.measureText(roomText).width : 0;
    if (roomText) {
      ctx.textAlign = "left";
      ctx.fillStyle = ink;
      ctx.fillText(roomText, x0 + 18, y + 48);
    }

    // اسم المحاضرة في النص، وتحته حالتها.
    // The lecture's name in the middle, its state beneath it.
    const titleRight = timeRight - 150;
    const titleMax = titleRight - (x0 + 18 + roomW + (roomW ? 22 : 0));
    // الاسم الإنجليزي بيتكتب شمال-يمين عشان "…" تيجي في آخره مش أوله.
    // An English name is laid out left-to-right so the "…" lands at its end,
    // not its start.
    ctx.textAlign = "right";
    ctx.fillStyle = ink;
    ctx.font = font(700, 23);
    ctx.direction = /^[^؀-ۿ]*[A-Za-z]/.test(row.title || "") ? "ltr" : "rtl";
    ctx.fillText(ellipsize(ctx, row.title || "", titleMax), titleRight, y + 36);
    ctx.direction = "rtl";

    const label = { now: "دلوقتي", next: "الجاية", done: "خلصت", later: "" }[row.state] || "";
    if (label) {
      ctx.fillStyle = now ? colors.nowText : row.state === "next" ? colors.next : soft;
      ctx.font = font(600, 17);
      ctx.fillText(label, titleRight, y + 62);
    }
    ctx.globalAlpha = 1;
  });

  const blob = await canvas.convertToBlob({ type: "image/png" });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return `data:image/png;base64,${btoa(binary)}`;
}

function ellipsize(ctx, text, maxWidth) {
  if (maxWidth <= 0) return "";
  if (ctx.measureText(text).width <= maxWidth) return text;
  let lo = 0;
  let hi = text.length;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (ctx.measureText(`${text.slice(0, mid)}…`).width <= maxWidth) lo = mid;
    else hi = mid - 1;
  }
  return `${text.slice(0, lo).trimEnd()}…`;
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
