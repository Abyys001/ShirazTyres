/**
 * The customer-facing slice of the API (specification 4).
 *
 * Deliberately narrower than the panel's copy: the fields section 4.7 withholds are not
 * modelled here, because the server does not send them and nothing in this app should
 * be written expecting them.
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

export type ConfirmationPath = "confirmed" | "overridden";

export interface Customer {
  id: number;
  name: string;
  phone: string | null;
  email: string;
  photo_url: string;
  is_phone_verified: boolean;
  is_email_verified: boolean;
  job_count: number;
  created_at: string;
}

export interface Vehicle {
  id: number;
  plate: string;
  display_plate: string;
  description: string;
  make: string;
  model: string;
  colour: string;
  year_of_manufacture: number | null;
  tyre_size_front: string;
  tyre_size_rear: string;
  tyre_load_index: string;
  tyre_speed_rating: string;
  tyre_pressure_front_psi: number | null;
  tyre_pressure_rear_psi: number | null;
  tyre_size_options: string[];
  is_fitment_ambiguous: boolean;
  tyre_source: string;
  lookup_error: string;
}

/** Exactly the six fields section 4.6 allows. No position, no phone number. */
export interface AssignedDriver {
  first_name: string;
  photo: string | null;
  vehicle_make: string;
  vehicle_model: string;
  vehicle_colour: string;
  vehicle_plate: string;
}

export interface InvoiceLine {
  id: number;
  description: string;
  quantity: string;
  unit_price: string;
  line_total: string;
  is_system: boolean;
}

export interface Invoice {
  id: number;
  status: string;
  status_display: string;
  currency: string;
  vat_rate: string;
  subtotal: string;
  vat_amount: string;
  total: string;
  lines: InvoiceLine[];
}

export interface CustomerJob {
  id: number;
  reference: string;
  vehicle: Vehicle | null;
  plate: string;
  issue_type: string;
  issue_label: string;
  description: string;
  tyre_size: string;
  looked_up_tyre_size: string;
  customer_tyre_size: string;
  tyre_confirmation_path: ConfirmationPath | "";
  location_text: string;
  latitude: string | null;
  longitude: string | null;
  status: JobStatus;
  status_display: string;
  driver: AssignedDriver | null;
  eta_seconds: number | null;
  eta_minutes: number | null;
  eta_updated_at: string | null;
  can_cancel: boolean;
  invoice: Invoice | null;
  created_at: string;
  accepted_at: string | null;
  en_route_at: string | null;
  arrived_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  timeline?: { status: string; label: string; at: string }[];
  notice?: string;
}

export interface PublicConfig {
  issue_types: { value: string; label: string }[];
  callout_fee: string | null;
  callout_fee_enabled: boolean;
  vat_rate: string;
  currency: string;
  business_hours: Record<string, string[]>;
  is_open: boolean;
  out_of_hours_behaviour: string;
  out_of_hours_message: string;
  out_of_area_message: string;
  customer_cancel_until: string;
  service_areas: { id: number; name: string; centre: { latitude: number; longitude: number } | null }[];
}

export interface Coverage {
  covered: boolean;
  area: string | null;
  message: string;
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

/** What the customer is shown. `assigned` is internal — they see "finding a driver". */
export const STATUS_LABELS: Record<JobStatus, string> = {
  submitted: "Request received",
  dispatching: "Finding a technician",
  assigned: "Finding a technician",
  accepted: "Technician assigned",
  en_route: "On the way to you",
  arrived: "Arrived",
  in_progress: "Work in progress",
  completed: "Completed",
  cancelled: "Cancelled",
  unclaimed: "We are calling round",
};

export const STATUS_BLURB: Record<JobStatus, string> = {
  submitted: "We have your request and are looking for the nearest technician.",
  dispatching: "We are offering your job to technicians near you.",
  assigned: "We are waiting for a technician to confirm.",
  accepted: "Your technician has accepted and will set off shortly.",
  en_route: "Your technician is on the way.",
  arrived: "Your technician is with you.",
  in_progress: "Work has started on your vehicle.",
  completed: "All done. Thank you for calling ShirazTyres.",
  cancelled: "This request was cancelled.",
  unclaimed: "Nobody is free right now — the office is calling round for you.",
};
