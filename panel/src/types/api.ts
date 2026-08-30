/**
 * Hand-maintained mirror of the DRF contract for version 2.0.
 *
 * `npm run generate:types` regenerates src/types/openapi.d.ts from
 * backend/openapi.yaml — use that when you need the full schema; these aliases are
 * what the UI actually consumes.
 *
 * Terminology follows specification section 2: a **customer** is the stranded
 * motorist, a **driver** is a ShirazTyres technician.
 */

export type JobStatus =
  | "submitted"
  | "dispatching"
  | "assigned"
  | "accepted"
  | "en_route"
  | "arrived"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "unclaimed";

export type JobSource = "website" | "app" | "panel" | "phone";
export type LocationSource = "device" | "browser" | "map_pin" | "staff";
export type ConfirmationPath = "confirmed" | "overridden";
export type DispatchMode = "automatic" | "selection";
export type VerificationStatus = "pending" | "approved" | "rejected" | "suspended";
export type DocumentStatus = "pending" | "approved" | "rejected";
export type InvoiceStatus = "draft" | "issued" | "paid" | "void";
export type PaymentMethod = "unspecified" | "card_reader" | "payment_link" | "cash" | "other";

export interface StaffUser {
  id: number;
  name: string;
  email: string;
  role: "owner" | "staff";
  is_active: boolean;
  date_joined: string;
}

export interface Vehicle {
  id: number;
  plate: string;
  display_plate: string;
  description: string;
  make: string;
  model: string;
  colour: string;
  fuel_type: string;
  engine_capacity: number | null;
  year_of_manufacture: number | null;
  co2_emissions: number | null;
  tax_status: string;
  tax_due_date: string | null;
  mot_status: string;
  mot_expiry_date: string | null;
  tyre_size_front: string;
  tyre_size_rear: string;
  tyre_load_index: string;
  tyre_speed_rating: string;
  tyre_pressure_front_psi: number | null;
  tyre_pressure_rear_psi: number | null;
  tyre_size_options: string[];
  is_fitment_ambiguous: boolean;
  tyre_source: "api" | "customer" | "driver" | "staff" | "unknown";
  dvla_fetched_at: string | null;
  tyre_fetched_at: string | null;
  lookup_error: string;
  updated_at: string;
}

export interface JobStatusEvent {
  id: number;
  from_status: string;
  to_status: string;
  note: string;
  actor_type: "system" | "staff" | "driver" | "customer";
  actor_name: string;
  created_at: string;
}

export interface InvoiceLine {
  id: number;
  service_item: number | null;
  kind: "callout" | "part" | "labour" | "other";
  description: string;
  quantity: string;
  unit_price: string;
  line_total: string;
  is_system: boolean;
  sort_order: number;
}

export interface Invoice {
  id: number;
  job: number;
  job_reference: string;
  status: InvoiceStatus;
  status_display: string;
  currency: string;
  vat_rate: string;
  subtotal: string;
  vat_amount: string;
  total: string;
  payment_method: PaymentMethod;
  payment_reference: string;
  notes: string;
  is_editable: boolean;
  lines: InvoiceLine[];
  issued_at: string | null;
  paid_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ServiceItem {
  id: number;
  code: string;
  name: string;
  kind: "callout" | "part" | "labour" | "other";
  unit_price: string;
  unit: string;
  is_active: boolean;
  sort_order: number;
}

export interface DispatchOffer {
  id: number;
  driver: number;
  driver_name: string;
  driver_phone: string;
  rank: number;
  eta_seconds: number | null;
  eta_minutes: number | null;
  distance_metres: number | null;
  state: "offered" | "accepted" | "rejected" | "withdrawn" | "timed_out";
  reason: string;
  offered_at: string;
  responded_at: string | null;
}

export interface DispatchAttempt {
  id: number;
  round_number: number;
  mode: DispatchMode;
  mode_display: string;
  outcome: "pending" | "accepted" | "rejected" | "timed_out" | "no_candidates" | "superseded";
  outcome_display: string;
  radius_km: string;
  timeout_seconds: number;
  candidates_considered: number;
  note: string;
  started_at: string;
  expires_at: string | null;
  resolved_at: string | null;
  offers: DispatchOffer[];
}

export interface Candidate {
  driver_id: number;
  name: string;
  phone: string;
  eta_seconds: number;
  eta_minutes: number;
  distance_metres: number;
}

export interface Job {
  id: number;
  reference: string;
  customer: number | null;
  vehicle: Vehicle | null;
  plate: string;
  contact_name: string;
  contact_phone: string;
  contact_email: string;
  issue_type: string;
  issue_label: string;
  description: string;
  tyre_size: string;
  looked_up_tyre_size: string;
  customer_tyre_size: string;
  tyre_confirmation_path: ConfirmationPath | "";
  disclaimer_accepted_at: string | null;
  tyre_corrected_on_site: boolean;
  tyre_correction_note: string;
  location_text: string;
  latitude: string | null;
  longitude: string | null;
  location_accuracy_m: number | null;
  location_source: LocationSource;
  service_area: number | null;
  service_area_name: string;
  status: JobStatus;
  status_display: string;
  source: JobSource;
  driver: number | null;
  driver_name: string;
  driver_phone: string;
  assigned_staff: StaffUser | null;
  dispatch_rounds: number;
  internal_notes: string;
  cancellation_reason: string;
  eta_seconds: number | null;
  eta_minutes: number | null;
  eta_distance_metres: number | null;
  eta_updated_at: string | null;
  invoice_total: string | null;
  maps_url: string;
  created_at: string;
  updated_at: string;
  dispatch_started_at: string | null;
  assigned_at: string | null;
  accepted_at: string | null;
  en_route_at: string | null;
  arrived_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
}

export interface JobDetail extends Job {
  status_events: JobStatusEvent[];
  invoice: Invoice | null;
  dispatch_attempts: DispatchAttempt[];
}

export interface DriverVehicle {
  id: number;
  plate: string;
  display_plate: string;
  description: string;
  make: string;
  model: string;
  colour: string;
  year_of_manufacture: number | null;
  is_primary: boolean;
  created_at: string;
  updated_at: string;
}

export interface DriverDocument {
  id: number;
  document_type: "insurance" | "licence" | "mot" | "right_to_work" | "other";
  type_display: string;
  file: string;
  reference: string;
  expiry_date: string;
  status: DocumentStatus;
  review_note: string;
  reviewed_at: string | null;
  is_expired: boolean;
  days_to_expiry: number;
  created_at: string;
  updated_at: string;
}

export interface Driver {
  id: number;
  name: string;
  phone: string;
  email: string;
  photo: string | null;
  employment_reference: string;
  verification_status: VerificationStatus;
  status_display: string;
  verification_note: string;
  approved_at: string | null;
  is_active: boolean;
  is_online: boolean;
  went_online_at: string | null;
  service_area_ids: number[];
  latitude: string | null;
  longitude: string | null;
  location_accuracy_m: number | null;
  location_updated_at: string | null;
  notes: string;
  vehicles: DriverVehicle[];
  documents: DriverDocument[];
  missing_documents: string[];
  expired_documents: string[];
  active_jobs: number;
  created_at: string;
  updated_at: string;
  last_login_at: string | null;
}

export interface DriverMapRow {
  id: number;
  name: string;
  phone: string;
  is_online: boolean;
  verification_status: VerificationStatus;
  latitude: string | null;
  longitude: string | null;
  location_accuracy_m: number | null;
  location_updated_at: string | null;
  vehicle_plate: string;
  active_jobs: number;
}

export interface Compliance {
  counts: { pending: number; approved: number; suspended: number; online: number };
  pending_documents: number;
  expiring: {
    document_id: number;
    driver_id: number;
    driver_name: string;
    document_type: string;
    expiry_date: string;
    days_to_expiry: number;
    is_expired: boolean;
  }[];
}

export interface ServiceArea {
  id: number;
  name: string;
  boundary: Record<string, unknown>;
  centre: { latitude: number; longitude: number } | null;
  is_active: boolean;
  priority: number;
  dispatch_overrides: Record<string, unknown>;
  notes: string;
  driver_count: number;
  created_at: string;
  updated_at: string;
}

export interface SettingSpec {
  key: string;
  group: "dispatch" | "pricing" | "service_areas" | "drivers" | "notifications" | "operational";
  type: "string" | "text" | "int" | "decimal" | "bool" | "choice" | "json";
  label: string;
  help_text: string;
  choices: { value: string; label: string }[];
  default: unknown;
  value: unknown;
}

export interface SettingsDocument {
  values: Record<string, unknown>;
  specs: SettingSpec[];
}

export interface JobStats {
  submitted: number;
  dispatching: number;
  assigned: number;
  accepted: number;
  en_route: number;
  arrived: number;
  in_progress: number;
  unclaimed: number;
  completed_today: number;
  open_total: number;
  drivers_online: number;
}

export interface Paginated<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export interface ApiErrorBody {
  detail: string;
  errors: Record<string, string[]>;
}

export const STATUS_LABELS: Record<JobStatus, string> = {
  submitted: "Submitted",
  dispatching: "Finding a driver",
  assigned: "Assigned",
  accepted: "Accepted",
  en_route: "On the way",
  arrived: "Arrived",
  in_progress: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
  unclaimed: "Unclaimed",
};

/**
 * Mirrors Job.ALLOWED_TRANSITIONS on the server so the panel does not offer a move the
 * API will refuse. The API remains the authority.
 */
export const NEXT_STATUSES: Record<JobStatus, JobStatus[]> = {
  submitted: ["dispatching", "assigned", "cancelled"],
  dispatching: ["assigned", "unclaimed", "cancelled"],
  assigned: ["accepted", "dispatching", "unclaimed", "cancelled"],
  accepted: ["en_route", "dispatching", "cancelled"],
  en_route: ["arrived", "dispatching", "cancelled"],
  arrived: ["in_progress", "cancelled"],
  in_progress: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
  unclaimed: ["dispatching", "assigned", "cancelled"],
};
