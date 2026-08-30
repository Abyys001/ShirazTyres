# ShirazTyres — Specification and Roadmap

**Version 2.0 — 28 August 2026**
Living document. Supersedes version 1.0 and all earlier notes.

### Changes from version 1.0

| Change | Section |
|---|---|
| Customers now have a Flutter mobile app in addition to the website | 3, 4, 15 |
| Customers now have accounts, with Google sign-in and phone OTP | 4.1 |
| Tyre specification confirmation step added before request submission | 4.3 |
| Customer location sharing specified explicitly | 4.4 |
| **Drivers can now reject requests** — reverses the v1.0 rule | 6 |
| Driver app distribution reclassified as employee-only | 3.2, 15 |

---

## 1. Vision

ShirazTyres is an emergency tyre dispatch platform for London. A motorist with a damaged tyre reports the problem from their phone browser or the ShirazTyres mobile app. A field technician is dispatched, arrives with the correct tyre already identified, completes the work, and issues the invoice on site.

**The goal:** get a qualified technician to a stranded motorist as fast as possible, with the right tyre, and with the customer knowing who is coming and when.

Two principles make this work:

1. **The customer supplies no technical information.** They enter a registration plate. The system identifies the vehicle and determines the tyre size, so the technician arrives prepared rather than diagnosing on site.
2. **Dispatch is handled by the system.** Requests are matched to available technicians automatically, rather than by staff reading a list and making phone calls.

### Success criteria

- A customer can submit an emergency request in under 60 seconds, from either the website or the app
- The tyre specification is attached to the job, and confirmed by the customer, before dispatch
- A technician is secured within seconds of the request arriving
- The customer knows the technician's name, vehicle, plate, and arrival time
- The owner can change dispatch behaviour, pricing, and timing from the panel without a developer

---

## 2. Terminology

The two central terms were used in opposite senses during early discussion. Anyone joining this project should read this section before any other.

| Term | Definition |
|---|---|
| **Customer** | The stranded motorist with the damaged tyre. Uses the **website and the customer mobile app**. Has a user account. |
| **Driver** | A ShirazTyres field technician who travels to the customer. A **direct employee**. Uses the **driver mobile app**. |

Throughout this document, "driver" always means the employee technician, never the customer.

Two vehicle concepts exist and must not share a table:

| Term | Definition |
|---|---|
| **Customer vehicle** | The broken-down car. Looked up by plate to determine tyre size. |
| **Driver vehicle** | The technician's service van. Registered by the driver, tied to their insurance documents. |

---

## 3. System overview

### 3.1 Surfaces

Four client surfaces share one backend:

| Surface | Users | Platform |
|---|---|---|
| **Customer website** | Stranded motorists | Web, mobile-first |
| **Customer app** | Stranded motorists | Flutter — Android first, then iOS |
| **Owner panel** | Owner and office staff | Web |
| **Driver app** | Field technicians | Flutter — Android first, then iOS |

All four communicate exclusively through a single backend API. No surface connects to the database or to any third-party service directly.

The customer website and customer app expose the same functionality against the same API. The website exists because a stranded motorist will not stop to install an app; the app exists for repeat customers and for the smoother location sharing that native permissions allow.

### 3.2 Distribution

The two mobile apps require different distribution routes, and this affects Phase 6.

**Customer app — public App Store and Google Play.** It serves the general public and qualifies for normal listing without difficulty.

**Driver app — restricted distribution.** Apple rejects applications under Guideline 3.2 when they are built for a specific business or organisation, explicitly including that organisation's employees, rather than for general distribution. A ShirazTyres-employee-only application matches that description directly. Two routes avoid rejection:

- **Unlisted App Distribution** — the app is hosted on the App Store but does not appear in search or browse; access is by direct link. Apple reviews the unlisted request separately and typically takes 5–7 business days.
- **Apple Business Manager custom app distribution** — private distribution to a named organisation.

Google Play offers an equivalent private-app route for organisation-restricted applications.

**Action required in Phase 0:** decide which route the driver app takes. Submitting it for standard public review is likely to be rejected and will cost weeks.

The owner panel is a web application and requires no store presence.

---

## 4. Customer experience

### 4.1 Account and sign-in

Customers hold an account. Both the website and the app support the same two sign-in methods:

- **Google sign-in** (OAuth)
- **Phone number with OTP**

Both routes resolve to the same account record. A customer who signs in with Google and later uses phone OTP on the same number reaches the same account and the same job history.

### 4.2 Vehicle lookup

The customer enters their registration plate. The system performs the lookup described in Section 9 and returns the vehicle's make, model, colour, year, and the manufacturer's specified tyre size.

### 4.3 Tyre specification confirmation

The retrieved tyre specification is displayed to the customer **before the request can be submitted**, and requires an explicit decision. This step exists because different trims of the same make, model, and year can take different tyre sizes, and because the technician loads the van based on this figure.

The flow has exactly two paths:

**Path A — the customer confirms the specification is correct.**
They proceed directly to finalising the request. The confirmed specification is attached to the job.

**Path B — the customer does not confirm.**
1. A notice is displayed stating that any mismatch or resulting problem is the customer's responsibility.
2. The customer must acknowledge that notice to continue.
3. The tyre specification fields become editable, and the customer enters their own values.
4. The customer finalises the request.

Every job records which path was taken and, where Path B was used, both the original looked-up specification and the customer-supplied values. This matters when a technician arrives with a tyre that does not fit.

### 4.4 Location

The customer shares their location so the technician can find them. Two capture methods:

- **Customer app:** native device location permission, giving the higher accuracy needed at the roadside.
- **Website:** browser geolocation, with a map-pin fallback for customers who decline the permission or whose position is imprecise.

A postcode is not accepted as a substitute. It is not precise enough on a dual carriageway or in a multi-storey car park.

If the resulting position falls outside an active service area, the request is refused with the configured out-of-area message rather than accepted as a job nobody can reach.

### 4.5 Submitting a request

The complete customer form:

1. Registration plate — triggers the lookup
2. Tyre specification confirmation — Section 4.3
3. Location — Section 4.4
4. Issue type, selected from the configured list, plus optional free text
5. Submit

### 4.6 Tracking a job

After submission, the customer follows their job from either surface while signed in:

- Current job status
- Once a driver is assigned: the driver's first name, photo, vehicle make, model, colour, and registration plate
- A live-updating estimated arrival time

**The customer does not see the driver's position on a map.** The ETA is recalculated on the backend each time the driver's location updates, and only the resulting figure is sent to the customer. This keeps an employee's live position out of the customer-facing surfaces, and prevents the customer watching a stationary pin at a junction and drawing conclusions from it.

### 4.7 Information withheld from the customer

Insurance policy numbers, uploaded document scans, and the driver's personal phone number are never shown to the customer. They exist so the business can verify that the driver is road-legal and insured. Customer-to-driver contact routes through a masked number or the office line.

---

## 5. Job lifecycle

| Status | Trigger | Visible to |
|---|---|---|
| `submitted` | Customer completes the request, or staff enter it manually | Owner panel |
| `dispatching` | The system is matching the job to a driver | Owner panel |
| `assigned` | A driver has been given or has taken the job | Owner panel, driver app |
| `accepted` | The driver has accepted | All surfaces |
| `en_route` | The driver has started travelling | All surfaces |
| `arrived` | The driver marks arrival on site | Owner panel, customer surfaces |
| `in_progress` | Work has begun | Owner panel, customer surfaces |
| `completed` | The driver marks the job done and submits the invoice | Owner panel, job history |
| `cancelled` | Cancelled by the customer or by staff | Owner panel |
| `unclaimed` | Escalation exhausted without securing a driver | Owner panel — requires staff intervention |

---

## 6. Dispatch

The owner selects the active mode in the panel. Both modes are built, and the same job flows through whichever is enabled.

### 6.1 Automatic assignment mode

The system selects the best-ranked driver and assigns the job to them. The driver receives it and may **accept** or **reject** it.

- Accept → the job proceeds to `accepted`
- Reject → the job returns to `dispatching` and is assigned to the next-best driver

### 6.2 Driver selection mode

The request is offered simultaneously to the nearest eligible drivers, who choose for themselves whether to take it. Each may **accept** or **reject**.

- The first driver to accept takes the job; it is immediately withdrawn from every other driver's list
- Reject removes the job from that driver's list only, and the offer stands with the remaining drivers

### 6.3 Rejection

Drivers can reject requests in both modes. This is a deliberate reversal of the version 1.0 rule.

Rejection gives the system a positive signal that a driver will not take a job, which is materially better than silence. In automatic assignment mode, a rejection reassigns immediately rather than waiting out a timeout. In driver selection mode, it narrows the pool of drivers still being waited on.

### 6.4 Driver ranking

Candidate drivers are ranked by **routing-engine travel time, not straight-line distance.** In London, a driver 800 metres away across the river can be twenty minutes out while one three kilometres away arrives in eight. Straight-line ranking would systematically select the wrong driver.

A driver enters the candidate pool only when they are online, verified, not already on a job, and within the matching service area.

### 6.5 Timeouts and escalation

Rejection covers the case where a driver will not take a job. Timeouts cover the case where a driver does not respond at all — a dead phone, a tunnel, a job that overran. Both are needed.

**Automatic assignment mode:**
1. Assign to the best-ranked driver
2. Rejection, or no response within the timeout → assign to the next-best driver and alert the owner
3. After the configured number of attempts → mark `unclaimed`

**Driver selection mode:**
1. Offer to the nearest *N* drivers
2. All reject, or no acceptance within the timeout → widen the radius and offer to the next group
3. Still nothing → fall back to automatic assignment or mark `unclaimed`, per configuration

Starting defaults, all configurable:

| Setting | Default |
|---|---|
| Driver selection acceptance timeout | 60 seconds |
| Automatic assignment response timeout | 90 seconds |
| Drivers per offer batch | 5 |
| Initial offer radius | 5 km |
| Radius increment per round | 3 km |
| Maximum escalation attempts | 3 |

These should be reviewed against observed driver behaviour before launch.

---

## 7. Payment

> **Assumption requiring confirmation.** This section assumes nothing is charged online at booking, and that a single payment is taken after the work is complete. If the call-out fee should instead be charged upfront, that change brings a payment processor into the request flow, requires Strong Customer Authentication at booking, and requires automatic refunds for jobs that go unclaimed. Estimated additional effort: 1.5 weeks in Phase 2.

### 7.1 Model

1. A **call-out fee** is configured in the owner panel.
2. When a job is created, that fee is attached automatically as the first line of the invoice.
3. On site, the driver adds service items — parts, labour, anything else.
4. The app totals the invoice and applies VAT.
5. The customer pays the total once the work is finished.
6. The driver marks the job complete, and the invoice is recorded against it.

### 7.2 Implementation notes

- **VAT must be built in from the start.** Tyre services are standard-rated, and retrofitting VAT into a pricing model afterwards is painful and error-prone.
- Payment capture method — card reader in the van, payment link by SMS, or cash — is an operational decision that shapes the driver app's invoice screen. **Still to be decided** (Section 16).
- Every invoice is stored against its job for reporting and dispute resolution.

---

## 8. Driver onboarding and verification

A driver receives no jobs until an administrator approves them.

### 8.1 Registration

1. Phone number and OTP
2. Profile: name, photograph
3. Vehicle: registration plate — make, model, and colour auto-fill from the plate lookup
4. Documents: insurance certificate, driving licence, and MOT certificate, each uploaded with its expiry date

### 8.2 Verification

Status moves from `pending` to `approved` or `rejected`, set by an administrator in the owner panel. Only `approved` drivers enter the dispatch pool.

### 8.3 Document expiry

The system tracks every document's expiry date, warns the owner in advance, and **automatically suspends a driver whose insurance lapses**. The warning threshold is configurable; 30 days is a reasonable default.

---

## 9. Vehicle and tyre lookup

Two separate data sources are required. Treating this as one integration is a common and costly mistake.

### 9.1 DVLA Vehicle Enquiry Service

The official UK government API. Free, with no per-lookup charge. Returns make, model, colour, fuel type, engine size, year of manufacture, CO2 emissions, tax status, and MOT status.

**It returns no tyre size.** No such field exists in the response.

Registration is free but requires an application, and approval typically takes between one and fourteen days. DVLA issues **one API key per company** and applies rate limits according to the subscribed usage plan. **Apply in Phase 0** — this has genuine lead time.

### 9.2 Tyre fitment data

A separate commercial provider supplies the manufacturer's standard fitment: size, width, aspect ratio, offset, load index, and pressures. UK Vehicle Data Ltd is one option among several. Typically billed per lookup or on a monthly plan.

### 9.3 Handling

- **Cache results by plate.** This controls cost and keeps usage within DVLA's rate limit.
- **The customer confirmation step in Section 4.3 is the fallback for ambiguity.** Where trims differ, the customer corrects the value and accepts responsibility for doing so.
- The driver can override the specification on site when the vehicle does not match what was recorded.
- The same lookup is available as a standalone tool in the owner panel, independent of any job.

---

## 10. Maps and routing

OpenStreetMap is the mapping foundation. This is three procurement decisions, not one.

| Requirement | Options |
|---|---|
| Map tiles | Commercial OSM provider — MapTiler, Stadia, Geoapify, Thunderforest — or self-hosted OpenMapTiles |
| Geocoding | Self-hosted Nominatim, or Geoapify / LocationIQ |
| Routing and ETA | Self-hosted OSRM or Valhalla, or GraphHopper |

### 10.1 Production tiles

**Do not point production at OSM's own tile server.** The OpenStreetMap Foundation's tile usage policy warns commercial services explicitly that access may be withdrawn at any point, leaving them unable to serve paying customers. There is no SLA, and heavy use can be blocked without notice. For a dispatch platform this would be an outage of the core product.

Use a commercial OSM-based provider — typically tens of pounds per month at this scale — or self-host.

OSM attribution must be shown clearly on every map, normally bottom-right, and must not be hidden behind a toggle or moved off-screen.

### 10.2 ETA accuracy

A default OSRM installation uses static road speeds and produces optimistic times in central London. Either use a traffic-aware routing provider or apply a time-of-day correction factor calibrated against real journey times. **An ETA that is consistently fifteen minutes wrong is worse than showing no ETA.**

### 10.3 Client libraries

- Driver app: `flutter_map`
- Owner panel: Leaflet or MapLibre GL JS

---

## 11. Driver location tracking

### 11.1 Behaviour

- Tracking runs **only while the driver is toggled online**. Never outside working hours.
- Updates are sent on a distance filter — every 50 to 100 metres — with a time cap, backing off to near-zero when the vehicle is stationary. Continuous streaming would exhaust the battery within a shift.
- Position updates reach the owner panel over WebSocket for a live map.
- The customer's ETA is recalculated from these updates; the position itself is never sent to a customer surface.

### 11.2 Platform requirements

- Android's `ACCESS_BACKGROUND_LOCATION` requires a written justification submitted to Google Play.
- iOS "Always" location permission requires justification at App Review.

Both are approvable for a genuine dispatch application, but the paperwork should be planned rather than discovered.

Use `flutter_background_geolocation` or an equivalent proven package. Background location is notoriously difficult on both platforms and is not worth building from scratch.

---

## 12. Configuration catalogue

Everything below is adjustable by the owner in the panel, without developer involvement.

### Dispatch
- Mode: automatic assignment or driver selection
- Drivers per offer batch
- Initial offer radius, and increment per round
- Driver selection acceptance timeout
- Automatic assignment response timeout
- Maximum escalation attempts
- Escalation fallback behaviour: retry, switch mode, or mark unclaimed

### Pricing
- Call-out fee amount
- Call-out fee enabled or disabled
- VAT rate
- Service item price list

### Service areas
- Active areas and their boundary polygons
- Per-area driver pools
- Per-area dispatch overrides
- Out-of-area message text

### Drivers
- Document types required for approval
- Document expiry warning threshold
- Automatic suspension on document expiry: on or off
- Maximum concurrent jobs per driver

### Notifications
- Which events notify the owner, and through which channel
- Which events notify the customer, and through which channel
- Message templates

### Operational
- Business hours, and out-of-hours behaviour
- Issue types offered on the customer request form
- Job cancellation rules

---

## 13. Data model

| Entity | Key fields |
|---|---|
| **Customer** | Name, phone, email, Google account link, verification status |
| **CustomerVehicle** | Plate, DVLA data, looked-up tyre specification, customer-supplied specification, confirmation path taken |
| **Driver** | Profile, employment reference, verification status, availability, current location, service area |
| **DriverVehicle** | Plate, make, model, colour, linked driver |
| **Document** | Driver, type, file, expiry date, verification status |
| **Job** | Customer, customer vehicle, location, issue type, status, assigned driver, timestamps |
| **DispatchAttempt** | Job, drivers contacted, mode, outcome — accepted, rejected, or timed out — timestamp |
| **Invoice** | Job, line items, VAT, total, payment status |
| **DriverLocation** | Driver, coordinates, accuracy, timestamp. Time-series, with a retention policy. |
| **ServiceArea** | Name, boundary polygon, active flag, dispatch overrides |
| **StaffUser** | Name, email, password hash, role |
| **Setting** | Key, value, type — backs the configuration catalogue |

Two entities carry more weight than their size suggests:

**`CustomerVehicle`** stores both the looked-up and the customer-supplied tyre specification, along with which confirmation path the customer took. When a technician arrives with a tyre that does not fit, this record settles what was shown, what was entered, and who accepted responsibility.

**`DispatchAttempt`** makes dispatch auditable. When a job goes unclaimed, it shows exactly which drivers were contacted, when, and whether each rejected or simply never responded.

---

## 14. Technology stack

| Layer | Choice | Rationale |
|---|---|---|
| Backend API | Node.js + NestJS (TypeScript) | Strong typing and clear structure for a system with this many moving parts |
| Database | PostgreSQL + PostGIS | PostGIS handles service-area polygons and proximity queries natively |
| Real-time | WebSocket | Live driver positions and job updates |
| Owner panel | React (Next.js) | Fast to build and maintain a dashboard |
| Customer website | Next.js | Server-rendered, fast on poor mobile connections |
| Customer app | Flutter (Dart) | Shares the codebase approach with the driver app |
| Driver app | Flutter (Dart), Riverpod or Bloc | One codebase for Android and iOS |
| Customer sign-in | Google OAuth + OTP provider | Both routes resolve to one account record |
| OTP / SMS | Twilio Verify or Firebase Phone Auth | Handles the SMS infrastructure |
| Push notifications | Firebase Cloud Messaging | Covers Android and iOS across both apps |
| Vehicle data | DVLA VES + commercial tyre API | Section 9 |
| Maps | Commercial OSM tiles + routing provider | Section 10 |
| Payments | Stripe | UK standard, SCA-compliant |

---

## 15. Roadmap

Assumes one backend developer, one frontend developer, one mobile developer, and part-time project management and QA. The mobile developer is a change from version 1.0; two Flutter applications is more than one person can carry alongside web work.

| Phase | Deliverable | Duration |
|---|---|---|
| **0. Discovery** | DVLA application submitted; tyre provider selected; map and routing provider selected; service-area boundary defined; payment capture method decided; **driver app distribution route decided** | 2 weeks |
| **1. Backend core** | Data model, service areas, customer accounts with Google and OTP sign-in, staff and driver authentication, job engine, dispatch engine with both modes and rejection handling, settings framework | 6–7 weeks |
| **2. Customer website** | Sign-in, request form, plate lookup, tyre confirmation flow, location capture, out-of-area handling, job tracking with ETA | 4–5 weeks |
| **3. Owner panel** | Job queue, live driver map, manual job entry, driver management and document verification, standalone lookup tool, full settings section, unclaimed-job alerts | 5–6 weeks |
| **4. Driver app — Android** | Onboarding, document upload, online/offline, both dispatch modes, accept and reject, job status flow, on-site invoicing | 6–8 weeks |
| **5. Customer app — Android** | Sign-in, request form, tyre confirmation, native location sharing, job tracking, job history | 5–6 weeks |
| **6. Location and ETA** | Background tracking, live panel map, routing integration, ETA calculation and publishing | 3–4 weeks |
| **7. iOS pass** | Both applications: builds, permission justifications, signing, store listings, restricted distribution for the driver app, device testing | 3 weeks |
| **8. QA, UAT, launch** | End-to-end testing across four surfaces, pilot with real drivers | 4–5 weeks |

**Sequential total: approximately 9–11 months.**

Phases 2 through 5 can run in parallel once Phase 1 is stable, which brings this to roughly **6.5–7.5 months** with the team above.

### Critical path

Phase 1 blocks everything else. The dispatch engine and the settings framework should be built first and built carefully, because the other four surfaces are configured against them.

### Note on the two customer surfaces

The customer website and the customer app deliver the same functionality through different clients. Building both means the request flow, tyre confirmation, and job tracking are implemented twice. Keeping all logic in the backend and treating both clients as thin presentation layers is what keeps the second implementation cheap rather than doubling the cost.

### Phase 0 lead-time items

| Item | Lead time |
|---|---|
| DVLA VES API approval | 1–14 days |
| Apple Developer Program account | Days, plus a Mac for builds |
| Apple Unlisted App request, if chosen for the driver app | 5–7 business days, requested separately from review |
| Google Play background location declaration | Submitted with the first release |
| Tyre data provider contract | Varies |

---

## 16. Open items

| # | Item | Blocks |
|---|---|---|
| 1 | **Payment timing** — confirm the Section 7 assumption: single payment after service, nothing charged at booking | Phase 2 |
| 2 | **Payment capture method** — card reader, SMS payment link, or cash | Phase 4 |
| 3 | **Driver app distribution** — Unlisted App Distribution or Apple Business Manager | Phase 7 |
| 4 | **Service area boundary** — the precise London polygon | Phase 1 |
| 5 | **Existing website** — whether the current site is replaced or the new customer flow is integrated into it | Phase 2 |
| 6 | **Timeout defaults** — review the Section 6.5 figures against real driver behaviour | Not blocking; configurable |

---

## 17. Out of scope for version 1

Recorded so they are not forgotten, and so the data model does not preclude them:

- Cities beyond London — the service-area model supports expansion without code changes
- Driver shift scheduling and rota management
- Stock and inventory tracking for tyres carried in vans
- Customer ratings and feedback
- Multi-branch operation

---

## 18. Compliance note

Continuous location tracking of employees, storage of insurance and licence documents, and customer account data are all regulated processing under UK GDPR. The client has confirmed that employment arrangements and internal rules are established and handled on their side.

The build-side commitments reflected in this design are: tracking limited strictly to online hours, a defined retention period for `DriverLocation` records, access controls on driver documents, and customer account data held only as long as the account exists.

This document is not legal advice. Data protection arrangements should be reviewed by whoever handles compliance for the business before launch.