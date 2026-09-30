/// Bump the version and effective date together whenever the displayed text changes.
const bookingTermsVersion = '1.0';
const bookingTermsEffectiveDate = 'September 30, 2026';
const privacyNoticeVersion = '1.0';
const privacyNoticeEffectiveDate = 'September 30, 2026';

const bookingTermsSections = <({String heading, String body})>[
  (
    heading: '1. Booking Information',
    body:
        'You are responsible for reviewing the details of your booking before confirmation, including the selected tour package, date and time, number of tourists, number of tricycles, pickup location, drop-off location, destinations, and total booking amount.\n\nOnce the booking is confirmed, changes may be subject to availability and the applicable booking and cancellation policies.',
  ),
  (
    heading: '2. Pickup and Drop-off Locations',
    body:
        'The Driver-Tour Guide will use the pickup and drop-off locations provided or selected during booking. You are responsible for providing accurate and accessible locations within the supported TourisTrike service area.\n\nYou should be ready at the selected pickup location at the scheduled time.',
  ),
  (
    heading: '3. Tour Schedule and Time of Stay',
    body:
        'Each destination may have an included Time of Stay indicated in the booking itinerary. The included duration represents the allotted stay at that destination.\n\nIf you remain at a destination beyond the included Time of Stay, an additional waiting fee may apply according to the rate established for the applicable municipality and displayed by TourisTrike.',
  ),
  (
    heading: '4. Additional Waiting Fees',
    body:
        'Additional waiting charges may apply when the included Time of Stay at a destination is exceeded.\n\nBefore confirming the booking, you should review the applicable waiting-fee information shown by TourisTrike. Any finalized waiting charges incurred during the tour will be added to the outstanding booking balance.',
  ),
  (
    heading: '5. Payment',
    body:
        'You agree to pay the amounts required for the booking using the payment methods available through TourisTrike.\n\nA booking may require payment according to the payment rules displayed during checkout. Any remaining balance and finalized additional charges must be settled when required by the system.\n\nA payment is considered settled only after TourisTrike receives or records the required payment confirmation.',
  ),
  (
    heading: '6. Cash Payments',
    body:
        'When Cash is selected as an available payment method, the corresponding Driver-Tour Guide may be required to confirm receipt of the payment through TourisTrike.\n\nSelecting Cash alone does not mean that the payment has already been confirmed.',
  ),
  (
    heading: '7. Cancellation',
    body:
        'Booking cancellations are subject to the TourisTrike Cancellation Policy displayed during booking.\n\nAny applicable refund will depend on the time of cancellation, payment already made, tour status, and reason for cancellation.\n\nTourisTrike may restrict ordinary cancellation once the tour has already started.',
  ),
  (
    heading: '8. Driver Assignment',
    body:
        "Driver-Tour Guide assignment is subject to availability and TourisTrike's assignment process. A booking does not guarantee a particular Driver unless that Driver has been officially assigned to the booking.",
  ),
  (
    heading: '9. Tourist Responsibilities',
    body:
        'During the tour, you are expected to provide accurate booking information, be present at the agreed pickup location, follow reasonable safety instructions, respect the Driver-Tour Guide and tourism destinations, and avoid conduct that may endanger other persons or interfere with the tour.',
  ),
  (
    heading: '10. Service Interruptions and Emergencies',
    body:
        'Tour schedules may be affected by circumstances such as severe weather, road closures, emergencies, destination closures, government restrictions, or other conditions affecting safe transportation.\n\nWhen necessary, TourisTrike and the responsible tourism office may assist in determining the appropriate action for the affected booking.',
  ),
  (
    heading: '11. Location Information',
    body:
        'When location-dependent TourisTrike features are used, location information may be processed to support functions such as navigation, pickup and drop-off coordination, tour progress, safety, and other features described in the TourisTrike Privacy Notice.',
  ),
  (
    heading: '12. Reviews and Ratings',
    body:
        'After an eligible completed tour, Tourists and Driver-Tour Guides may be allowed to submit ratings and feedback.\n\nReviews should relate to the actual tour experience and must not contain abusive, discriminatory, threatening, fraudulent, or knowingly false content.',
  ),
  (
    heading: '13. Acceptance',
    body:
        'By checking the agreement box and confirming the booking, you confirm that you have reviewed the booking information and agree to these Booking Terms and Conditions and the applicable cancellation and payment policies.',
  ),
];

const cancellationPolicySummary =
    'More than 24 hours before the scheduled tour: standard cancellation is allowed; confirmed payments may be eligible for refund processing.\n\nWithin 24 hours, including exactly 24 hours: late cancellation applies and confirmed payments are normally non-refundable, subject to exceptional review.\n\nOnce the tour has started: standard cancellation is unavailable; use support or emergency assistance.\n\nSame-day bookings follow the existing no-downpayment rule.';

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
        'TourisTrike uses Supabase for account and application data, PayMongo for supported online payments, and Google Maps and Places for location and route features. These providers process information as needed to provide the relevant service.',
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
