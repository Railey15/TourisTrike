/// Bump the version and effective date together whenever the displayed text changes.
const bookingTermsVersion = '1.1';
const bookingTermsEffectiveDate = 'October 1, 2026';
const privacyNoticeVersion = '1.1';
const privacyNoticeEffectiveDate = 'September 30, 2026';

const bookingTermsSections = <({String heading, String body})>[
  (
    heading: '1. Booking Information',
    body:
        'The tourist must review the selected tour, date and time, passenger and tricycle counts, pickup and drop-off locations, itinerary, and total amount before confirming a booking. The confirmed record is the basis for tour coordination and payment. Any later change is subject to availability and the applicable booking and cancellation rules.',
  ),
  (
    heading: '2. Pickup and Drop-off Locations',
    body:
        'The driver uses the pickup and drop-off locations confirmed in the booking. The tourist must select accurate, accessible locations within the supported service area and be ready at the pickup location at the scheduled time. These booked locations cannot be changed by the tourist after confirmation.',
  ),
  (
    heading: '3. Tour Schedule and Time of Stay',
    body:
        'The itinerary states the included Time of Stay for each destination. Tour pickup is available from 5:00 AM through 4:59 PM in the local municipality time zone. Travel, arrival, and departure times may vary with actual conditions.',
  ),
  (
    heading: '4. Additional Waiting Fees',
    body:
        'One municipality-configured waiting interval after the included Time of Stay is free. The first additional charge applies at the end of that grace interval; later charges follow the configured interval and rate. The applicable rate is displayed before confirmation. Finalized waiting charges are added to the outstanding balance.',
  ),
  (
    heading: '5. Payment',
    body:
        'The tourist agrees to pay the amounts required for the booking through an available payment method. The applicable downpayment, remaining balance, and finalized additional charges are due according to the checkout and tour payment flow. Payment is settled only when the service records the required confirmation.',
  ),
  (
    heading: '6. Cash Payments',
    body:
        'Where cash payment is available, the assigned driver may need to confirm receipt in the service. Selecting cash does not itself confirm payment.',
  ),
  (
    heading: '7. Cancellation',
    body:
        'Cancellation follows the policy shown during booking. Refund eligibility depends on the cancellation time, confirmed payments, tour status, and applicable reason. Ordinary cancellation may be unavailable after the tour starts.',
  ),
  (
    heading: '8. Driver Assignment',
    body:
        'Driver assignment depends on availability and the service assignment process. A booking does not reserve a particular driver until that driver is officially assigned.',
  ),
  (
    heading: '9. Tourist Responsibilities',
    body:
        'The tourist must provide accurate booking information, attend the agreed pickup, follow reasonable safety instructions, respect the driver and destinations, and avoid conduct that endangers others or disrupts the tour.',
  ),
  (
    heading: '10. Service Interruptions and Emergencies',
    body:
        'Severe weather, road or destination closures, emergencies, government restrictions, and similar conditions may affect the schedule or safe operation. The service and responsible tourism office may assist with the affected booking when needed.',
  ),
  (
    heading: '11. Location Information',
    body:
        'When location features are used, location information may support navigation, pickup and drop-off coordination, tour progress, and safety as described in the Privacy Notice.',
  ),
  (
    heading: '12. Reviews and Ratings',
    body:
        'After an eligible completed tour, the tourist and driver may submit ratings and feedback. Reviews should concern the actual tour and must not contain abusive, discriminatory, threatening, fraudulent, or knowingly false content.',
  ),
  (
    heading: '13. Acceptance',
    body:
        'By checking the agreement box and confirming the booking, the tourist acknowledges review of the booking details and accepts these terms and the applicable cancellation and payment policies.',
  ),
];

const cancellationPolicySummary =
    'More than 12 hours before the scheduled tour: standard cancellation is allowed; confirmed test payments are eligible for full refund processing.\n\nWithin 12 hours, including exactly 12 hours: late cancellation applies, the payment is non-refundable, and the assigned Driver payout may become eligible.\n\nOnce the tour has started: standard cancellation is unavailable; use Report Problem or Emergency Termination.\n\nAll package bookings, including same-day bookings, require the 50% down payment only after all required Drivers accept.';

const privacyNoticeSections = <({String heading, String body})>[
  (
    heading: '1. Information We Process',
    body:
        'We process account details such as your name, email address, and contact information; booking and travel-group details; pickup and drop-off locations and itinerary; payment status and transaction references; and reviews and ratings. Location information is processed when you use location-dependent features. Driver documents are handled separately in Driver registration.',
  ),
  (
    heading: '2. Why We Use It',
    body:
        'We use this information to create and manage accounts, process bookings, coordinate Tourists and assigned Driver-Tour Guides, support navigation and tour progression, record payments and booking obligations, provide safety and customer support, handle cancellations, refunds, and disputes, enable authorized tourism-office administration, and maintain system security and audit records.',
  ),
  (
    heading: '3. Location Information',
    body:
        'When you use location-dependent features, TourisTrike may process location information for navigation, pickup and drop-off coordination, active tour tracking, tour progression, and safety. This notice does not mean GPS is continuously collected outside those features.',
  ),
  (
    heading: '4. Who Can Access Information',
    body:
        'Tourists can access their own account and bookings. Assigned Drivers receive information needed to perform the tour. The relevant Municipal Tourism Office and authorized Provincial Administrator receive operational information within their scope. System Administrators have access according to existing authorization. Service providers receive only information needed for their services.',
  ),
  (
    heading: '5. Third-Party Services',
    body:
        'TourisTrike uses Supabase for account and application data, PayMongo for supported online payments, and Google Maps and Places for location and route features. Driver identity verification uses Didit, which may process a government-issued ID, selfie/liveness information, and facial comparison information. The Didit integration stores a session reference and verification result; Driver documents uploaded separately in TourisTrike remain separate. These providers process information as needed to provide the relevant service.',
  ),
  (
    heading: '6. Retention and Security',
    body:
        'Information is retained as needed to provide services, maintain booking and transaction records, address disputes, protect security, and meet applicable operational or legal requirements. TourisTrike uses access controls and other safeguards appropriate to these functions.',
  ),
  (
    heading: '7. Your Privacy Rights',
    body:
        'You may request appropriate access to or correction of your information and raise privacy concerns through your responsible Municipal Tourism Office or the TourisTrike support process. Official project privacy contact: to be configured by the project administrator.',
  ),
  (
    heading: '8. Acknowledgment',
    body:
        'By proceeding with Tourist registration, you confirm that you have read and understood this Privacy Notice.',
  ),
];
