// بيرسم صفحات من ملف PDF كصور JPEG — عشان رسمة السلايد نفسها تدخل التلخيص.
// pdf.js بيتحمّل أول مرة بس يتطلب، مش مع فتح التطبيق.
// Renders PDF pages as JPEG images, so the slide's own figure goes into the
// summary. pdf.js loads the first time it is needed, not when the app opens.
(function () {
  var BASE = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/";
  var loading = null;

  function load() {
    if (window.pdfjsLib) return Promise.resolve(window.pdfjsLib);
    if (!loading) {
      loading = new Promise(function (resolve, reject) {
        var s = document.createElement("script");
        s.src = BASE + "pdf.min.js";
        s.onload = function () {
          window.pdfjsLib.GlobalWorkerOptions.workerSrc = BASE + "pdf.worker.min.js";
          resolve(window.pdfjsLib);
        };
        s.onerror = function () {
          loading = null;
          reject(new Error("pdf.js failed to load"));
        };
        document.head.appendChild(s);
      });
    }
    return loading;
  }

  window.renderPdfPages = async function (bytes, pages, width) {
    var lib = await load();
    // نسخة: pdf.js بينقل البايتات للـ worker وبيفضّي الأصل.
    // A copy: pdf.js transfers the bytes to its worker and empties the original.
    var doc = await lib.getDocument({ data: bytes.slice() }).promise;
    var out = [];
    try {
      for (var i = 0; i < pages.length; i++) {
        var n = pages[i];
        if (n < 1 || n > doc.numPages) {
          out.push(null);
          continue;
        }
        var page = await doc.getPage(n);
        var scale = width / page.getViewport({ scale: 1 }).width;
        var viewport = page.getViewport({ scale: scale });
        var canvas = document.createElement("canvas");
        canvas.width = Math.round(viewport.width);
        canvas.height = Math.round(viewport.height);
        var ctx = canvas.getContext("2d");
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        await page.render({ canvasContext: ctx, viewport: viewport }).promise;
        var blob = await new Promise(function (r) {
          canvas.toBlob(r, "image/jpeg", 0.82);
        });
        out.push(blob ? new Uint8Array(await blob.arrayBuffer()) : null);
      }
    } finally {
      doc.destroy();
    }
    return out;
  };
})();
