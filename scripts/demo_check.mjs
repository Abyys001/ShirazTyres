/**
 * The whole call-out, across all three surfaces, against a running stack.
 *
 * The pytest suite proves each publisher sends what it should; this proves the
 * sockets, the channel layer and the three token scopes agree once they are all
 * real — which is the thing a demo actually depends on and the thing a unit test
 * cannot see. Run it before showing the system to anyone.
 *
 *   node scripts/demo_check.mjs                 # against localhost:8000
 *   API_BASE=http://localhost:8010 node scripts/demo_check.mjs
 *
 * It needs `make seed` to have run, and the technician on 07700900301 to be free
 * — a driver already on a job is correctly offered nothing, and the run would
 * fail on a behaviour that is right.
 */
const BASE = (process.env.API_BASE ?? "http://localhost:8000").replace(/\/$/, "");
const API = `${BASE}/api/v1`;
const WS = `${BASE.replace(/^http/, "ws")}/ws`;

const log = (...a) => console.log(...a);
const t0 = Date.now();
const ms = () => String(Date.now() - t0).padStart(6) + "ms";

async function api(path, { method = "GET", token, body } = {}) {
  const res = await fetch(API + path, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data; try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${text.slice(0, 400)}`);
  return data;
}

function openFeed(name, path, token) {
  const events = [];
  const ws = new WebSocket(`${WS}${path}?token=${encodeURIComponent(token)}`);
  const ready = new Promise((resolve, reject) => {
    ws.addEventListener("open", () => resolve());
    ws.addEventListener("error", (e) => reject(new Error(`${name} ws error`)));
    ws.addEventListener("close", (e) => { if (!events.length) reject(new Error(`${name} ws closed code=${e.code}`)); });
  });
  ws.addEventListener("message", (m) => {
    const p = JSON.parse(m.data);
    events.push({ at: Date.now() - t0, ...p });
    log(`${ms()}  [${name}] ${p.event}`);
  });
  return {
    name, ws, events, ready,
    async wait(eventName, timeout = 12000) {
      const start = Date.now();
      for (;;) {
        const hit = events.find((e) => e.event === eventName);
        if (hit) return hit;
        if (Date.now() - start > timeout) throw new Error(`${name}: timed out waiting for ${eventName}; saw [${events.map(e=>e.event).join(", ")}]`);
        await new Promise((r) => setTimeout(r, 50));
      }
    },
    clear() { events.length = 0; },
    close() { ws.close(); },
  };
}

async function otpToken(phone, audience) {
  const purpose = audience === "driver" ? "driver" : "login";
  const req = await api("/auth/otp/request", { method: "POST", body: { phone, purpose } });
  const code = req.debug_code;
  if (!code) throw new Error(`no debug_code for ${phone}: ${JSON.stringify(req)}`);
  return api(`/auth/${audience}/otp/verify`, { method: "POST", body: { phone, code } });
}

const fail = [];
function check(label, ok, detail = "") {
  log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? "  — " + detail : ""}`);
  if (!ok) fail.push(label);
}

(async () => {
  // ---- auth ----
  const staff = await api("/auth/staff/login", { method: "POST", body: { email: "owner@shiraztyres.co.uk", password: "shiraz1234" } });
  const cust  = await otpToken("07700900101", "customer");
  const drv   = await otpToken("07700900301", "driver");
  log(`${ms()}  tokens: staff/customer/driver OK`);

  const panel    = openFeed("PANEL",    "/panel",    staff.access);
  const customer = openFeed("CUSTOMER", "/customer", cust.access);
  const driver   = openFeed("DRIVER",   "/driver",   drv.access);
  await Promise.all([panel.ready, customer.ready, driver.ready]);
  await Promise.all([panel.wait("connected"), customer.wait("connected"), driver.wait("connected")]);
  log(`${ms()}  three sockets connected`);

  // driver must be on shift and located to be a dispatch candidate
  await api("/driver/online", { method: "POST", token: drv.access, body: { is_online: true } });
  await api("/driver/location", { method: "POST", token: drv.access, body: { latitude: "51.5074", longitude: "-0.1278", accuracy_m: 8 } });
  await panel.wait("driver.location");
  check("driver location reaches the panel live", true);

  panel.clear(); customer.clear(); driver.clear();

  // ---- customer creates a job ----
  const created = await api("/my/jobs", {
    method: "POST", token: cust.access,
    body: {
      plate: "AB12CDE", contact_name: "E2E Customer", contact_phone: "07700900101",
      issue_type: "puncture", description: "Rear nearside puncture, E2E run",
      location_text: "Trafalgar Square, London", latitude: "51.5080", longitude: "-0.1281",
      location_accuracy_m: 10, location_source: "device",
      damaged_positions: [{ position: "rear_left", severity: "flat", note: "" }],
    },
  });
  log(`${ms()}  job #${created.id} ${created.reference} created from the customer app`);

  const panelCreated = await panel.wait("job.created");
  check("panel receives job.created without a refresh", true, `${panelCreated.at}ms after POST returned`);
  check("panel payload carries the job", panelCreated.job?.id === created.id, `job ${panelCreated.job?.id}`);

  const offer = await driver.wait("offer.new", 20000);
  check("technician app receives offer.new", true, `${offer.at}ms`);
  check("offer carries the same job", offer.job?.id === created.id, `job ${offer.job?.id}`);
  const dispatched = panel.events.find((e) => e.event === "dispatch.offered");
  check("panel sees the dispatch round", Boolean(dispatched));

  // ---- driver accepts ----
  panel.clear(); customer.clear(); driver.clear();
  await api(`/driver/jobs/${created.id}/accept`, { method: "POST", token: drv.access });
  await panel.wait("job.status");
  check("panel sees the acceptance live", true);
  const custAccept = await customer.wait("job.status");
  check("customer app sees the acceptance live", true, `status=${custAccept.job?.status}`);
  check("customer payload hides the driver position",
    custAccept.job && !("driver_latitude" in custAccept.job) && !(custAccept.job.driver?.latitude),
    JSON.stringify(Object.keys(custAccept.job?.driver ?? {})));

  // ---- progression to completion ----
  for (const status of ["en_route", "arrived", "in_progress"]) {
    panel.clear(); customer.clear();
    await api(`/driver/jobs/${created.id}/status`, { method: "POST", token: drv.access, body: { status } });
    await panel.wait("job.status");
    await customer.wait("job.status");
    check(`status ${status} reaches panel and customer live`, true);
  }

  // moving the van must refresh the customer's ETA without sending a position
  customer.clear();
  await api("/driver/location", { method: "POST", token: drv.access, body: { latitude: "51.5079", longitude: "-0.1280", accuracy_m: 6 } });
  try {
    const eta = await customer.wait("job.eta", 8000);
    check("customer ETA updates as the van moves", true, `eta=${eta.job?.eta_minutes} min`);
  } catch (e) {
    check("customer ETA updates as the van moves", false, e.message);
  }

  // ---- completion + invoice ----
  panel.clear(); customer.clear();
  await api(`/driver/jobs/${created.id}/complete`, { method: "POST", token: drv.access, body: {} }).catch(async (e) => {
    log("   complete failed, retrying via status endpoint: " + e.message);
    return api(`/driver/jobs/${created.id}/status`, { method: "POST", token: drv.access, body: { status: "completed" } });
  });
  await panel.wait("job.status");
  check("panel sees completion live", true);
  const done = await customer.wait("job.status");
  check("customer sees completion live", true, `status=${done.job?.status}`);

  const invoiceEvent = panel.events.find((e) => e.event.startsWith("invoice."));
  check("panel receives the invoice event", Boolean(invoiceEvent), invoiceEvent?.event ?? "none seen");

  panel.close(); customer.close(); driver.close();
  log(`\n${fail.length ? "FAILURES: " + fail.join(" | ") : "ALL CHECKS PASSED"}`);
  process.exit(fail.length ? 1 : 0);
})().catch((e) => { console.error("\nERROR:", e.message); process.exit(2); });
