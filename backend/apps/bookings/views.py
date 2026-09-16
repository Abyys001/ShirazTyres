from django.db.models import Count, Q
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status as http_status
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import Customer, StaffUser
from apps.accounts.permissions import IsApprovedDriver, IsCustomer, IsStaff
from apps.billing.models import Invoice, ServiceItem
from apps.billing.serializers import AddLineSerializer, InvoiceSerializer, PaymentSerializer
from apps.billing.services import add_line, issue_invoice, mark_paid, remove_line
from apps.configuration.hours import business_hours_status
from apps.dispatch.engine import accept_offer, assign_manually, dispatch_job, reject_offer
from apps.dispatch.models import DispatchOffer
from apps.dispatch.serializers import (
    CandidatePreviewSerializer,
    DriverOfferSerializer,
    ManualAssignSerializer,
    RejectSerializer,
)
from apps.drivers.models import Driver
from apps.vehicles.models import ConfirmationPath, CustomerVehicle
from apps.vehicles.services import record_confirmation

from .filters import JobFilter
from .models import Job, JobStatusEvent
from .serializers import (
    CancelSerializer,
    CustomerJobDetailSerializer,
    CustomerJobSerializer,
    DriverJobSerializer,
    JobCreateSerializer,
    JobDetailSerializer,
    JobMapSerializer,
    JobSerializer,
    JobStaffUpdateSerializer,
    JobStatsSerializer,
    JobStatusUpdateSerializer,
    TyreCorrectionSerializer,
)
from .services import correct_tyre_on_site, create_job, customer_may_cancel, transition_job

JOB_QUERYSET = Job.objects.select_related(
    "vehicle", "driver", "assigned_staff", "customer", "service_area", "invoice"
)

#: Statuses a driver may set from the app, and what each one means on the road.
DRIVER_TRANSITIONS = {
    Job.Status.EN_ROUTE,
    Job.Status.ARRIVED,
    Job.Status.IN_PROGRESS,
    Job.Status.COMPLETED,
}


def _build_job(serializer: JobCreateSerializer, *, source: str, customer=None, staff=None) -> Job:
    data = dict(serializer.validated_data)
    confirmation = data.pop("tyre_confirmation", None)
    vehicle = serializer.resolve_vehicle(data.pop("plate", ""))

    looked_up = vehicle.tyre_size_front if vehicle else ""
    data["looked_up_tyre_size"] = looked_up
    data["tyre_size"] = looked_up

    customer_vehicle = None
    if confirmation:
        path = confirmation["confirmation_path"]
        data["tyre_confirmation_path"] = path
        if path == ConfirmationPath.OVERRIDDEN:
            data["customer_tyre_size"] = confirmation["tyre_size"]
            data["tyre_size"] = confirmation["tyre_size"]
            data["disclaimer_accepted_at"] = timezone.now()

        if customer is not None and vehicle is not None:
            customer_vehicle, _ = CustomerVehicle.objects.get_or_create(
                customer=customer, vehicle=vehicle
            )
            record_confirmation(
                customer_vehicle,
                path=path,
                looked_up_size=looked_up,
                customer_size=confirmation.get("tyre_size", ""),
                load_index=confirmation.get("load_index", ""),
                speed_rating=confirmation.get("speed_rating", ""),
                disclaimer_accepted=confirmation.get("disclaimer_accepted", False),
            )

    return create_job(
        vehicle=vehicle,
        customer_vehicle=customer_vehicle,
        customer=customer,
        source=source,
        created_by_staff=staff,
        **data,
    )


# ---------------------------------------------------------------- customer ----


@extend_schema(tags=["customer-jobs"])
class CustomerJobViewSet(viewsets.ModelViewSet):
    """The customer website and the customer app both live here — section 3.1 keeps
    the logic in the backend so the second client stays cheap."""

    permission_classes = [IsCustomer]
    http_method_names = ["get", "post"]
    throttle_scope = "job_create"
    queryset = Job.objects.none()

    def get_throttles(self):
        """The limit is on reporting call-outs, not on reading your own.

        A scope set on the viewset covers every action in it, so an app polling
        its live ETA every thirty seconds spent the same ten-an-hour budget that
        submitting a puncture needs — and a customer who had watched their own
        job for five minutes got a 429 when they finally pressed send. Only the
        write is rationed.
        """
        if self.action != "create":
            return []
        return super().get_throttles()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Job.objects.none()
        return (
            JOB_QUERYSET.filter(customer=self.request.user)
            .prefetch_related("status_events", "driver__vehicles", "invoice__lines")
        )

    def get_serializer_class(self):
        if self.action == "create":
            return JobCreateSerializer
        if self.action == "retrieve":
            return CustomerJobDetailSerializer
        return CustomerJobSerializer

    def create(self, request, *args, **kwargs):
        customer: Customer = request.user
        hours = business_hours_status()
        if hours.behaviour == "refuse" and not hours.is_open:
            raise ValidationError({"out_of_hours": [hours.message]})

        data = {key: value for key, value in request.data.items() if value not in (None, "")}
        data.setdefault("contact_name", customer.display_name)
        if customer.phone:
            data.setdefault("contact_phone", customer.phone)
        if customer.email:
            data.setdefault("contact_email", customer.email)

        serializer = JobCreateSerializer(data=data)
        serializer.is_valid(raise_exception=True)

        source = Job.Source.APP if request.data.get("source") == Job.Source.APP else Job.Source.WEBSITE
        job = _build_job(serializer, source=source, customer=customer)

        payload = CustomerJobDetailSerializer(job).data
        if not hours.is_open and hours.behaviour == "accept_with_notice":
            payload["notice"] = hours.message
        return Response(payload, status=http_status.HTTP_201_CREATED)

    @extend_schema(request=CancelSerializer, responses={200: CustomerJobDetailSerializer})
    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        job = self.get_object()
        if not customer_may_cancel(job):
            raise ValidationError(
                {"detail": ["This job can no longer be cancelled from the app. Please call us."]}
            )
        serializer = CancelSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        job = transition_job(
            job, Job.Status.CANCELLED,
            actor_type=JobStatusEvent.Actor.CUSTOMER,
            note=serializer.validated_data.get("reason", "Cancelled by the customer."),
        )
        return Response(CustomerJobDetailSerializer(job).data)

    @extend_schema(responses={200: CustomerJobSerializer})
    @action(detail=False, methods=["get"])
    def active(self, request):
        """What the app opens on: the job in progress, if there is one."""
        job = self.get_queryset().exclude(status__in=Job.TERMINAL_STATUSES).first()
        if job is None:
            return Response({"job": None})
        return Response({"job": CustomerJobDetailSerializer(job).data})


# ------------------------------------------------------------------ driver ----


@extend_schema(tags=["driver-jobs"])
class DriverOfferListView(ListAPIView):
    """Live offers for this driver. In selection mode there may be several at once."""

    permission_classes = [IsApprovedDriver]
    pagination_class = None
    serializer_class = DriverOfferSerializer
    queryset = DispatchOffer.objects.none()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return DispatchOffer.objects.none()
        return (
            DispatchOffer.objects.filter(
                driver=self.request.user, state=DispatchOffer.State.OFFERED
            )
            .select_related("attempt__job__vehicle")
            .order_by("rank")
        )

    def list(self, request, *args, **kwargs):
        offers = self.get_queryset()
        return Response(
            [
                {
                    **DriverOfferSerializer(offer).data,
                    "job": DriverJobSerializer(offer.attempt.job).data,
                }
                for offer in offers
            ]
        )


@extend_schema(tags=["driver-jobs"])
class DriverJobViewSet(viewsets.ReadOnlyModelViewSet):
    """The driver app's job list, the accept/reject pair, and on-site invoicing."""

    permission_classes = [IsApprovedDriver]
    serializer_class = DriverJobSerializer
    queryset = Job.objects.none()

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Job.objects.none()
        return JOB_QUERYSET.filter(driver=self.request.user).prefetch_related("invoice__lines")

    def _offered_job(self, pk) -> Job:
        """Accept and reject act on a job that is offered, not one already assigned to us."""
        offer = (
            DispatchOffer.objects.select_related("attempt__job")
            .filter(driver=self.request.user, attempt__job_id=pk, state=DispatchOffer.State.OFFERED)
            .first()
        )
        if offer is None:
            raise ValidationError({"detail": ["This job is no longer available to you."]})
        return offer.attempt.job

    @extend_schema(request=None, responses={200: DriverJobSerializer})
    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        job = accept_offer(request.user, self._offered_job(pk))
        return Response(DriverJobSerializer(job).data)

    @extend_schema(request=RejectSerializer, responses={200: dict})
    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        """Section 6.3 — a positive 'no' beats silence, in both modes."""
        serializer = RejectSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reject_offer(
            request.user, self._offered_job(pk), reason=serializer.validated_data.get("reason", "")
        )
        return Response({"detail": "Job rejected."})

    @extend_schema(request=JobStatusUpdateSerializer, responses={200: DriverJobSerializer})
    @action(detail=True, methods=["post"])
    def status(self, request, pk=None):
        serializer = JobStatusUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        new_status = serializer.validated_data["status"]
        if new_status not in DRIVER_TRANSITIONS:
            raise ValidationError({"status": ["A driver cannot set that status."]})

        job = self.get_object()
        if new_status == Job.Status.COMPLETED:
            raise ValidationError(
                {"status": ["Complete the job through the invoice endpoint so the invoice is recorded."]}
            )
        job = transition_job(
            job, new_status, driver=request.user,
            actor_type=JobStatusEvent.Actor.DRIVER,
            note=serializer.validated_data.get("note", ""),
        )
        return Response(DriverJobSerializer(job).data)

    @extend_schema(request=TyreCorrectionSerializer, responses={200: DriverJobSerializer})
    @action(detail=True, methods=["post"], url_path="correct-tyre")
    def correct_tyre(self, request, pk=None):
        serializer = TyreCorrectionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        job = correct_tyre_on_site(
            self.get_object(),
            serializer.validated_data["tyre_size"],
            driver=request.user,
            note=serializer.validated_data.get("note", ""),
        )
        return Response(DriverJobSerializer(job).data)

    @extend_schema(responses={200: InvoiceSerializer})
    @action(detail=True, methods=["get"])
    def invoice(self, request, pk=None):
        return Response(InvoiceSerializer(self.get_object().invoice).data)

    @extend_schema(request=AddLineSerializer, responses={200: InvoiceSerializer})
    @action(detail=True, methods=["post"], url_path="invoice/lines")
    def add_invoice_line(self, request, pk=None):
        """Section 7.1 step 3 — the driver adds parts and labour on site."""
        serializer = AddLineSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        service_item = None
        if data.get("service_item_id"):
            service_item = ServiceItem.objects.filter(pk=data["service_item_id"], is_active=True).first()
            if service_item is None:
                raise ValidationError({"service_item_id": ["No such item in the price list."]})

        invoice = self.get_object().invoice
        add_line(
            invoice,
            description=data.get("description", ""),
            unit_price=data.get("unit_price"),
            quantity=data["quantity"],
            kind=data["kind"],
            service_item=service_item,
        )
        invoice.refresh_from_db()
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(
        request=None,
        responses={200: InvoiceSerializer},
        parameters=[OpenApiParameter("line_id", int, OpenApiParameter.PATH)],
    )
    @action(detail=True, methods=["delete"], url_path="invoice/lines/(?P<line_id>[^/.]+)")
    def remove_invoice_line(self, request, pk=None, line_id=None):
        invoice = self.get_object().invoice
        line = invoice.lines.filter(pk=line_id).first()
        if line is None:
            raise ValidationError({"detail": ["No such line on this invoice."]})
        remove_line(line)
        invoice.refresh_from_db()
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(request=PaymentSerializer, responses={200: DriverJobSerializer})
    @action(detail=True, methods=["post"])
    def complete(self, request, pk=None):
        """Section 7.1 steps 5 and 6, as one action: take payment, close the job."""
        serializer = PaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        job = self.get_object()

        if job.status != Job.Status.IN_PROGRESS:
            raise ValidationError({"status": ["Start the work before completing the job."]})

        method = serializer.validated_data.get("payment_method", "")
        reference = serializer.validated_data.get("payment_reference", "")
        invoice = job.invoice
        if method:
            mark_paid(invoice, payment_method=method, reference=reference)
        else:
            issue_invoice(invoice, driver=request.user, reference=reference)

        job = transition_job(
            job, Job.Status.COMPLETED, driver=request.user,
            actor_type=JobStatusEvent.Actor.DRIVER, note="Work complete, invoice issued.",
        )
        return Response(DriverJobSerializer(job).data)


# ------------------------------------------------------------------- staff ----


@extend_schema(tags=["jobs"])
class JobViewSet(viewsets.ModelViewSet):
    """The panel's main surface: queue, detail, manual entry, status, dispatch control."""

    queryset = JOB_QUERYSET
    permission_classes = [IsStaff]
    filterset_class = JobFilter
    search_fields = ["reference", "contact_name", "contact_phone", "vehicle__plate", "location_text"]
    ordering_fields = ["created_at", "status", "updated_at"]
    http_method_names = ["get", "post", "patch"]

    def get_serializer_class(self):
        if self.action == "create":
            return JobCreateSerializer
        if self.action == "partial_update":
            return JobStaffUpdateSerializer
        if self.action == "retrieve":
            return JobDetailSerializer
        return JobSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.action == "retrieve":
            return queryset.prefetch_related(
                "status_events", "invoice__lines", "dispatch_attempts__offers__driver"
            )
        return queryset

    def create(self, request, *args, **kwargs):
        """Manual entry — the phone-in path. Section 5's ``submitted`` row covers it."""
        serializer = JobCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        source = request.data.get("source", Job.Source.PHONE)
        if source not in Job.Source.values:
            source = Job.Source.PHONE

        phone = serializer.validated_data["contact_phone"]
        customer = Customer.objects.filter(phone=phone).first()
        job = _build_job(serializer, source=source, customer=customer, staff=request.user)
        return Response(JobDetailSerializer(job).data, status=http_status.HTTP_201_CREATED)

    @extend_schema(request=JobStatusUpdateSerializer, responses={200: JobDetailSerializer})
    @action(detail=True, methods=["patch", "post"])
    def status(self, request, pk=None):
        serializer = JobStatusUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        assigned_staff = None
        if serializer.validated_data.get("assigned_staff_id"):
            assigned_staff = StaffUser.objects.filter(
                pk=serializer.validated_data["assigned_staff_id"], is_active=True
            ).first()
            if assigned_staff is None:
                raise ValidationError({"assigned_staff_id": ["No such active staff member."]})

        job = transition_job(
            self.get_object(),
            serializer.validated_data["status"],
            staff=request.user,
            actor_type=JobStatusEvent.Actor.STAFF,
            note=serializer.validated_data.get("note", ""),
            assigned_staff=assigned_staff,
            force=serializer.validated_data.get("force", False),
        )
        return Response(JobDetailSerializer(job).data)

    @extend_schema(request=ManualAssignSerializer, responses={200: JobDetailSerializer})
    @action(detail=True, methods=["post"])
    def assign(self, request, pk=None):
        serializer = ManualAssignSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        driver = Driver.objects.filter(pk=serializer.validated_data["driver_id"]).first()
        if driver is None:
            raise ValidationError({"driver_id": ["No such driver."]})
        job = assign_manually(self.get_object(), driver, staff=request.user)
        return Response(JobDetailSerializer(job).data)

    @extend_schema(request=None, responses={200: JobDetailSerializer})
    @action(detail=True, methods=["post"], url_path="dispatch")
    def redispatch(self, request, pk=None):
        """Re-run dispatch by hand — the way out of the unclaimed queue.

        Named ``redispatch`` because ``dispatch`` is APIView's own request entry point."""
        job = self.get_object()
        if not job.is_dispatchable:
            raise ValidationError({"detail": ["This job is not in a state that can be dispatched."]})
        job.dispatch_rounds = 0
        job.save(update_fields=["dispatch_rounds"])
        dispatch_job(job, note="Dispatch restarted by staff.")
        job.refresh_from_db()
        return Response(JobDetailSerializer(job).data)

    @extend_schema(responses={200: CandidatePreviewSerializer(many=True)})
    @action(detail=True, methods=["get"])
    def candidates(self, request, pk=None):
        """Who would be offered this job, without offering it."""
        from decimal import Decimal

        from apps.dispatch.engine import rank_candidates
        from apps.geo.services import area_setting

        job = self.get_object()
        radius = Decimal(str(area_setting(job.service_area, "dispatch.initial_radius_km")))
        candidates = rank_candidates(job, radius_km=radius, limit=25)
        return Response(
            CandidatePreviewSerializer(
                [
                    {
                        "driver_id": candidate.driver.pk,
                        "name": candidate.driver.name,
                        "phone": candidate.driver.phone,
                        "eta_seconds": candidate.eta_seconds,
                        "eta_minutes": max(1, round(candidate.eta_seconds / 60)),
                        "distance_metres": candidate.distance_metres,
                    }
                    for candidate in candidates
                ],
                many=True,
            ).data
        )

    @extend_schema(responses={200: JobMapSerializer(many=True)})
    @action(detail=False, methods=["get"])
    def map(self, request):
        """
        Every live call-out that has a position, for the panel's map.

        Unpositioned jobs are excluded rather than dropped at the far end: a job
        with no coordinates cannot be drawn, and sending it only to have the
        client filter it costs the same bytes on every driver ping. They are
        still on the board — this endpoint feeds the map, not the queue.
        """
        jobs = (
            Job.objects.filter(latitude__isnull=False, longitude__isnull=False)
            .exclude(status__in=Job.TERMINAL_STATUSES)
            .select_related("driver")
            .order_by("-created_at")
        )
        return Response(JobMapSerializer(jobs, many=True).data)

    @extend_schema(responses={200: JobStatsSerializer})
    @action(detail=False, methods=["get"])
    def stats(self, request):
        today = timezone.localtime().replace(hour=0, minute=0, second=0, microsecond=0)
        counts = Job.objects.aggregate(
            submitted=Count("pk", filter=Q(status=Job.Status.SUBMITTED)),
            dispatching=Count("pk", filter=Q(status=Job.Status.DISPATCHING)),
            assigned=Count("pk", filter=Q(status=Job.Status.ASSIGNED)),
            accepted=Count("pk", filter=Q(status=Job.Status.ACCEPTED)),
            en_route=Count("pk", filter=Q(status=Job.Status.EN_ROUTE)),
            arrived=Count("pk", filter=Q(status=Job.Status.ARRIVED)),
            in_progress=Count("pk", filter=Q(status=Job.Status.IN_PROGRESS)),
            unclaimed=Count("pk", filter=Q(status=Job.Status.UNCLAIMED)),
            completed_today=Count("pk", filter=Q(status=Job.Status.COMPLETED, completed_at__gte=today)),
        )
        counts["open_total"] = sum(
            counts[key] for key in
            ("submitted", "dispatching", "assigned", "accepted", "en_route", "arrived", "in_progress")
        )
        counts["drivers_online"] = Driver.objects.filter(is_online=True).count()
        return Response(JobStatsSerializer(counts).data)


@extend_schema(tags=["jobs"], responses={200: InvoiceSerializer})
class JobInvoiceView(APIView):
    """Staff-side invoice edits, for the cases the driver could not close on site."""

    permission_classes = [IsStaff]

    def get(self, request, pk):
        invoice = Invoice.objects.filter(job_id=pk).first()
        if invoice is None:
            raise ValidationError({"detail": ["This job has no invoice."]})
        return Response(InvoiceSerializer(invoice).data)

    @extend_schema(request=AddLineSerializer, responses={200: InvoiceSerializer})
    def post(self, request, pk):
        invoice = Invoice.objects.filter(job_id=pk).first()
        if invoice is None:
            raise ValidationError({"detail": ["This job has no invoice."]})
        serializer = AddLineSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        service_item = (
            ServiceItem.objects.filter(pk=data["service_item_id"]).first()
            if data.get("service_item_id") else None
        )
        add_line(
            invoice,
            description=data.get("description", ""),
            unit_price=data.get("unit_price"),
            quantity=data["quantity"],
            kind=data["kind"],
            service_item=service_item,
        )
        invoice.refresh_from_db()
        return Response(InvoiceSerializer(invoice).data)
