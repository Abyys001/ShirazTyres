"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import dynamic from "next/dynamic";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef, useState } from "react";

import { SiteHeader } from "@/components/site-header";
import { EMPTY_DECISION, TyreConfirmation, type TyreDecision } from "@/components/tyre-confirmation";
import { Button, Card, Field, Input, Notice, Select, Steps, Textarea } from "@/components/ui";
import type { Position } from "@/components/location-picker";
import { api, fieldError } from "@/lib/client-api";
import type { Coverage, CustomerJob, PublicConfig, Vehicle } from "@/types/api";

// Leaflet needs `window`, so the picker only loads in the browser.
const LocationPicker = dynamic(() => import("@/components/location-picker").then((m) => m.LocationPicker), {
  ssr: false,
  loading: () => <div className="h-24 animate-pulse rounded-lg bg-surface-raised" />,
});

const STEPS = ["Vehicle", "Tyre size", "Location", "What happened"];

function Request() {
  const router = useRouter();
  const params = useSearchParams();

  const [plate, setPlate] = useState(params.get("plate")?.toUpperCase() ?? "");
  const [vehicle, setVehicle] = useState<Vehicle | null>(null);
  const [decision, setDecision] = useState<TyreDecision>(EMPTY_DECISION);
  const [position, setPosition] = useState<Position | null>(null);
  const [coverage, setCoverage] = useState<Coverage | null>(null);
  const [issueType, setIssueType] = useState("");
  const [description, setDescription] = useState("");
  const [locationText, setLocationText] = useState("");

  const config = useQuery({
    queryKey: ["public-config"],
    queryFn: () => api<PublicConfig>("/public/config"),
    staleTime: 5 * 60_000,
  });

  const lookup = useMutation({
    mutationFn: (registration: string) =>
      api<Vehicle>(`/public/vehicle-lookup/${encodeURIComponent(registration.replace(/\s/g, ""))}`),
    onSuccess: (data) => {
      setVehicle(data);
      setDecision(EMPTY_DECISION);
    },
  });

  const checkCoverage = useMutation({
    mutationFn: (point: Position) =>
      api<Coverage>("/public/coverage", {
        method: "POST",
        body: JSON.stringify({ latitude: point.latitude, longitude: point.longitude }),
      }),
    onSuccess: setCoverage,
  });

  const submit = useMutation({
    mutationFn: () =>
      api<CustomerJob>("/my/jobs", {
        method: "POST",
        body: JSON.stringify({
          plate,
          issue_type: issueType,
          description,
          location_text: locationText,
          latitude: position?.latitude,
          longitude: position?.longitude,
          location_accuracy_m: position?.accuracy ?? undefined,
          location_source: position?.source,
          tyre_confirmation: {
            confirmation_path: decision.path,
            tyre_size: decision.tyreSize,
            load_index: decision.loadIndex,
            speed_rating: decision.speedRating,
            disclaimer_accepted: decision.disclaimerAccepted,
          },
        }),
      }),
    onSuccess: (job) => router.replace(`/jobs/${job.id}`),
  });

  // The marketing-site widget hands over a plate and a position; picking them up
  // here is what stops the customer typing the same things twice.
  const prefilled = useRef(false);
  useEffect(() => {
    if (prefilled.current) return;
    prefilled.current = true;

    const startingPlate = params.get("plate");
    if (startingPlate) lookup.mutate(startingPlate);

    const latitude = Number(params.get("lat"));
    const longitude = Number(params.get("lng"));
    if (Number.isFinite(latitude) && Number.isFinite(longitude) && latitude !== 0) {
      handlePosition({ latitude, longitude, accuracy: null, source: "browser" });
    }
    // Runs once, on the values the URL arrived with.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function handlePosition(next: Position) {
    setPosition(next);
    setCoverage(null);
    checkCoverage.mutate(next);
  }

  const tyreDone =
    decision.path === "confirmed" ||
    (decision.path === "overridden" && decision.disclaimerAccepted && decision.tyreSize.trim() !== "");
  const covered = coverage?.covered ?? false;
  const step = !vehicle ? 0 : !tyreDone ? 1 : !covered ? 2 : 3;

  const closed = config.data && !config.data.is_open;
  const refusing = closed && config.data?.out_of_hours_behaviour === "refuse";

  return (
    <>
      <SiteHeader signedIn />
      <main className="mx-auto max-w-2xl space-y-4 px-4 py-8">
        <Steps current={step} labels={STEPS} />

        {closed ? (
          <Notice tone={refusing ? "error" : "warning"}>{config.data?.out_of_hours_message}</Notice>
        ) : null}

        <Card title="1. Your registration">
          <form
            className="flex flex-wrap items-end gap-3"
            onSubmit={(event) => {
              event.preventDefault();
              lookup.mutate(plate);
            }}
          >
            <div className="flex-1">
              <Field label="Registration plate" error={lookup.isError ? lookup.error.message : null}>
                <Input
                  value={plate}
                  onChange={(event) => setPlate(event.target.value.toUpperCase())}
                  placeholder="AB12 CDE"
                  className="font-mono text-lg tracking-[0.2em]"
                  autoCapitalize="characters"
                  required
                />
              </Field>
            </div>
            <Button type="submit" disabled={!plate || lookup.isPending}>
              {lookup.isPending ? "Checking…" : "Look up"}
            </Button>
          </form>
        </Card>

        {vehicle ? (
          <Card title="2. Confirm your tyre size">
            <TyreConfirmation vehicle={vehicle} decision={decision} onChange={setDecision} />
          </Card>
        ) : null}

        {tyreDone ? (
          <Card title="3. Where are you?">
            <div className="space-y-3">
              <LocationPicker value={position} onChange={handlePosition} />

              {checkCoverage.isPending ? <p className="text-sm text-ink-muted">Checking we cover that…</p> : null}
              {coverage && !coverage.covered ? (
                <Notice tone="error">{coverage.message || config.data?.out_of_area_message}</Notice>
              ) : null}
              {coverage?.covered ? (
                <Field label="Anything that helps us find you (optional)">
                  <Input
                    value={locationText}
                    onChange={(event) => setLocationText(event.target.value)}
                    placeholder="Hard shoulder, just past the Perivale exit"
                  />
                </Field>
              ) : null}
            </div>
          </Card>
        ) : null}

        {tyreDone && covered ? (
          <Card title="4. What happened?">
            <form
              className="space-y-4"
              onSubmit={(event) => {
                event.preventDefault();
                submit.mutate();
              }}
            >
              <Field label="Problem" error={fieldError(submit.error, "issue_type")}>
                <Select value={issueType} onChange={(event) => setIssueType(event.target.value)} required>
                  <option value="" disabled>
                    Choose…
                  </option>
                  {(config.data?.issue_types ?? []).map((issue) => (
                    <option key={issue.value} value={issue.value}>
                      {issue.label}
                    </option>
                  ))}
                </Select>
              </Field>

              <Field label="Anything else we should know? (optional)">
                <Textarea
                  rows={3}
                  value={description}
                  onChange={(event) => setDescription(event.target.value)}
                  placeholder="Nearside front. Two children in the car."
                />
              </Field>

              {config.data?.callout_fee_enabled ? (
                <Notice>
                  A call-out fee of £{config.data.callout_fee} applies, plus parts and labour and VAT at{" "}
                  {config.data.vat_rate}%. You pay once the work is finished.
                </Notice>
              ) : null}

              {submit.isError ? <Notice tone="error">{submit.error.message}</Notice> : null}

              <Button type="submit" size="lg" className="w-full" disabled={!issueType || submit.isPending}>
                {submit.isPending ? "Sending…" : "Send my request"}
              </Button>
            </form>
          </Card>
        ) : null}
      </main>
    </>
  );
}

export default function RequestPage() {
  return (
    <Suspense>
      <Request />
    </Suspense>
  );
}
