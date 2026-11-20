import assert from "node:assert/strict";

const origin = new URL(process.argv[2] ?? "http://localhost:5000");
const request = (path, options) => fetch(new URL(path, origin), {
  redirect: "manual", signal: AbortSignal.timeout(10_000), ...options,
});

const health = await request("/api/health");
assert.equal(health.status, 200);
assert.equal((await health.json()).status, "ok");
for (const path of ["/api/auth/user", "/api/lectures"]) {
  const response = await request(path);
  assert.equal(response.status, 401, path);
  assert.equal(response.headers.get("cache-control"), "no-store", path);
}
const unstartedCallback = await request("/api/callback");
assert.equal(unstartedCallback.status, 302);
assert.equal(unstartedCallback.headers.get("location"), "/?auth=retry");
const crossSiteMutation = await request("/api/logout", {
  method: "POST", headers: { Origin: "https://example.org" },
});
assert.equal(crossSiteMutation.status, 403);
console.log("Health, protected routes, OAuth callback without a session, and cross-origin logout checks passed.");
