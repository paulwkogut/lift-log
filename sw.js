const SHELL = "lift-log-shell-v14";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== SHELL).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  const path = url.pathname;
  const isDocument = req.mode === "navigate" || path.endsWith("/index.html") || /\/$/.test(path);
  if (isDocument) {
    event.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(SHELL).then((cache) => cache.put("./index.html", copy)).catch(() => {});
        return res;
      }).catch(() => caches.match("./index.html"))
    );
    return;
  }
  if (!/\.(png|webmanifest)$/.test(path)) return;
  event.respondWith(
    caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      const copy = res.clone();
      caches.open(SHELL).then((cache) => cache.put(req, copy)).catch(() => {});
      return res;
    }))
  );
});

self.addEventListener("push", (event) => {
  const fallback = "Break is over bruh. Get back to work";
  event.waitUntil((async () => {
    let title = "Rest over";
    let body = fallback;
    let target = new URL("./", self.registration.scope).href;
    try {
      const data = event.data ? event.data.json() : null;
      const note = data && data.notification && typeof data.notification === "object" ? data.notification : data;
      if (note) {
        if (note.title) title = String(note.title);
        if (note.body) body = String(note.body);
        const dest = note.navigate || note.url;
        if (dest) target = new URL(String(dest), self.registration.scope).href;
      }
    } catch {}
    try {
      await self.registration.showNotification(title, {
        body,
        icon: new URL("icon-192.png", self.registration.scope).href,
        data: { url: target }
      });
    } catch {
      await self.registration.showNotification("Rest over", {
        body: fallback,
        data: { url: target }
      });
    }
  })());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || new URL("./", self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const client of list) {
      if (client.url.startsWith(self.registration.scope) && "focus" in client) {
        return client.focus();
      }
    }
    if (self.clients.openWindow) return self.clients.openWindow(target);
  }));
});
