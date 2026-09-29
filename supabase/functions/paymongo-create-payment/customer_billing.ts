type TouristProfile = {
  full_name?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  mobile?: string | null;
} | null;

export function resolveCheckoutBilling({
  requestedName,
  requestedEmail,
  profile,
  authEmail,
  authPhone,
}: {
  requestedName?: string;
  requestedEmail?: string;
  profile: TouristProfile;
  authEmail?: string | null;
  authPhone?: string | null;
}): Record<string, string> {
  const name = requestedName?.trim() || profile?.full_name?.trim() ||
    [profile?.first_name, profile?.last_name]
      .map((part) => part?.trim() ?? "")
      .filter(Boolean)
      .join(" ");
  const email = requestedEmail?.trim() || authEmail?.trim() || "";
  const phone = profile?.mobile?.trim() || authPhone?.trim() || "";
  const billing: Record<string, string> = {};
  if (name) billing.name = name;
  if (email) billing.email = email;
  if (phone) billing.phone = phone;
  return billing;
}
