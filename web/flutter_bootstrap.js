{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/"
  }
}).catch(function (error) {
  console.error("Flutter failed to start", error);
  var root = document.createElement("div");
  root.style.cssText = "font-family:Arial,sans-serif;padding:24px;color:#111;line-height:1.5";
  root.innerHTML =
    "<h2>Application failed to start</h2>" +
    "<p>Please confirm that <code>.htaccess</code> was uploaded and that <code>.wasm</code> files are served as <code>application/wasm</code>.</p>" +
    "<pre style='white-space:pre-wrap;background:#f3f4f6;padding:12px;border-radius:6px'>" +
    String(error && (error.stack || error.message || error)) +
    "</pre>";
  document.body.appendChild(root);
});
