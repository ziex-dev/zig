if (self.document) {
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('pwa.js')
    });
  }
} else {
  const cachename = 'pwa';
  const precached = [
    '.',
    'main.js',
    'main.wasm',
    'sources.tar',
  ];
  async function cachePrefetch(name, paths) {
    const cache = await self.caches.open(name);
    await cache.addAll(paths);
  }
  async function cachedFetch(name, request) {
    const cache = await self.caches.open(name);
    const matched = await cache.match(request);
    if (matched) {
      return matched;
    } else {
      const fetched = await fetch(request);
      cache.put(request, fetched.clone());
      return fetched;
    }
  }
  self.addEventListener("install", (event) => {
    event.waitUntil(cachePrefetch(cachename, precached));
  });
  self.addEventListener('fetch', (event) => {
    event.respondWith(cachedFetch(cachename, event.request));
  });
}
